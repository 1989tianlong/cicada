"""Words the "can't reach the AI service" hint (ProxyHint.swift). Read-only on purpose: the app never
sets or picks a proxy of its own (urllib already goes through `https_proxy` when it is set); it only
tells the user which of three situations they are in, so the hint says what to do."""
from __future__ import annotations

import os
import socket
import subprocess

# Ports common proxy apps listen on (Clash 7890, Clash Verge 7897, SOCKS 1080).
PORTS = (7890, 7897, 1080)


def system_proxy_on(env=None, gsettings=None) -> bool:
    """A proxy in the environment (what urllib uses), else GNOME's 设置 › 网络 › 网络代理 set to
    manual or automatic."""
    env = os.environ if env is None else env
    if any((env.get(k) or "").strip() for k in ("https_proxy", "HTTPS_PROXY", "all_proxy", "ALL_PROXY")):
        return True
    mode = (gsettings or _gnome_mode)()
    return mode.strip().strip("'\"") in ("manual", "auto")


def _gnome_mode() -> str:
    try:
        r = subprocess.run(["gsettings", "get", "org.gnome.system.proxy", "mode"], capture_output=True, text=True, timeout=2)
        return r.stdout if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""  # no gsettings (not GNOME, or the Mac running the tests)


def listening(port: int, timeout: float = 0.3) -> bool:
    """Something accepts a TCP connection on 127.0.0.1:`port` within `timeout`. Nothing is sent."""
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=timeout):
            return True
    except OSError:
        return False


def hint(env=None, gsettings=None, probe=listening) -> tuple:
    """("system",), ("app", port) or ("none",): see AICheck.proxy_line."""
    if system_proxy_on(env, gsettings):
        return ("system",)
    for port in PORTS:
        if probe(port):
            return ("app", port)
    return ("none",)
