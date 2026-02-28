# -*- coding: utf-8 -*-
# Cheat Engine launcher: кнопка "CE" в конце тулбара 'pdbgen' (или MainToolBar),
# по клику открывает "d:\HYSYS 1.1\hysys.CT" в Cheat Engine.
# Свой отличимый значок (зелёная "C") встроен; можно указать внешний ICON_PATH.
# Windows-only. IDA 7.x–9.x, Python 3.x.

import os
import glob
import zlib
import struct
import binascii
import ctypes
from ctypes import wintypes
import subprocess

import idaapi
import ida_kernwin as kw

# === Настройки ===
ACTION_NAME     = "czar.ce.launch"
ACTION_LABEL    = "CE"
ACTION_TIP      = "Открыть Cheat Engine с таблицей"
HOTKEY          = "Ctrl+Alt+C"

PDBGEN_TOOLBAR  = "pdbgen"        # тот же тулбар, что создаёт PdbGenerator
FALLBACK_TB     = "MainToolBar"   # запасной вариант
TIMER_STEP_MS   = 300
MAX_TRIES       = 20              # ~6 сек ожидания

CT_PATH         = r"d:\HYSYS 1.1\hysys.CT"

# Если ассоциации .CT нет, попробуем найти EXE Cheat Engine автоматически.
# Можно сразу задать вручную (раскомментируйте строку ниже):
CE_EXE          = None
# CE_EXE        = r"C:\Program Files\Cheat Engine 7.5\cheatengine-x86_64.exe"

# Можно загрузить внешний PNG/ICO вместо встроенного:
ICON_PATH       = None
# ICON_PATH     = r"d:\icons\cheatengine.png"
# ==============

_state = {"tries": 0, "attached_to": None, "timer_live": False}
_icon_id = -1

def _msg(s): kw.msg("[CE-Launch] %s\n" % s)

# ---- ShellExecute "open" (устойчиво для GUI-приложений в IDA) ----
ShellExecuteW = ctypes.windll.shell32.ShellExecuteW
ShellExecuteW.argtypes = [wintypes.HWND, wintypes.LPCWSTR, wintypes.LPCWSTR,
                          wintypes.LPCWSTR, wintypes.LPCWSTR, ctypes.c_int]
ShellExecuteW.restype  = wintypes.HINSTANCE

def _shell_open(file_, params=None, cwd=None, show=1):
    h = ShellExecuteW(None, "open", file_, params or None, cwd or None, int(show))
    if h <= 32:
        raise OSError(f"ShellExecute failed, code={h}")

# ---- Иконка: загрузка внешней или встроенной ----
def _png_from_rgba(rows, w, h):
    """Собрать PNG из списка байтовых строк row: [0, r,g,b,a, ...] на каждую строку."""
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack("!IIBBBBB", w, h, 8, 6, 0, 0, 0)
    def _chunk(typ, data):
        return struct.pack("!I", len(data)) + typ + data + struct.pack("!I", binascii.crc32(typ + data) & 0xffffffff)
    raw = b"".join(rows)
    return sig + _chunk(b'IHDR', ihdr) + _chunk(b'IDAT', zlib.compress(raw, 9)) + _chunk(b'IEND', b'')

def _build_ce_icon_png():
    """16x16: зелёный фон + белая 'C' (кольцо с прорезью справа)."""
    w = h = 16
    bg = (0x2E, 0xCC, 0x71, 255)  # зелёный
    rows = []
    for y in range(h):
        row = [0]  # filter type 0
        for x in range(w):
            dx = x - 8
            dy = y - 8
            r2 = dx*dx + dy*dy
            ring = (34 <= r2 <= 64)      # толщина кольца
            gap  = (x >= 9 and abs(dy) <= 3)  # прорезь справа
            if ring and not gap:
                r, g, b, a = (255, 255, 255, 255)  # белая "C"
            else:
                r, g, b, a = bg                    # зелёный фон
            row += [r, g, b, a]
        rows.append(bytes(row))
    return _png_from_rgba(rows, w, h)

def _ensure_icon():
    """Возвращает icon_id (int). Если ICON_PATH указан — пробуем его; иначе встроенный PNG."""
    global _icon_id
    if _icon_id != -1:
        return _icon_id
    # 1) внешний файл?
    if ICON_PATH and os.path.isfile(ICON_PATH):
        try:
            _icon_id = kw.load_custom_icon(ICON_PATH)
            if _icon_id != idaapi.BADADDR:
                _msg(f"Загружен внешний значок: {ICON_PATH}")
                return _icon_id
        except Exception as e:
            _msg(f"Не удалось загрузить {ICON_PATH}: {e}")
        _icon_id = -1
    # 2) встроенный
    try:
        png = _build_ce_icon_png()
        _icon_id = kw.py_load_custom_icon_data(png, "png")
        _msg(f"Загружен встроенный значок (id={_icon_id})")
    except Exception as e:
        _msg(f"Иконка по умолчанию не загрузилась: {e}")
        _icon_id = -1  # IDA тогда покажет стандартную пустую
    return _icon_id

# ---- Поиск Cheat Engine (если нужно) ----
def _guess_cheatengine_exe():
    if CE_EXE and os.path.isfile(CE_EXE):
        return CE_EXE
    candidates = []
    for env in ("ProgramFiles", "ProgramFiles(x86)"):
        base = os.environ.get(env)
        if not base:
            continue
        pattern = os.path.join(base, "Cheat Engine*", "cheatengine*.exe")
        candidates.extend(glob.glob(pattern))
    candidates = [c for c in candidates if os.path.isfile(c)]
    # предпочитаем 64‑битную сборку
    candidates.sort(key=lambda p: ("x86_64" not in os.path.basename(p).lower(), len(p)))
    return candidates[0] if candidates else None

# ---- Открытие CT ----
def _open_ct():
    if not os.path.isfile(CT_PATH):
        kw.warning("Не найден CT-файл:\n%s" % CT_PATH)
        return
    # 1) Идеально — по ассоциации
    try:
        _shell_open(CT_PATH, None, None, 1)
        _msg("Открываю таблицу по ассоциации: %s" % CT_PATH)
        return
    except Exception as e:
        _msg(f"ShellExecute(CT) не сработал: {e}")
    # 2) Явный запуск CE с параметром
    ce = _guess_cheatengine_exe()
    if not ce:
        kw.warning("Не найден cheatengine.exe. Задайте CE_EXE вручную в плагине.")
        return
    try:
        _shell_open(ce, CT_PATH, None, 1)
        _msg(f"Запускаю Cheat Engine: {ce} {CT_PATH}")
    except Exception as e:
        kw.warning(f"Не удалось запустить Cheat Engine:\n{e}\nCE_EXE={ce}")

# ---- IDA UI: одна кнопка в конце нужного тулбара ----
def _attach_last(toolbar_name):
    # отцепить от всех и прицепить в конец указанного тулбара
    for tb in (PDBGEN_TOOLBAR, FALLBACK_TB):
        try: kw.detach_action_from_toolbar(tb, ACTION_NAME)
        except Exception: pass
    ok = kw.attach_action_to_toolbar(toolbar_name, ACTION_NAME)
    _msg("attach_action_to_toolbar('%s') -> %s" % (toolbar_name, ok))
    if ok:
        # приём "detach -> attach" ещё раз — чтобы оказаться строго в конце
        try: kw.detach_action_from_toolbar(toolbar_name, ACTION_NAME)
        except Exception: pass
        kw.attach_action_to_toolbar(toolbar_name, ACTION_NAME)
        _msg("re-attached to '%s' (tail)" % toolbar_name)
    return ok

class _Handler(kw.action_handler_t):
    def activate(self, ctx):
        if os.name != "nt":
            kw.warning("Плагин рассчитан на Windows.")
            return 1
        _open_ct()
        return 1
    def update(self, ctx):
        return kw.AST_ENABLE_ALWAYS if os.name == "nt" else kw.AST_DISABLE

def _register_action():
    try: kw.unregister_action(ACTION_NAME)
    except Exception: pass
    icon_id = _ensure_icon()
    desc = kw.action_desc_t(ACTION_NAME, ACTION_LABEL, _Handler(), HOTKEY, ACTION_TIP, icon_id)
    ok = kw.register_action(desc)
    _msg("register_action -> %s" % ok)
    return ok

def _probe_and_attach():
    if _state["attached_to"] == PDBGEN_TOOLBAR:
        _state["timer_live"] = False
        return -1
    ok = _attach_last(PDBGEN_TOOLBAR)
    if ok:
        _state["attached_to"] = PDBGEN_TOOLBAR
        _state["timer_live"] = False
        return -1
    _state["tries"] += 1
    if _state["tries"] >= MAX_TRIES:
        _attach_last(FALLBACK_TB)
        _state["timer_live"] = False
        return -1
    return TIMER_STEP_MS

class _Hooks(kw.UI_Hooks):
    def ready_to_run(self):
        _register_action()
        if not _attach_last(PDBGEN_TOOLBAR):
            if not _state["timer_live"]:
                kw.register_timer(TIMER_STEP_MS, _probe_and_attach)
                _state["timer_live"] = True

_hooks = None
def _install():
    global _hooks
    _register_action()
    if not _attach_last(PDBGEN_TOOLBAR):
        kw.register_timer(TIMER_STEP_MS, _probe_and_attach)
        _state["timer_live"] = True
    _hooks = _Hooks()
    try:
        _hooks.hook()
        _msg("UI_Hooks.hook -> ok")
    except Exception as e:
        _msg(f"UI_Hooks.hook -> fail: {e}")
    _msg("CE‑Launcher готов: кнопка 'CE' и хоткей %s." % HOTKEY)

def _uninstall():
    global _hooks, _icon_id
    try:
        for tb in (PDBGEN_TOOLBAR, FALLBACK_TB):
            kw.detach_action_from_toolbar(tb, ACTION_NAME)
    except Exception:
        pass
    try: kw.unregister_action(ACTION_NAME)
    except Exception: pass
    # освободим кастомную иконку
    try:
        if _icon_id != -1:
            kw.free_custom_icon(_icon_id)
    except Exception:
        pass
    _icon_id = -1
    if _hooks:
        try: _hooks.unhook()
        except Exception: pass
    _hooks = None
    _msg("uninstall complete")

class ce_launch_after_pdbgen_plugin_t(idaapi.plugin_t):
    flags = idaapi.PLUGIN_PROC
    comment = "Cheat Engine launcher (custom icon)"
    help = "Open CE with the given .CT"
    wanted_name = "Cheat Engine Launcher"
    wanted_hotkey = HOTKEY
    def init(self): _install(); return idaapi.PLUGIN_KEEP
    def run(self, arg): kw.process_ui_action(ACTION_NAME)
    def term(self): _uninstall()

def PLUGIN_ENTRY():
    return ce_launch_after_pdbgen_plugin_t()
