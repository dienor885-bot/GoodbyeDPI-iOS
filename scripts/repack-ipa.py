import os
import sys
import zipfile
import tempfile
import shutil

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
        if os.path.exists(dst):
            os.remove(dst)
        with zipfile.ZipFile(dst, "w", allowZip64=False) as z:
            for root, dirs, files in os.walk(payload):
                for fn in files:
                    path = os.path.join(root, fn)
                    arc = os.path.relpath(path, work).replace("\\", "/")
                    compress = zipfile.ZIP_STORED if fn == "PkgInfo" else zipfile.ZIP_DEFLATED
                    z.write(path, arc, compress)
        print("wrote", dst, os.path.getsize(dst))
    finally:
        shutil.rmtree(work, ignore_errors=True)

if __name__ == "__main__":
    main()
