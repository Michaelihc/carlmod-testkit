"""解压 Carl Mod 服务端 ZIP（只读取 ZIP，不修改它）。

用法: python scripts/extract-server.py --zip <服务端.zip> <目标文件夹>

- 自动找到包含 "Carl Mod.exe" 的文件夹，目标文件夹里直接得到 "Carl Mod.exe" 和 "Carl Mod_Data"。
- 未标记 UTF-8 的文件名按 GBK 解码（国内打包工具常见）。
- 跳过 mono.msi 和 *.bak 备份文件。
"""
import argparse
import sys
import zipfile
from pathlib import PurePosixPath, Path

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, 'reconfigure'):
        stream.reconfigure(encoding='utf-8', errors='replace')

parser = argparse.ArgumentParser(description='Extract the Carl Mod server ZIP.')
parser.add_argument('--zip', type=Path, required=True, help='Carl Mod server ZIP')
parser.add_argument('destination', type=Path, help='destination folder')
args = parser.parse_args()

if not args.zip.is_file():
    sys.exit(f'找不到服务端 ZIP: {args.zip}')


def entry_name(info: zipfile.ZipInfo) -> str:
    name = info.filename
    if not info.flag_bits & 0x800:
        try:
            name = name.encode('cp437').decode('gbk')
        except UnicodeError:
            pass
    return name.replace(chr(92), '/')


with zipfile.ZipFile(args.zip) as archive:
    entries = [(entry_name(i), i) for i in archive.infolist()]
    exes = sorted((n for n, _ in entries if PurePosixPath(n).name == 'Carl Mod.exe'), key=len)
    if not exes:
        sys.exit('ZIP 里没有 "Carl Mod.exe"，这不是 Carl Mod 服务端压缩包。')
    root = exes[0][: -len('Carl Mod.exe')]  # '' or 'folder/'

    dst = args.destination
    dst.mkdir(parents=True, exist_ok=True)
    count = 0
    for name, info in entries:
        if not name.startswith(root) or name.endswith('mono.msi') or name.endswith('.bak'):
            continue
        rel = name[len(root):]
        if not rel:
            continue
        if '..' in PurePosixPath(rel).parts or rel.startswith('/'):
            continue
        out = dst / rel
        if rel.endswith('/'):
            out.mkdir(parents=True, exist_ok=True)
            continue
        out.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(info) as source, open(out, 'wb') as target:
            while True:
                chunk = source.read(1 << 20)
                if not chunk:
                    break
                target.write(chunk)
        count += 1

print(f'已解压 {count} 个文件到 {dst}')
