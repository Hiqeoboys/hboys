import os
from PIL import Image

SRC = r"C:\Users\Kallopsia\Documents\App\nama_app\app\assets\raw_guides"
DST = r"C:\Users\Kallopsia\Documents\App\nama_app\app\assets\guides"
MAX_WIDTH = 1440
QUALITY = 97

os.makedirs(DST, exist_ok=True)

for name in os.listdir(SRC):
    if not name.lower().endswith((".jpg", ".jpeg", ".png")):
        continue

    img = Image.open(os.path.join(SRC, name)).convert("RGB")
    old_size = img.size

    # Perkecil hanya jika lebih lebar dari MAX_WIDTH (rasio tetap terjaga)
    if img.width > MAX_WIDTH:
        new_height = round(img.height * MAX_WIDTH / img.width)
        img = img.resize((MAX_WIDTH, new_height), Image.LANCZOS)

    out_name = os.path.splitext(name)[0] + ".webp"
    img.save(os.path.join(DST, out_name), "WEBP", quality=QUALITY, method=6)
    print(f"OK: {name} {old_size} -> {out_name} {img.size}")