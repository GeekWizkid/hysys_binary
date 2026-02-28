import os
import sys
from os import walk
import struct
sys.path.append(os.path.join(os.path.dirname(__file__), "srcsync"))
import threading
import ida_hexrays
import ida_idp
import ida_kernwin
import ida_bytes
import ida_funcs
import idaapi
import ctypes
import configparser
import PdbGeneratorPy
from srcsync.TypeExtractor import TypeExtractor
from srcsync.PEDataExtractor import PEDataExtractor
from srcsync.SymbolExtractor import SymbolExtractor
from srcsync.FunctionDataExtractor import FunctionDataExtractor
from concurrent import futures
from PyQt5 import QtCore, QtWidgets
import glob
import xml.dom.minidom as minidom

def add_cpp_files_to_vcproj(vcproj_path, source_dir):
    """
    Функция добавляет в .vcproj все файлы .cpp из папки source_dir.
    :param vcproj_path: Путь к файлу .vcproj (Visual Studio 2005).
    :param source_dir: Папка, откуда нужно взять .cpp файлы.
    """

    # Считаем все .cpp файлы из указанной папки (рекурсивный поиск не включён)
    cpp_files = glob.glob(os.path.join(source_dir, '*.c'))
    if not cpp_files:
        print(f"В папке '{source_dir}' не найдено файлов .c.")
        return

    # Парсим существующий vcproj-файл
    try:
        dom = minidom.parse(vcproj_path)
    except Exception as e:
        print(f"Ошибка при чтении/парсинге {vcproj_path}: {e}")
        return

    # Ищем элемент <Files> (корневой ребёнок внутри <VisualStudioProject>)
    # а внутри него - нужный <Filter Name="Source Files" ... >
    # или Filter с атрибутом Filter, содержащим "cpp"
    project_node = None
    for node in dom.childNodes:
        if node.nodeName == 'VisualStudioProject':
            project_node = node
            break

    if not project_node:
        print("Не найден корневой элемент <VisualStudioProject> в vcproj.")
        return

    files_node = None
    for node in project_node.childNodes:
        if node.nodeName == 'Files':
            files_node = node
            break

    if not files_node:
        print("Не найден элемент <Files> в vcproj.")
        return

    # Ищем нужный фильтр (например, Source Files).
    # Часто он выглядит так:
    # <Filter Name="Source Files" Filter="cpp;c;cxx;def;odl;idl;hpj;bat;rc" ...>
    source_filter_node = None
    for node in files_node.childNodes:
        if node.nodeName == 'Filter':
            # Проверим атрибуты 'Name' и 'Filter'
            name_attr = node.getAttribute('Name')
            filter_attr = node.getAttribute('Filter')
            # Можно сравнивать как:
            if name_attr.lower() == 'source files' or ('cpp' in filter_attr.lower()):
                source_filter_node = node
                break

    if not source_filter_node:
        print("Не найден фильтр, соответствующий Source Files.")
        return

    # Теперь для каждого .cpp файла, добавим вложенный элемент <File RelativePath="...">
    # Убедимся, что мы не дублируем уже существующие пути.
    existing_files = set()
    for node in source_filter_node.childNodes:
        if node.nodeName == 'File':
            rp = node.getAttribute('RelativePath')
            existing_files.add(rp.lower())

    for cpp_file in cpp_files:
        # Приведём путь к относительному (если нужно), либо используем полный.
        # Здесь для наглядности берём относительный путь (относительно папки vcproj).
        rel_path = os.path.relpath(cpp_file, start=os.path.dirname(vcproj_path))
        # В VC++ 2005 часто используют обратные слеши, можно заменить:
        rel_path = rel_path.replace('/', '\\')

        # Проверим, не добавлен ли уже такой файл
        if rel_path.lower() in existing_files:
            continue

        # Создаём XML-элемент <File RelativePath="rel_path" />
        file_node = dom.createElement('File')
        file_node.setAttribute('RelativePath', rel_path)
        # Добавляем в source_filter_node
        source_filter_node.appendChild(file_node)
    
    # Сохраняем результат обратно в файл
    try:
        with open(vcproj_path, 'w', encoding='utf-8') as f:
            dom.writexml(f, encoding='utf-8')
        print(f"Файл {vcproj_path} обновлён. Добавлено {len(cpp_files)} .cpp-файлов (с учётом пропуска дублей).")
    except Exception as e:
        print(f"Не удалось записать изменения в {vcproj_path}: {e}")



class CheckBoxActionHandler(idaapi.action_handler_t):
    def __init__(self, Cb):
        idaapi.action_handler_t.__init__(self)
        self.Cb = Cb

    def activate(self, Ctx):
        self.Cb.toggle()
        return 1

    def update(self, Ctx):
        return idaapi.AST_ENABLE_ALWAYS

    
class ActionHandler(idaapi.action_handler_t):
        def activate(self, ctx):
            print("[PdbGen] Button clicked!")
            idaapi.get_plugin_instance(PdbGenPlugin).run(0)
            return 1
        
        def update(self, ctx):
            # Включаем кнопку только при открытом файле
            return idaapi.AST_ENABLE if idaapi.get_file_type_name() else idaapi.AST_DISABLE
        
class PdbGenPlugin(idaapi.plugin_t):
    flags = idaapi.PLUGIN_PROC
    comment = "PDBGenerator"
    help = "This is help"
    wanted_name = "PdbGen plugin"
    wanted_hotkey = "Alt-Shift-D"
    ACTION_NAME = "PdbGen:generate"
    ICON_PATH = f"{os.path.dirname(__file__)}/srcsync/ico/pdb.png"
    global PdbGenForm
    PdbGenForm = None
    def load_icon(self, path):
        try:
            pixmap = ida_kernwin.load_custom_icon(path)
            if pixmap != idaapi.BADADDR:
                print(f"[PdbGen] Loaded icon from '{path}'")
                return pixmap
            else:
                print(f"[PdbGen] Failed to load icon from '{path}'")
        except Exception as e:
            print(f"[PdbGen] Exception while loading icon: {e}")
        return 0
    
    def init(self):
        if idaapi.unregister_action(self.ACTION_NAME):
            print("[PdbGen] Old action unregistered.")
        ida_kernwin.create_toolbar('pdbgen', 'PdbGenToolBar')
        action = idaapi.action_desc_t(
            self.ACTION_NAME,  # Идентификатор действия
            "Generate PDB",   # Текст всплывающей подсказки
            self.ActionHandler(),  # Обработчик действия
            self.wanted_hotkey,  # Горячая клавиша
            "Generate PDB for current file",  # Описание
            self.load_icon(self.ICON_PATH)  # Иконка
        )
        if idaapi.register_action(action):
            print("[PdbGen] Action registered.")
        else:
            print("[PdbGen] Failed to register action.")
            
        if idaapi.attach_action_to_toolbar("MainToolBar", self.ACTION_NAME):
            print("[PdbGen] Button added to toolbar.")
        else:
            print("[PdbGen] Failed to add button to toolbar.")
            
        idaapi.register_timer(1000, lambda: self.add_button())
        return idaapi.PLUGIN_KEEP
    
    def add_button(self):
        if idaapi.attach_action_to_toolbar("pdbgen", self.ACTION_NAME):
            print("[PdbGen] Button added to toolbar.")
        else:
            print("[PdbGen] Failed to add button to toolbar.")
            
    class ActionHandler(idaapi.action_handler_t):
        def activate(self, ctx):
            self.CbGeneratePdb()
            return 1
        
        def CbGeneratePdb(self):
            peDataExtractor = PEDataExtractor()
            pdbInfo = peDataExtractor.GetPdbInfo()
            sectionsData = peDataExtractor.GetSectionsData()
            if len(sectionsData) == 0:
                print("[PdbGen] Failed to get sections")       
                return
            if(pdbInfo is None):
                print("[PdbGen] Failed to get pdbInfo")
                return
            print("[PdbGen] Generating pdb")
            typeExtractor = TypeExtractor()
            typeExtractor.GatherData(ExecuteSync = False)
            
            symbolExtractor = SymbolExtractor(typeExtractor)
            publicSymbolsData = symbolExtractor.GetPublics(ExecuteSync = False)
            globalSymbolsData = symbolExtractor.GetGlobals(ExecuteSync = False)
            
            functionDataExtractor = FunctionDataExtractor(typeExtractor)
            functionsData = functionDataExtractor.GetFunctionsData()
            
            enumsData = typeExtractor.GetEnumsData()
            structsData = typeExtractor.GetStructsData()
            complexTypes = typeExtractor.GetComplexTypesData()
            
            

            if idaapi.inf_is_64bit():
                cpuArchitectureType = PdbGeneratorPy.CpuArchitectureType.X86_64
            else:
                cpuArchitectureType = PdbGeneratorPy.CpuArchitectureType.X86
                
            pdbGenerator = PdbGeneratorPy.PdbGenerator(
                complexTypes, structsData, enumsData, functionsData,
                pdbInfo, sectionsData, publicSymbolsData, globalSymbolsData, cpuArchitectureType)
            
            if pdbGenerator.Generate():
                add_cpp_files_to_vcproj("d:\\VsProjects\\re\\hysys\\hysys.vcproj", "d:\\HYSYS 1.1\\hysysSources");
                print("[PdbGen] Pdb generated")       
            else:
                print("[PdbGen] Failed to generate pdb")   
            
        
        def update(self, ctx):
            # Включаем кнопку только при открытом файле
            return idaapi.AST_ENABLE if idaapi.get_file_type_name() else idaapi.AST_DISABLE


    def run(self, Arg):
        if ida_idp.ph.id != ida_idp.PLFM_386:
            print("[PdbGen] Only x86_64/x86 architecture is supported.")
            return

        if "portable executable" not in idaapi.get_file_type_name().lower():
            print("[PdbGen] Only PE files are supported.")
            return
        
        #global PdbGenForm
        #if not PdbGenForm:
        #    PdbGenForm = PdbGenForm()
        #    PdbGenForm.Show()
    
            
    def term(self):
        pass

def PLUGIN_ENTRY():
    return PdbGenPlugin()