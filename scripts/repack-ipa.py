import os
import sys
import zipfile
import tempfile
import shutil
import time

def add_file(z, path, arc, stored=False):
    info = zipfile.ZipInfo(arc, time.localtime(os.path.getmtime(path))[:6])
    info.create_system = 3
    info.extra = b""
    info.comment = b""
    info.flag_bits = 0
    info.compress_type = zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED
    info.external_attr = 0o100644 << 16
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
                break
        if not app:
            raise SystemExit("no .app")
        with open(os.path.join(app, "PkgInfo"), "wb") as f:
            f.write(b"APPL????")
        for root, dirs, files in os.walk(app):
            if root.endswith(".appex"):
                with open(os.path.join(root, "PkgInfo"), "wb") as f:
                    f.write(b"XPC!!!!!")
        tmp = dst + ".partial"
        if os.path.exists(tmp):
            os.remove(tmp)
        with zipfile.ZipFile(tmp, "w", allowZip64=False) as z:
            z.comment = b""
            for root, dirs, files in os.walk(payload):
                for fn in files:
                    path = os.path.join(root, fn)
                    arc = os.path.relpath(path, work).replace("\\", "/")
                    add_file(z, path, arc, stored=(fn == "PkgInfo"))
        if os.path.exists(dst):
            os.remove(dst)
        os.replace(tmp, dst)
        print("wrote", dst, os.path.getsize(dst))
        with zipfile.ZipFile(dst) as z:
            for i in z.infolist():
                if "PkgInfo" in i.filename:
                    print("PkgInfo", i.file_size, i.compress_size, i.compress_type, len(i.extra), hex(i.flag_bits))
    finally:
        shutil.rmtree(work, ignore_errors=True)

if __name__ == "__main__":
    main()
