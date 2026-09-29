import os
import sys
import zipfile
import tempfile
import shutil
import time

def add_file(z, path, arc):
    st = os.stat(path)
    info = zipfile.ZipInfo(arc.replace("\\", "/"), time.localtime(st.st_mtime)[:6])
    info.create_system = 0
    info.create_version = 20
    info.extract_version = 20
    info.reserved = 0
    info.flag_bits = 0
    info.extra = b""
    info.comment = b""
    info.compress_type = zipfile.ZIP_STORED
    info.external_attr = 0x20
    info.volume = 0
    info.internal_attr = 0
    with open(path, "rb") as f:
        data = f.read()
    z.writestr(info, data)

def main():
    src = sys.argv[1]
    dst = sys.argv[2]
    drop_pkginfo = "--no-pkginfo" in sys.argv
    work = tempfile.mkdtemp(prefix="gdpi-")
    try:
        with zipfile.ZipFile(src, "r") as z:
            z.extractall(work)
        payload = os.path.join(work, "Payload")
        for root, dirs, files in os.walk(payload):
            for fn in list(files):
                if fn == "PkgInfo":
                    os.remove(os.path.join(root, fn))
        if not drop_pkginfo:
            for root, dirs, files in os.walk(payload):
                if root.endswith(".app") and not root.endswith(".appex"):
                    with open(os.path.join(root, "PkgInfo"), "wb") as f:
                        f.write(b"APPL????")
        tmp = dst + ".partial"
        if os.path.exists(tmp):
            os.remove(tmp)
        with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_STORED, allowZip64=False) as z:
            z.comment = b""
            for root, dirs, files in os.walk(payload):
                for fn in files:
                    path = os.path.join(root, fn)
                    arc = os.path.relpath(path, work).replace("\\", "/")
                    add_file(z, path, arc)
        if os.path.exists(dst):
            try:
                os.remove(dst)
            except OSError:
                dst = dst.replace(".ipa", "-new.ipa")
        os.replace(tmp, dst)
        print("wrote", dst, os.path.getsize(dst))
        with zipfile.ZipFile(dst) as z:
            for i in z.infolist():
                print(i.compress_type, i.file_size, i.compress_size, len(i.extra), i.create_system, i.filename)
    finally:
        shutil.rmtree(work, ignore_errors=True)

if __name__ == "__main__":
    main()
