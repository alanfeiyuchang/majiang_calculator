#!/usr/bin/env python3
"""
框选标注 editor 的本地服务。

跑起来：
    python3 data/editor/serve.py
然后浏览器打开 http://localhost:8777

静态文件根目录是 data/，编辑结果直接写回 data/boxes.json。
"""

import json
import os
import sys
import webbrowser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

PORT = 8777
DATA_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # …/data
BOXES = os.path.join(DATA_DIR, "boxes.json")


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DATA_DIR, **kwargs)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self.path = "/editor/index.html"
        return super().do_GET()

    def do_POST(self):
        if self.path != "/save":
            self.send_error(404)
            return
        try:
            n = int(self.headers.get("Content-Length", 0))
            req = json.loads(self.rfile.read(n).decode("utf-8"))
            name, b = req["name"], req["box"]
            # 校验后再落盘，避免把坏数据写进 ground truth
            for k in ("x", "y", "w", "h"):
                v = float(b[k])
                if not (0.0 <= v <= 1.0):
                    raise ValueError(f"{name}.{k} out of range: {v}")
            if b["w"] <= 0 or b["h"] <= 0:
                raise ValueError(f"{name}: empty box")

            # 只合并这一张：同时开着多个标签页时，各自只写自己改的那张，不会互相覆盖
            with open(BOXES) as f:
                data = json.load(f)
            data[name] = {k: round(float(b[k]), 4) for k in ("x", "y", "w", "h")}

            lines = ["{"]
            for i, key in enumerate(sorted(data)):
                v = data[key]
                comma = "," if i < len(data) - 1 else ""
                lines.append(
                    f'  "{key}": {{"x": {v["x"]:.4f}, "y": {v["y"]:.4f}, '
                    f'"w": {v["w"]:.4f}, "h": {v["h"]:.4f}}}{comma}'
                )
            lines.append("}")
            tmp = BOXES + ".tmp"
            with open(tmp, "w") as f:
                f.write("\n".join(lines) + "\n")
            os.replace(tmp, BOXES)                      # 原子替换，中途出错不会毁掉原文件
        except Exception as e:                          # noqa: BLE001
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    def log_message(self, fmt, *args):
        if "POST" in (args[0] if args else ""):
            sys.stderr.write("saved boxes.json\n")


if __name__ == "__main__":
    if not os.path.exists(BOXES):
        with open(BOXES, "w") as f:
            f.write("{}\n")
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    url = f"http://localhost:{PORT}"
    print(f"框选 editor: {url}\n静态根目录: {DATA_DIR}\n结果写入: {BOXES}\nCtrl-C 停止")
    try:
        webbrowser.open(url)
    except Exception:                                   # noqa: BLE001
        pass
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")
