#!/usr/bin/env python3
"""Generate Quintile app-icon concepts as SVG (1024x1024, macOS squircle)."""
import random

C = 1024
# macOS icon squircle: content inset with generous transparent padding.
PAD = 88
S = C - 2 * PAD          # squircle side
RX = round(S * 0.2237)   # Apple's continuous-corner ratio approximation
DOTS = [("#FF5F57"), ("#FEBC2E"), ("#28C840")]
# Syntax-ish palette for code-line bars.
CODE = ["#7DD3FC", "#86EFAC", "#FCD34D", "#C4B5FD", "#F9A8D4", "#94A3B8"]


def squircle(fill):
    return f'<rect x="{PAD}" y="{PAD}" width="{S}" height="{S}" rx="{RX}" ry="{RX}" fill="{fill}"/>'


def code_lines(x, y, w, seed, n=5, gap=26, h=12, bright=1.0, term=True):
    """A stack of rounded 'code' bars with varied indents/widths/colors."""
    r = random.Random(seed)
    out = []
    cy = y
    for i in range(n):
        indent = r.choice([0, 0, 18, 30])
        lw = int((w - indent) * r.uniform(0.35, 0.95))
        lw = max(lw, 22)
        col = r.choice(CODE)
        op = 0.9 * bright
        out.append(
            f'<rect x="{x+indent}" y="{cy}" width="{lw}" height="{h}" '
            f'rx="{h/2}" fill="{col}" opacity="{op:.2f}"/>'
        )
        cy += gap
    return "".join(out)


def window(x, y, w, h, seed, fill="#111827", stroke=None, sw=0,
           title=True, lines=5, bright=1.0, rx=18):
    parts = [f'<g>']
    if stroke:
        parts.append(
            f'<rect x="{x-sw/2}" y="{y-sw/2}" width="{w+sw}" height="{h+sw}" '
            f'rx="{rx+sw/2}" fill="none" stroke="{stroke}" stroke-width="{sw}"/>'
        )
    parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"/>')
    inner_top = y + 16
    if title:
        for i, c in enumerate(DOTS):
            parts.append(f'<circle cx="{x+24+i*22}" cy="{y+30}" r="7" fill="{c}" opacity="{0.95*bright:.2f}"/>')
        inner_top = y + 58
    if lines:
        avail = (y + h) - inner_top - 20
        gap = max(22, min(30, avail / lines))
        parts.append(code_lines(x + 22, inner_top, w - 44, seed, n=lines, gap=int(gap), bright=bright))
    parts.append('</g>')
    return "".join(parts)


def defs():
    return f'''<defs>
      <linearGradient id="indigo" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#6366F1"/><stop offset="1" stop-color="#8B5CF6"/></linearGradient>
      <linearGradient id="night" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#1E293B"/><stop offset="1" stop-color="#0F172A"/></linearGradient>
      <linearGradient id="ocean" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#0EA5E9"/><stop offset="1" stop-color="#4F46E5"/></linearGradient>
      <linearGradient id="slate" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#334155"/><stop offset="1" stop-color="#0F172A"/></linearGradient>
      <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#ffffff" stop-opacity="0.18"/>
        <stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/></linearGradient>
      <filter id="soft" x="-20%" y="-20%" width="140%" height="140%">
        <feDropShadow dx="0" dy="6" stdDeviation="10" flood-color="#000000" flood-opacity="0.28"/></filter>
      <filter id="glow" x="-40%" y="-40%" width="180%" height="180%">
        <feDropShadow dx="0" dy="0" stdDeviation="14" flood-color="#38BDF8" flood-opacity="0.9"/></filter>
    </defs>'''


def sheen():
    # subtle top gloss inside the squircle
    return f'<rect x="{PAD}" y="{PAD}" width="{S}" height="{S/2}" rx="{RX}" fill="url(#sheen)"/>'


def wrap(body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{C}" height="{C}" viewBox="0 0 {C} {C}">'
            f'{defs()}{body}</svg>')


# ---------------------------------------------------------------- concepts

def concept_A():
    """Five terminal windows in a row (5x1); center one selected."""
    bg = squircle("url(#indigo)") + sheen()
    left, right = PAD + 44, C - PAD - 44
    n = 5
    gap = 16
    cw = (right - left - gap * (n - 1)) / n
    top, bot = PAD + 150, C - PAD - 90
    ch = bot - top
    wins = ['<g filter="url(#soft)">']
    for i in range(n):
        x = left + i * (cw + gap)
        sel = (i == 2)
        if sel:
            wins.append(window(int(x), top, int(cw), int(ch), seed=100 + i,
                               fill="#0B1220", stroke="#38BDF8", sw=8,
                               lines=6, bright=1.15))
        else:
            wins.append(window(int(x), top, int(cw), int(ch), seed=100 + i,
                               fill="#111827", lines=6, bright=0.8))
    wins.append('</g>')
    return wrap(bg + "".join(wins))


def concept_B():
    """5x2 grid with luminous lines; two top cells merged into a span."""
    bg = squircle("url(#night)")
    left, right = PAD + 40, C - PAD - 40
    top, bot = PAD + 60, C - PAD - 60
    cols, rows = 5, 2
    gw, gh = right - left, bot - top
    cw, chh = gw / cols, gh / rows
    body = [bg]
    # dim window cells
    def cell(cx, cy, cwn, chn, seed, bright, fill, stroke=None, sw=0):
        return window(int(cx + 10), int(cy + 10), int(cwn - 20), int(chn - 20),
                      seed=seed, fill=fill, stroke=stroke, sw=sw,
                      lines=3, bright=bright, rx=14)
    g = ['<g filter="url(#soft)">']
    # top row: cells 0..4 but 1&2 merged span
    # merged span over col1-col2
    g.append(cell(left + cw*1, top, cw*2, chh, seed=11, bright=1.15,
                  fill="#0B1220", stroke="#38BDF8", sw=7))
    for c in [0, 3, 4]:
        g.append(cell(left + cw*c, top, cw, chh, seed=20+c, bright=0.7, fill="#111827"))
    for c in range(5):
        g.append(cell(left + cw*c, top + chh, cw, chh, seed=40+c, bright=0.7, fill="#111827"))
    g.append('</g>')
    return wrap("".join(body + g))


def concept_C():
    """5x1 columns with a move arrow between two cells (the 'move-within-grid' idea)."""
    bg = squircle("url(#ocean)") + sheen()
    left, right = PAD + 44, C - PAD - 44
    n = 5
    gap = 16
    cw = (right - left - gap * (n - 1)) / n
    top, bot = PAD + 150, C - PAD - 90
    ch = bot - top
    body = ['<g filter="url(#soft)">']
    for i in range(n):
        x = left + i * (cw + gap)
        occupied = i in (0, 4)
        if occupied:
            body.append(window(int(x), top, int(cw), int(ch), seed=200+i,
                               fill="#0B1220", lines=6, bright=1.0))
        else:
            # empty slot outline
            body.append(f'<rect x="{int(x)}" y="{top}" width="{int(cw)}" height="{int(ch)}" '
                        f'rx="18" fill="#0B1220" opacity="0.28" '
                        f'stroke="#ffffff" stroke-opacity="0.28" stroke-width="3" stroke-dasharray="10 12"/>')
    body.append('</g>')
    # arrow from col0 toward col1
    ay = top + ch/2
    ax0 = left + cw + 2
    ax1 = left + cw + gap + cw*0.5
    body.append(f'<g><line x1="{ax0}" y1="{ay}" x2="{ax1}" y2="{ay}" stroke="#38BDF8" '
                f'stroke-width="14" stroke-linecap="round"/>'
                f'<path d="M {ax1-6} {ay-26} L {ax1+30} {ay} L {ax1-6} {ay+26} Z" fill="#38BDF8"/></g>')
    return wrap(bg + "".join(body))


def concept_D():
    """Bold minimal: five rounded bars, one accent; tiny code marks. Best at small sizes."""
    bg = squircle("url(#slate)") + sheen()
    left, right = PAD + 70, C - PAD - 70
    n = 5
    gap = 22
    cw = (right - left - gap * (n - 1)) / n
    top, bot = PAD + 150, C - PAD - 150
    ch = bot - top
    body = ['<g filter="url(#soft)">']
    for i in range(n):
        x = left + i * (cw + gap)
        sel = (i == 2)
        fill = "#38BDF8" if sel else "#E2E8F0"
        body.append(f'<rect x="{int(x)}" y="{top}" width="{int(cw)}" height="{ch}" rx="26" fill="{fill}"/>')
        # two short "code" marks near the top of each bar
        mc = "#0B1220" if sel else "#334155"
        body.append(f'<rect x="{int(x)+22}" y="{top+30}" width="{int(cw)-60}" height="12" rx="6" fill="{mc}" opacity="0.8"/>')
        body.append(f'<rect x="{int(x)+22}" y="{top+58}" width="{int(cw)-90}" height="12" rx="6" fill="{mc}" opacity="0.6"/>')
    body.append('</g>')
    return wrap(bg + "".join(body))


def concept_A_small():
    """Small-size variant of A: no traffic dots, 2 bold code lines, thicker highlight."""
    bg = squircle("url(#indigo)") + sheen()
    left, right = PAD + 40, C - PAD - 40
    n = 5
    gap = 20
    cw = (right - left - gap * (n - 1)) / n
    top, bot = PAD + 120, C - PAD - 120
    ch = bot - top
    wins = ['<g filter="url(#soft)">']
    for i in range(n):
        x = int(left + i * (cw + gap))
        sel = (i == 2)
        fill = "#0B1220" if sel else "#111827"
        stroke = "#38BDF8" if sel else None
        sw = 12 if sel else 0
        if stroke:
            wins.append(f'<rect x="{x-sw/2}" y="{top-sw/2}" width="{int(cw)+sw}" height="{ch+sw}" '
                        f'rx="{22+sw/2}" fill="none" stroke="{stroke}" stroke-width="{sw}"/>')
        wins.append(f'<rect x="{x}" y="{top}" width="{int(cw)}" height="{ch}" rx="22" fill="{fill}"/>')
        # two bold code bars
        c1 = "#7DD3FC" if sel else "#86EFAC"
        c2 = "#FCD34D" if sel else "#94A3B8"
        bw = int(cw) - 44
        wins.append(f'<rect x="{x+22}" y="{top+40}" width="{bw}" height="26" rx="13" fill="{c1}"/>')
        wins.append(f'<rect x="{x+22}" y="{top+92}" width="{int(bw*0.62)}" height="26" rx="13" fill="{c2}" opacity="0.85"/>')
    wins.append('</g>')
    return wrap(bg + "".join(wins))


concepts = {"A": concept_A, "B": concept_B, "C": concept_C, "D": concept_D,
            "Asmall": concept_A_small}
for name, fn in concepts.items():
    open(f"concept-{name}.svg", "w").write(fn())
    print(f"wrote concept-{name}.svg")
