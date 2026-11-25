# self-test of cmp_sweeps.py: a copy of a sweep folder with ONE pixel of ONE render changed must read "1 differ";
# the folder against itself must read 0 differ.   py -3.12 cmp_selftest.py <sweep dir>
import os, shutil, subprocess, sys, tempfile
from PIL import Image

src = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
tmp = tempfile.mkdtemp(prefix="cmpself_")
dst = os.path.join(tmp, "b")
shutil.copytree(src, dst)
pngs = sorted(f for f in os.listdir(dst) if f.endswith(".png"))
victim = pngs[len(pngs) // 2]
im = Image.open(os.path.join(dst, victim)).convert("RGBA")
r, g, b, a = im.getpixel((5, 5))
im.putpixel((5, 5), ((r + 1) % 256, g, b, a))
im.save(os.path.join(dst, victim))
cmp = os.path.join(here, "cmp_sweeps.py")
same = subprocess.run([sys.executable, cmp, src, src], capture_output=True, text=True).stdout
one = subprocess.run([sys.executable, cmp, src, dst], capture_output=True, text=True).stdout
print("self vs self:", " | ".join(l for l in same.splitlines() if "identical" in l))
print("one pixel changed in %s:" % victim, " | ".join(l for l in one.splitlines() if "identical" in l))
ok_same = all(", 0 differ" in l for l in same.splitlines() if "identical" in l)
ok_one = sum(int(l.split(",")[1].split()[0]) for l in one.splitlines() if "identical" in l) == 1
shutil.rmtree(tmp, ignore_errors=True)
print("SELFTEST", "PASS" if (ok_same and ok_one) else "FAIL")
sys.exit(0 if (ok_same and ok_one) else 1)
