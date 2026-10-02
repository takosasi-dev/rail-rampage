"""Godot を tools/godot/ に用意する（エディタ本体と、Windows・Web の書き出しテンプレート）。

公式の export_templates.tpz は全機種分で 1.28GB あるため、HTTP Range で必要なファイルだけ取り出す。
Web はスレッド無しのものだけ（NFR-3。設定を間違えてスレッド有りで書き出そうとすると、テンプレートが無くて止まる）。
すでにあるファイルは取り直さない。
実行: python tools/setup_godot.py
"""
import io
import urllib.request
import zipfile
from pathlib import Path

VERSION = "4.7.2-stable"
BASE = f"https://github.com/godotengine/godot/releases/download/{VERSION}/Godot_v{VERSION}"
GODOT_DIR = Path(__file__).resolve().parent / "godot"
# TODO(spec): 配布用（build/release/ と Web）はリリース版で書き出す。仕様書は版を決めていないが、
# FR-54 のデバッグ表示（FPS・物体数）を遊ぶ人に見せないため。確かめる用の exe はデバッグ版のまま
TEMPLATES = [
    "templates/version.txt",
    "templates/windows_debug_x86_64.exe",
    "templates/windows_release_x86_64.exe",
    "templates/web_nothreads_release.zip",
]
CHUNK = 8 * 1024 * 1024


class HttpRangeFile(io.RawIOBase):
    """zipfile から読める、Range リクエストで必要な部分だけ取ってくるファイル。"""

    def __init__(self, url: str) -> None:
        # リダイレクト先（署名付きURL）を先に確定させる
        with urllib.request.urlopen(urllib.request.Request(url, headers={"Range": "bytes=0-0"})) as r:
            self.url = r.url
            self.size = int(r.headers["Content-Range"].split("/")[1])
        self.pos = 0

    def readable(self) -> bool:
        return True

    def seekable(self) -> bool:
        return True

    def tell(self) -> int:
        return self.pos

    def seek(self, offset: int, whence: int = 0) -> int:
        self.pos = {0: offset, 1: self.pos + offset, 2: self.size + offset}[whence]
        return self.pos

    def readinto(self, b) -> int:
        n = min(len(b), self.size - self.pos)
        if n <= 0:
            return 0
        req = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{self.pos + n - 1}"})
        with urllib.request.urlopen(req) as r:
            data = r.read()
        b[: len(data)] = data
        self.pos += len(data)
        return len(data)


def open_remote_zip(url: str) -> zipfile.ZipFile:
    return zipfile.ZipFile(io.BufferedReader(HttpRangeFile(url), buffer_size=CHUNK))


def main() -> None:
    GODOT_DIR.mkdir(parents=True, exist_ok=True)
    (GODOT_DIR / "_sc_").touch()  # エディタの設定・テンプレートを AppData でなくこのフォルダに置く
    (GODOT_DIR / ".gdignore").touch()  # Godot にこのフォルダを取り込ませない
    if not (GODOT_DIR / f"Godot_v{VERSION}_win64.exe").exists():
        with open_remote_zip(f"{BASE}_win64.exe.zip") as z:
            z.extractall(GODOT_DIR)
    with open_remote_zip(f"{BASE}_export_templates.tpz") as z:
        dest = GODOT_DIR / "editor_data" / "export_templates" / z.read(TEMPLATES[0]).decode().strip()
        dest.mkdir(parents=True, exist_ok=True)
        for name in TEMPLATES:
            if not (dest / Path(name).name).exists():
                (dest / Path(name).name).write_bytes(z.read(name))
    print("用意できました:", GODOT_DIR)


if __name__ == "__main__":
    main()
