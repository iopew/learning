# Draws Resources/AppIcon.png (1024x1024). Usage: python3 tools/make_icon.py Resources/AppIcon.png  (needs Pillow)
import math, sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SCALE = 4  # supersample for smooth edges
W = S * SCALE

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

img = Image.new("RGBA", (W, W), (0, 0, 0, 0))

# Shadow
inset = 100 * SCALE
radius = 185 * SCALE
shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle(
    (inset, inset + 18 * SCALE, W - inset, W - inset + 18 * SCALE), radius, fill=(0, 0, 0, 110))
shadow = shadow.filter(ImageFilter.GaussianBlur(22 * SCALE))
img.alpha_composite(shadow)

# Background gradient inside the rounded square
top, bottom = (84, 132, 255), (118, 62, 232)
grad = Image.new("RGBA", (W, W))
gd = ImageDraw.Draw(grad)
for y in range(W):
    t = y / (W - 1)
    gd.line([(0, y), (W, y)], fill=lerp(top, bottom, t) + (255,))
mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).rounded_rectangle((inset, inset, W - inset, W - inset), radius, fill=255)
img.paste(grad, (0, 0), mask)

d = ImageDraw.Draw(img)
cx = cy = W // 2
white = (255, 255, 255, 255)

# Activity arc segments around the clock (like a day ring): a few colored arcs
ring_r = 300 * SCALE
ring_w = 46 * SCALE
bbox = (cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r)
base = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(base).arc(bbox, 0, 360, fill=(255, 255, 255, 80), width=ring_w)
img.alpha_composite(base)
d = ImageDraw.Draw(img)
for start, end, color in [(-90, 20, (255, 255, 255, 255)), (35, 110, (255, 214, 102, 255)), (125, 165, (120, 230, 190, 255))]:
    d.arc(bbox, start, end, fill=color, width=ring_w)

# Clock hands
def hand(angle_deg, length, width):
    a = math.radians(angle_deg - 90)
    x = cx + math.cos(a) * length
    y = cy + math.sin(a) * length
    d.line([(cx, cy), (x, y)], fill=white, width=width)
    r = width // 2
    d.ellipse((x - r, y - r, x + r, y + r), fill=white)

hand(300, 150 * SCALE, 40 * SCALE)   # hour hand ~10 o'clock
hand(60, 215 * SCALE, 30 * SCALE)    # minute hand ~2 o'clock
r = 34 * SCALE
d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=white)

img = img.resize((S, S), Image.LANCZOS)
img.save(sys.argv[1])
print("saved", sys.argv[1], img.size)
