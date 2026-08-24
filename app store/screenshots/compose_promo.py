#!/usr/bin/env python3
"""
Regenerate the App Store 6.5" promo screenshots from raw simulator captures.

Usage: capture fresh raw screenshots into raw/<name>.png (see repo memory
`ai-tile-recognition`/README for the SIMCTL_CHILD_DEMO_* env hooks that
reproduce each demo state), then from this directory run:

    python3 compose_promo.py

Composites each raw/<name>.png onto a gradient background with caption +
headline + subtitle text, rounded corners, and a soft drop shadow, writing
6.5-inch/<name>.png. Style (colors, type sizes, phone placement) was reverse
-measured from the original hand-made screenshots, so re-running this after
editing SCREENS below should stay visually consistent.
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
RAW_DIR = os.path.join(HERE, "raw")
OUT_DIR = os.path.join(HERE, "6.5-inch")

CANVAS_W, CANVAS_H = 1242, 2688
TOP_COLOR = (40, 129, 90)
BOTTOM_COLOR = (12, 56, 35)
GOLD = (246, 212, 136)
WHITE = (255, 255, 255)
MINT = (207, 233, 220)

FONT_MED = "/System/Library/Fonts/STHeiti Medium.ttc"
FONT_LIGHT = "/System/Library/Fonts/STHeiti Light.ttc"

PHONE_W = 904
PHONE_TOP = 690
PHONE_LEFT = (CANVAS_W - PHONE_W) // 2
CORNER_RADIUS = 60


def make_gradient():
    im = Image.new("RGB", (CANVAS_W, CANVAS_H))
    px = im.load()
    for y in range(CANVAS_H):
        t = y / (CANVAS_H - 1)
        r = round(TOP_COLOR[0] + (BOTTOM_COLOR[0] - TOP_COLOR[0]) * t)
        g = round(TOP_COLOR[1] + (BOTTOM_COLOR[1] - TOP_COLOR[1]) * t)
        b = round(TOP_COLOR[2] + (BOTTOM_COLOR[2] - TOP_COLOR[2]) * t)
        for x in range(CANVAS_W):
            px[x, y] = (r, g, b)
    return im


def draw_tracked_text(draw, y, text, font, fill, tracking, center_x):
    widths = []
    for ch in text:
        bbox = font.getbbox(ch)
        widths.append(bbox[2] - bbox[0] if ch != " " else font.getbbox("一")[2] * 0.4)
    total = sum(widths) + tracking * (len(text) - 1)
    x = center_x - total / 2
    for ch, w in zip(text, widths):
        draw.text((x, y), ch, font=font, fill=fill)
        x += w + tracking


def fit_headline_font(text, max_width, start_size=96, min_size=56):
    size = start_size
    while size > min_size:
        f = ImageFont.truetype(FONT_MED, size)
        bbox = f.getbbox(text)
        if (bbox[2] - bbox[0]) <= max_width:
            return f
        size -= 2
    return ImageFont.truetype(FONT_MED, min_size)


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def compose(raw_path, out_path, caption, headline, subtitle, crop_top=0, crop_bottom=0):
    bg = make_gradient()
    draw = ImageDraw.Draw(bg)
    cx = CANVAS_W // 2

    draw_tracked_text(draw, 150, caption, ImageFont.truetype(FONT_MED, 44), GOLD, tracking=4, center_x=cx)

    headline_font = fit_headline_font(headline, CANVAS_W - 120)
    hbbox = headline_font.getbbox(headline)
    draw.text((cx - (hbbox[2] - hbbox[0]) / 2 - hbbox[0], 250), headline, font=headline_font, fill=WHITE)

    sub_font = ImageFont.truetype(FONT_LIGHT, 40)
    sbbox = sub_font.getbbox(subtitle)
    draw.text((cx - (sbbox[2] - sbbox[0]) / 2 - sbbox[0], 428), subtitle, font=sub_font, fill=MINT)

    shot = Image.open(raw_path).convert("RGB")
    w, h = shot.size
    if crop_top or crop_bottom:
        shot = shot.crop((0, crop_top, w, h - crop_bottom))
        w, h = shot.size
    new_h = round(h * (PHONE_W / w))
    shot = shot.resize((PHONE_W, new_h), Image.LANCZOS)

    avail_h = CANVAS_H - PHONE_TOP - 24
    if new_h > avail_h:
        shot = shot.crop((0, 0, PHONE_W, avail_h))
        new_h = avail_h

    shadow = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [PHONE_LEFT - 4, PHONE_TOP + 10, PHONE_LEFT + PHONE_W + 4, PHONE_TOP + new_h + 18],
        radius=CORNER_RADIUS + 4, fill=(0, 0, 0, 90),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    bg = Image.alpha_composite(bg.convert("RGBA"), shadow).convert("RGB")

    bg.paste(shot, (PHONE_LEFT, PHONE_TOP), rounded_mask((PHONE_W, new_h), CORNER_RADIUS))
    bg.save(out_path)
    print("wrote", out_path, bg.size)


# Raw capture recipe for each screen (SIMCTL_CHILD_ env vars on `simctl launch`):
#   1_tenpai   DEMO_HAND=1112345678999m DEMO_NOSCROLL=1        (nine-gates shape, tenpai on all 9 tiles)
#   2_discard  DEMO_HAND=12345678m123456p                      (14 tiles, auto-scrolls to 打牌建议)
#   3_shanten  DEMO_HAND=1245678m123567p                       (13 tiles, 1-shanten, auto-scrolls to result)
#   4_input    DEMO_HAND=345s123p DEMO_ANALYZE=0                (partial hand, stays unanalyzed)
#   5_scoring  DEMO_HAND=1111223344556m DEMO_SHEET=6m           (清豪七 tenpai, pops fan-breakdown sheet)
#   6_photo    从设置里「从相册选择识别手牌」挑一张 data/preview/*.jpg，停在裁剪页（自动框已画好）
# DEMO_NOSCROLL=1 is a scratch-only env var (see ContentView.scrollToResult) — keep it if still present,
# it just skips the auto-scroll-to-result animation so the top-of-page framing is captured cleanly.
SCREENS = [
    dict(
        raw="1_tenpai.png",
        caption="四川麻将 · 听牌计算器",
        headline="一眼算清听什么牌",
        subtitle="13 张自动判断听牌，列出所有能胡的牌",
    ),
    dict(
        raw="2_discard.png",
        caption="四川麻将 · 听牌计算器",
        headline="该打哪张？秒出最优解",
        subtitle="14 张逐一比较，给出向听数与进张建议",
        crop_top=140,
    ),
    dict(
        raw="3_shanten.png",
        caption="四川麻将 · 听牌计算器",
        headline="向听 · 进张 一目了然",
        subtitle="离听牌还差几张，摸什么牌最有用",
        crop_top=140,
    ),
    dict(
        raw="4_input.png",
        caption="四川麻将 · 听牌计算器",
        headline="真实牌面，上手就会",
        subtitle="点选或拍照识别，万 · 筒 · 条 一眼分辨",
    ),
    dict(
        raw="5_scoring.png",
        caption="四川麻将 · 听牌计算器",
        headline="算番算钱，一步到位",
        subtitle="点开任意听牌，看番型明细与点炮/自摸金额",
        crop_top=140,
    ),
    dict(
        raw="6_photo.png",
        caption="四川麻将 · 听牌计算器",
        headline="拍一张，自动认牌",
        subtitle="自动框出你的手牌与碰杠，桌上别人的牌不会算进来",
        crop_top=130,
    ),
]

if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    for s in SCREENS:
        compose(
            os.path.join(RAW_DIR, s["raw"]), os.path.join(OUT_DIR, s["raw"]),
            s["caption"], s["headline"], s["subtitle"],
            crop_top=s.get("crop_top", 0), crop_bottom=s.get("crop_bottom", 0),
        )
