#!/usr/bin/env python3
"""Convert status line ANSI output (stdin) into a terminal-styled HTML page (stdout)."""
import html
import re
import sys

BG = "#1e1e2e"
FG = "#cdd6f4"
BASIC = {
    30: "#45475a", 31: "#f38ba8", 32: "#a6e3a1", 33: "#f9e2af",
    34: "#89b4fa", 35: "#cba6f7", 36: "#94e2d5", 37: "#bac2de",
    90: "#6c7086", 91: "#ff5f7e", 92: "#a6e3a1", 93: "#f9e2af",
    94: "#89b4fa", 95: "#f5c2e7", 96: "#94e2d5", 97: "#ffffff",
}

def convert(text):
    out, color = [], None
    for chunk in re.split(r"(\x1b\[[0-9;]*m)", text):
        m = re.fullmatch(r"\x1b\[([0-9;]*)m", chunk)
        if not m:
            if chunk:
                esc = html.escape(chunk)
                out.append(f'<span style="color:{color}">{esc}</span>' if color else esc)
            continue
        codes = [int(c) for c in m.group(1).split(";") if c] or [0]
        i = 0
        while i < len(codes):
            c = codes[i]
            if c == 0 or c == 39:
                color = None
            elif c == 38 and codes[i + 1:i + 2] == [2]:
                r, g, b = codes[i + 2:i + 5]
                color = f"rgb({r},{g},{b})"
                i += 4
            elif c in BASIC:
                color = BASIC[c]
            i += 1
    return "".join(out)

body = convert(sys.stdin.read())
print(f"""<!doctype html><html><head><meta charset="utf-8"><style>
html,body{{margin:0;background:{BG};}}
pre{{margin:0;padding:18px 22px;color:{FG};font:15px/1.55 "Cascadia Mono","Consolas","Menlo",monospace;
  font-variant-ligatures:none;display:inline-block;}}
</style></head><body><pre>{body}</pre></body></html>""")
