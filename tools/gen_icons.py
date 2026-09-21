#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_icons.py — 生成丛丛影视 iOS App Icon 完整集 + Assets.xcassets 标准结构。
输出到 <repo>/CongcongTV/Resources/Assets.xcassets/
AppIcon.appiconset/Contents.json 用通用 single-size entries（1024 + 60pt@2x 等，
Xcode 13+ 接受 idiom 统一的 AppIcon 集；这里两种都生成，兼容旧版）。

无设计资产：用 渐变 + 圆角 + “丛”字 绘制 AppIcon，符合 1024 无透明要求。
"""
import io
import json
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.abspath(__file__))
XCA = os.path.normpath(os.path.join(ROOT, "..", "CongcongTV", "Resources", "Assets.xcassets"))
ICONSET = os.path.join(XCA, "AppIcon.appiconset")
FONT = "C:/Windows/Fonts/msyh.ttc"

# ---- 画 1024 semantic icon ----
def make_icon(size=1024, out=None):
    SS = 4  # supersample
    S = size * SS
    img = Image.new("RGB", (S, S), (8, 17, 32))
    d = ImageDraw.Draw(img)

    # 背景渐变（深檀 → 绯红）
    import math
    top = (58, 26, 90)
    bottom = (214, 44, 84)
    for y in range(S):
        t = y / max(S - 1, 1)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        d.line([(0, y), (S, y)], fill=(r, g, b))

    # 圆角遮罩
    mask = Image.new("L", (S, S), 0)
    dm = ImageDraw.Draw(mask)
    rad = int(S * 0.18)
    dm.rounded_rectangle([0, 0, S - 1, S - 1], radius=rad, fill=255)
    alpha = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    alpha.paste(img.convert("RGBA"), (0, 0), mask)

    # 播放三角（白 → 浅金）
    cx, cy = S * 0.5, S * 0.50
    tri_h = S * 0.34
    tri_w = S * 0.34
    pts = [
        (cx - tri_w * 0.5, cy - tri_h * 0.62),
        (cx - tri_w * 0.5, cy + tri_h * 0.62),
        (cx + tri_w * 0.55, cy),
    ]
    d2 = ImageDraw.Draw(alpha)
    d2.polygon(pts, fill=(255, 244, 224, 255))

    # 下光环
    d2.ellipse([cx - S * 0.34, cy + S * 0.30, cx + S * 0.34, cy + S * 0.50],
               fill=(255, 255, 255, 90))

    # “丛” 字叠加（右下小号，作品牌点缀）
    fsize = int(S * 0.40)
    font = ImageFont.truetype(FONT, fsize)
    glyph = "丛"
    bbox = d2.textbbox((0, 0), glyph, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = S * 0.5 - tw / 2 - bbox[0]
    ty = S * 0.5 - th / 2 - bbox[1] + S * 0.002
    d2.text((tx, ty), glyph, font=font, fill=(255, 250, 240, 235))

    # 缩小到目标尺寸 + 圆角回采样（抗锯齿）
    icon = alpha.resize((size, size), Image.LANCZOS)
    mask_s = mask.resize((size, size), Image.LANCZOS)
    icon.putalpha(mask_s)

    if out:
        icon.save(out)
    else:
        b = io.BytesIO()
        icon.save(b, "PNG")
        return b.getvalue()


CONTENTS = {
    "images": [
        {"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        {"filename": "AppIcon-60@2x.png", "idiom": "universal", "platform": "ios", "size": "60x60", "scale": "2x"},
        {"filename": "AppIcon-60@3x.png", "idiom": "universal", "platform": "ios", "size": "60x60", "scale": "3x"},
        {"filename": "AppIcon-76@2x.png", "idiom": "universal", "platform": "ios", "size": "76x76", "scale": "2x"},
        {"filename": "AppIcon-83.5@2x.png", "idiom": "universal", "platform": "ios", "size": "83.5x83.5", "scale": "2x"},
        {"filename": "AppIcon-29@2x.png", "idiom": "universal", "platform": "ios", "size": "29x29", "scale": "2x"},
        {"filename": "AppIcon-29@3x.png", "idiom": "universal", "platform": "ios", "size": "29x29", "scale": "3x"},
        {"filename": "AppIcon-40@2x.png", "idiom": "universal", "platform": "ios", "size": "40x40", "scale": "2x"},
        {"filename": "AppIcon-40@3x.png", "idiom": "universal", "platform": "ios", "size": "40x40", "scale": "3x"},
    ],
    "info": {"author": "xcode", "version": 1},
}


def sizes_of(filename):
    byts = {
        "1024": 1024,
        "60": 60, "76": 76, "83.5": 84, "29": 29, "40": 40,
    }
    base = filename.replace("AppIcon-", "").replace(".png", "")
    px = base.split("@")[0]
    return byts[px]


def main():
    os.makedirs(ICONSET, exist_ok=True)
    # 修正 XCA 目录 Contents.json（之前是目录/畸形）
    for f in os.listdir(XCA):
        p = os.path.join(XCA, f)
        if os.path.isdir(p):
            if f == "Contents.json" and not os.listdir(p):
                os.rmdir(p)  # 删除错误的空目录
                continue
            continue
        if os.path.getsize(p) == 0:
            os.remove(p)

    with open(os.path.join(XCA, "Contents.json"), "w", encoding="utf-8") as fh:
        json.dump({"info": {"author": "xcode", "version": 1}}, fh, ensure_ascii=False)

    icon1024 = make_icon(1024)
    with open(os.path.join(ICONSET, "AppIcon-1024.png"), "wb") as fh:
        fh.write(icon1024)

    for im in CONTENTS["images"]:
        if im["filename"] == "AppIcon-1024.png":
            continue
        px = sizes_of(im["filename"])
        data = make_icon(px)
        with open(os.path.join(ICONSET, im["filename"]), "wb") as fh:
            fh.write(data)
        print(im["filename"], "->", px, "px")

    with open(os.path.join(ICONSET, "Contents.json"), "w", encoding="utf-8") as fh:
        json.dump(CONTENTS, fh, ensure_ascii=False, indent=2)

    print("Assets written to", XCA)
    for root, _, files in os.walk(XCA):
        for fn in files:
            p = os.path.join(root, fn)
            print("  %s (%d B)" % (os.path.relpath(p, ROOT), os.path.getsize(p)))


if __name__ == "__main__":
    main()
