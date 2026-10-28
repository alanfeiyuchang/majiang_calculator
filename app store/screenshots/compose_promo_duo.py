#!/usr/bin/env python3
"""
Regenerate the iPhone Duo App Store screenshots from raw simulator captures.

Usage: capture fresh raw screenshots into raw-duo/<name>.png, then run:

    python3 compose_promo_duo.py

Same visual language as compose_promo.py (gradient + 金 caption / 白 headline /
薄荷 subtitle + 圆角投影的机身图)，只是画布换成 iPhone Duo 外屏的 1398×2034。

关于尺寸：App Store Connect 的 iPhone Duo 槽位收 1398×2034、2034×1398、
2007×2853、2007 的横版，也就是外屏和内屏两套都认。这里用的是**外屏**原生尺寸，
因为内屏（2007×2853）在模拟器上截不到——模拟器没有折叠 / 展开开关，只有真机能截。
真要换成内屏，把 CANVAS 改成 2007×2853，raw 换成真机 devicectl 截的图即可，
其它常数都是按画布宽度推的，会自己跟着走。

画布比 6.5" 那套矮得多（2034 对 2688），所以文字块压得更紧、机身图起点更高，
不是按同一组绝对坐标缩放来的。
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
RAW_DIR = os.path.join(HERE, "raw-duo")
OUT_DIR = os.path.join(HERE, "iphone-duo")

CANVAS_W, CANVAS_H = 1398, 2034
TOP_COLOR = (40, 129, 90)
BOTTOM_COLOR = (12, 56, 35)
GOLD = (246, 212, 136)
WHITE = (255, 255, 255)
MINT = (207, 233, 220)

FONT_MED = "/System/Library/Fonts/STHeiti Medium.ttc"
FONT_LIGHT = "/System/Library/Fonts/STHeiti Light.ttc"

CAPTION_SIZE, CAPTION_Y = 46, 92
HEADLINE_Y = 158
SUBTITLE_SIZE, SUBTITLE_Y = 42, 316

PHONE_W = 1020
PHONE_TOP = 440
PHONE_LEFT = (CANVAS_W - PHONE_W) // 2
CORNER_RADIUS = 68


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


def fit_headline_font(text, max_width, start_size=108, min_size=64):
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

    draw_tracked_text(draw, CAPTION_Y, caption, ImageFont.truetype(FONT_MED, CAPTION_SIZE),
                      GOLD, tracking=4, center_x=cx)

    headline_font = fit_headline_font(headline, CANVAS_W - 140)
    hbbox = headline_font.getbbox(headline)
    draw.text((cx - (hbbox[2] - hbbox[0]) / 2 - hbbox[0], HEADLINE_Y), headline,
              font=headline_font, fill=WHITE)

    sub_font = ImageFont.truetype(FONT_LIGHT, SUBTITLE_SIZE)
    sbbox = sub_font.getbbox(subtitle)
    draw.text((cx - (sbbox[2] - sbbox[0]) / 2 - sbbox[0], SUBTITLE_Y), subtitle,
              font=sub_font, fill=MINT)

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


# raw-duo/ 的抓取配方（在 iPhone Duo 模拟器上 `simctl launch` 时带 SIMCTL_CHILD_ 前缀）：
#   玩法（川麻 / 国标）是持久化设置，DEMO_MODE 只改 viewModel，onAppear 会被 ruleStore 覆盖回去。
#   所以截国标那两张之前，要先在界面上把标题菜单切到「国标麻将」，川麻同理。
#   sc_tenpai   DEMO_HAND=1112345678999m DEMO_NOSCROLL=1
#   sc_discard  DEMO_HAND=12345678m123456p
#   sc_input    DEMO_HAND=345s123p DEMO_ANALYZE=0
#   sc_scoring  DEMO_HAND=1111223344556m DEMO_SHEET=6m
#   mcr_tenpai  DEMO_MODE=mcr DEMO_HAND=1112345678999m DEMO_NOSCROLL=1
#   mcr_score   DEMO_MODE=mcr DEMO_HAND=1111223344556m DEMO_SHEET=6m
SCREENS = [
    dict(
        raw="sc_tenpai.png",
        caption="四川麻将 · 听牌计算器",
        headline="一眼算清听什么牌",
        subtitle="13 张自动判断听牌，列出所有能胡的牌",
    ),
    dict(
        raw="sc_discard.png",
        caption="四川麻将 · 听牌计算器",
        headline="该打哪张？秒出最优解",
        subtitle="14 张逐一比较，给出向听数与进张建议",
        crop_top=130,
    ),
    dict(
        raw="sc_scoring.png",
        caption="四川麻将 · 听牌计算器",
        headline="算番算钱，一步到位",
        subtitle="点开任意听牌，看番型明细与点炮/自摸金额",
        crop_top=150,
    ),
    dict(
        raw="sc_input.png",
        caption="四川麻将 · 听牌计算器",
        headline="真实牌面，上手就会",
        subtitle="点选或拍照识别，万 · 筒 · 条 一眼分辨",
    ),
    dict(
        raw="mcr_tenpai.png",
        caption="国标麻将 · 听牌计算器",
        headline="国标麻将，一样算得清",
        subtitle="81 种番种、起和 8 分，吃与风牌箭牌花牌齐全",
    ),
    dict(
        raw="mcr_score.png",
        caption="国标麻将 · 听牌计算器",
        headline="番分明细，一点就懂",
        subtitle="点炮 / 自摸分开算，花牌单独计入，每种番型都有解释",
        crop_top=170,
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
