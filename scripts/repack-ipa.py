import os
import sys
import zipfile
import tempfile
import shutil
import time

def add_dir(z, arc):
    if not arc.endswith("/"):
        arc += "/"
    info = zipfile.ZipInfo(arc)
    info.create_system = 3
    info.create_version = 20
    info.extract_version = 20
    info.compress_type = zipfile.ZIP_STORED
    info.external_attr = (0o40755 << 16) | 0x10
    z.writestr(info, b"")

def add_file(z, path, arc, mode=0o100644):
    st = os.stat(path)
    info = zipfile.ZipInfo(arc.replace("\\", "/"), time.localtime(st.st_mtime)[:6])
    info.create_system = 3
    info.create_version = 20
    info.extract_version = 20
    info.flag_bits = 0
    info.extra = b""
    info.comment = b""
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = mode << 16
    with open(path, "rb") as f:
        data = f.read()
    z.writestr(info, data)

def main():
    src = sys.argv[1]
    dst = sys.argv[2]
    work = tempfile.mkdtemp(prefix="gdpi-")
    try:
        with zipfile.ZipFile(src, "r") as z:
            z.extractall(work)
        payload = os.path.join(work, "Payload")
        app = None
        for name in os.listdir(payload):
            if name.endswith(".app"):
                app = os.path.join(payload, name)
        if not app:
            raise SystemExit("no .app")
        with open(os.path.join(app, "PkgInfo"), "wb") as f:
            f.write(b"APPL????")
        for root, dirs, files in os.walk(app):
            if root.endswith(".appex"):
                with open(os.path.join(root, "PkgInfo"), "wb") as f:
                    f.write(b"APPL????")
        dirs_needed = set(["Payload/"])
        files_list = []
        for root, dirs, files in os.walk(payload):
            rel = os.path.relpath(root, work).replace("\\", "/")
            if not rel.endswith("/"):
                rel += "/"
            dirs_needed.add(rel)
            for fn in files:
                path = os.path.join(root, fn)
                arc = os.path.relpath(path, work).replace("\\", "/")
                files_list.append((path, arc))
        tmp = dst + ".partial"
        if os.path.exists(tmp):
            os.remove(tmp)
        with zipfile.ZipFile(tmp, "w", allowZip64=False) as z:
            z.comment = b""
            for d in sorted(dirs_needed):
                add_dir(z, d)
            for path, arc in files_list:
                mode = 0o100755 if os.path.splitext(arc)[1] == "" else 0o100644
                add_file(z, path, arc, mode)
        os.replace(tmp, dst)
        print("wrote", dst, os.path.getsize(dst))
    finally:
        shutil.rmtree(work, ignore_errors=True)

if __name__ == "__main__":
    main()
