#!/usr/bin/env python3
"""Writes plain stand-in sources (PNG and WAV) for the Playdate SDK assets the patched Cranked embeds, for builds
meant for distribution (prepare-sdk-assets.sh --distributable compiles them with pdc).

Each stand-in has the file name, image size, image-table cell size and frame count, and audio format (channels,
sample size or ADPCM, rate, length) of the asset it replaces; only those sizes are read from the SDK's sources (or,
for Cranked's own older copies, from the compiled files in core/resources). The pictures and sounds are drawn here:
crank frames are a circle with a handle turning frame by frame, the notice bubble a rounded rectangle, the notice text
the word CRANK made of rectangles, the keyboard keys outlined boxes with a line glyph, and the sounds short quiet sine
blips.

Usage: make-standin-assets.py <PlaydateSDK folder> <cranked core/resources folder> <output source folder>
The output folder gets crank-3.1.1/, keyboard-3.1.1/ and upstream/, laid out so that pdc compiles each file to the
name the build embeds (image tables as <name>-table-<w>-<h>.png).
"""
import math
import os
import re
import struct
import sys
import wave
import zlib

# --- reading sizes ---------------------------------------------------------------------------------------------

def png_size(path):
    with open(path, 'rb') as f:
        head = f.read(24)
    if head[:8] != b'\x89PNG\r\n\x1a\n' or head[12:16] != b'IHDR':
        raise ValueError(f'{path}: not a PNG')
    return struct.unpack('>II', head[16:24])


def wav_format(path):
    """(format tag, channels, rate, bits, block align, frames) from a WAV's fmt, fact and data chunks."""
    with open(path, 'rb') as f:
        data = f.read()
    if data[:4] != b'RIFF' or data[8:12] != b'WAVE':
        raise ValueError(f'{path}: not a WAV')
    fmt = fact = None
    size = 0
    i = 12
    while i + 8 <= len(data):
        cid, n = data[i:i + 4], struct.unpack_from('<I', data, i + 4)[0]
        if cid == b'fmt ':
            fmt = struct.unpack_from('<HHIIHH', data, i + 8)
        elif cid == b'fact':
            fact = struct.unpack_from('<I', data, i + 8)[0]
        elif cid == b'data':
            size = n
        i += 8 + n + (n & 1)
    tag, channels, rate, _, align, bits = fmt
    if tag == 1:
        frames = size // align
    elif fact is not None:
        frames = fact
    else:  # IMA ADPCM without a fact chunk: count from the blocks
        per_block = (align - 4 * channels) * 8 // (4 * channels) + 1
        frames = size // align * per_block
    return tag, channels, rate, bits, align, frames


def compiled_body(data):
    flags = struct.unpack_from('<I', data, 12)[0]
    return zlib.decompress(data[32:]) if flags & 0x80000000 else data[16:]


def cell_size(body, offset=0):
    cw, ch, _, left, right, top, bottom, _ = struct.unpack_from('<8H', body, offset)
    return left + cw + right, top + ch + bottom


def compiled_info(path):
    """Sizes from a compiled .pdi (w, h), .pdt (cell w, cell h, frames) or .pda (format, rate, frames)."""
    with open(path, 'rb') as f:
        data = f.read()
    magic = data[:12]
    if magic == b'Playdate IMG':
        return cell_size(compiled_body(data))
    if magic == b'Playdate IMT':
        body = compiled_body(data)
        count = struct.unpack_from('<H', body, 0)[0]
        return cell_size(body, 4 + 4 * (count - 1) + 4) + (count,)
    if magic == b'Playdate AUD':
        word = struct.unpack_from('<I', data, 12)[0]
        fmt, rate = word >> 24, word & 0xFFFFFF
        size = len(data) - 16
        if fmt in (0, 1, 2, 3):
            frames = size // ({0: 1, 1: 2, 2: 2, 3: 4}[fmt])
        else:
            frames = size * 2 // (2 if fmt == 5 else 1)  # about two samples a byte; close enough for a stand-in
        return fmt, rate, frames
    raise ValueError(f'{path}: unknown file type')

# --- drawing -----------------------------------------------------------------------------------------------------

CLEAR, BLACK, WHITE = 0, 1, 2


class Canvas:
    def __init__(self, w, h, fill=CLEAR):
        self.w, self.h = w, h
        self.px = [[fill] * w for _ in range(h)]

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(xx, yy, c)

    def frame(self, x, y, w, h, c):
        self.rect(x, y, w, 1, c)
        self.rect(x, y + h - 1, w, 1, c)
        self.rect(x, y, 1, h, c)
        self.rect(x + w - 1, y, 1, h, c)

    def line(self, x0, y0, x1, y1, c):
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.set(x0, y0, c)
            if x0 == x1 and y0 == y1:
                return
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def ellipse(self, cx, cy, rx, ry, outline, fill):
        for y in range(self.h):
            for x in range(self.w):
                d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2
                if d <= 1:
                    inner = ((x + 0.5 - cx) / max(rx - 1, 0.5)) ** 2 + ((y + 0.5 - cy) / max(ry - 1, 0.5)) ** 2
                    self.set(x, y, fill if inner <= 1 else outline)

    def rounded(self, x, y, w, h, r, c):
        for yy in range(h):
            for xx in range(w):
                cx = min(max(xx, r), w - 1 - r)
                cy = min(max(yy, r), h - 1 - r)
                if (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r:
                    self.set(x + xx, y + yy, c)

    def blit(self, other, ox, oy):
        for y in range(other.h):
            for x in range(other.w):
                if other.px[y][x] != CLEAR:
                    self.set(ox + x, oy + y, other.px[y][x])

    def png(self, path):
        """Writes the canvas as an 8-bit grey and alpha PNG."""
        raw = bytearray()
        for row in self.px:
            raw.append(0)
            for c in row:
                raw += b'\x00\x00' if c == CLEAR else (b'\x00\xff' if c == BLACK else b'\xff\xff')

        def chunk(kind, payload):
            return struct.pack('>I', len(payload)) + kind + payload + \
                struct.pack('>I', zlib.crc32(kind + payload) & 0xFFFFFFFF)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'wb') as f:
            f.write(b'\x89PNG\r\n\x1a\n')
            f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', self.w, self.h, 8, 4, 0, 0, 0)))
            f.write(chunk(b'IDAT', zlib.compress(bytes(raw), 9)))
            f.write(chunk(b'IEND', b''))


def crank_frame(w, h, index, count):
    """A circle with a handle line from its centre, turned by index/count of a revolution."""
    c = Canvas(w, h)
    cx, cy = w / 2, h / 2
    r = max(min(w, h) / 2 - 0.5, 1)
    c.ellipse(cx, cy, r, r, BLACK, WHITE)
    a = 2 * math.pi * index / count
    x1 = int(round(cx - 0.5 + (r - 1) * math.sin(a)))
    y1 = int(round(cy - 0.5 - (r - 1) * math.cos(a)))
    c.line(int(cx - 0.5), int(cy - 0.5), x1, y1, BLACK)
    return c


def crank_table(w, h, count):
    t = Canvas(w * count, h)
    for i in range(count):
        t.blit(crank_frame(w, h, i, count), i * w, 0)
    return t


def notice_bubble(w, h):
    c = Canvas(w, h)
    c.rounded(0, 0, w, h, max(1, min(w, h) // 5), BLACK)
    return c


# the word CRANK on a 3 by 5 grid, one string per row, drawn as rectangles
WORD = {
    'C': ['###', '#..', '#..', '#..', '###'],
    'R': ['##.', '#.#', '##.', '#.#', '#.#'],
    'A': ['.#.', '#.#', '###', '#.#', '#.#'],
    'N': ['#.#', '###', '###', '###', '#.#'],
    'K': ['#.#', '##.', '#..', '##.', '#.#'],
}


def notice_text(w, h):
    c = Canvas(w, h)
    letters = 'CRANK'
    units = len(letters) * 4 - 1
    s = max(1, min(w // units, h // 5))
    x = (w - units * s) // 2
    y = (h - 5 * s) // 2
    for ch in letters:
        for row, bits in enumerate(WORD[ch]):
            for col, b in enumerate(bits):
                if b == '#':
                    c.rect(x + col * s, y + row * s, s, s, WHITE)
        x += 4 * s
    return c


def menu_key(name, w, h):
    """An outlined box with a glyph from lines: X (cancel), a left arrow (del), a tick (ok), a space bracket."""
    c = Canvas(w, h)
    if name == 'menu-space':
        c.rect(0, 0, 1, h, BLACK)
        c.rect(w - 1, 0, 1, h, BLACK)
        c.rect(0, h - 1, w, 1, BLACK)
        return c
    c.frame(0, 0, w, h, BLACK)
    gh = max(h - 5, 1)
    gx, gy = (w - gh) // 2, (h - gh) // 2
    g = gh - 1
    if name == 'menu-cancel':
        c.line(gx, gy, gx + g, gy + g, BLACK)
        c.line(gx, gy + g, gx + g, gy, BLACK)
    elif name == 'menu-del':
        mid = gy + g // 2
        c.line(gx - g // 2, mid, gx + g + g // 2, mid, BLACK)
        c.line(gx - g // 2, mid, gx, mid - g // 2, BLACK)
        c.line(gx - g // 2, mid, gx, mid + g // 2, BLACK)
    elif name == 'menu-ok':
        c.line(gx, gy + g // 2, gx + g // 3, gy + g, BLACK)
        c.line(gx + g // 3, gy + g, gx + g, gy, BLACK)
    return c

# --- sounds ------------------------------------------------------------------------------------------------------

def blip(frames, rate, freq=880.0, level=0.08):
    """A quiet sine with a short fade in and a fade out over the rest, as 16-bit samples."""
    out = []
    attack = max(1, min(frames // 10, rate // 200))
    for i in range(frames):
        env = min(1.0, i / attack) * (1 - i / frames) ** 2
        out.append(int(32767 * level * env * math.sin(2 * math.pi * freq * i / rate)))
    return out


def write_pcm(path, channels, rate, bits, samples):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, 'wb') as w:
        w.setnchannels(channels)
        w.setsampwidth(bits // 8)
        w.setframerate(rate)
        if bits == 8:
            w.writeframes(bytes(((s >> 8) + 128) & 0xFF for s in samples for _ in range(channels)))
        else:
            w.writeframes(b''.join(struct.pack('<h', s) * channels for s in samples))


IMA_INDEX = [-1, -1, -1, -1, 2, 4, 6, 8] * 2
IMA_STEP = [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88,
            97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724,
            796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026,
            4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500,
            20350, 22385, 24623, 27086, 29794, 32767]


def ima_encode(samples, state):
    pred, index = state
    nibbles = []
    for s in samples:
        step = IMA_STEP[index]
        diff = s - pred
        code = 8 if diff < 0 else 0
        diff = abs(diff)
        delta = step >> 3
        if diff >= step:
            code |= 4
            diff -= step
            delta += step
        if diff >= step >> 1:
            code |= 2
            diff -= step >> 1
            delta += step >> 1
        if diff >= step >> 2:
            code |= 1
            delta += step >> 2
        pred = max(-32768, min(32767, pred - delta if code & 8 else pred + delta))
        index = max(0, min(88, index + IMA_INDEX[code]))
        nibbles.append(code)
    return nibbles, (pred, index)


def write_ima_adpcm(path, rate, align, samples):
    """A mono IMA ADPCM WAV (format 0x11) with the given block size."""
    per_block = (align - 4) * 2 + 1
    body = bytearray()
    for start in range(0, len(samples), per_block):
        block = samples[start:start + per_block]
        first = block[0]
        body += struct.pack('<hBB', first, 0, 0)
        nibbles, _ = ima_encode(block[1:], (first, 0))
        nibbles += [0] * (-len(nibbles) % 8)
        for i in range(0, len(nibbles), 2):
            body.append(nibbles[i] | (nibbles[i + 1] << 4))
    fmt = struct.pack('<HHIIHHHH', 0x11, 1, rate, rate * align // per_block, align, 4, 2, per_block)
    fact = struct.pack('<I', len(samples))
    riff = b'WAVE' + b'fmt ' + struct.pack('<I', len(fmt)) + fmt + b'fact' + struct.pack('<I', 4) + fact + \
        b'data' + struct.pack('<I', len(body)) + bytes(body) + (b'\x00' if len(body) & 1 else b'')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(b'RIFF' + struct.pack('<I', len(riff)) + riff)


def sound(path, tag, channels, rate, bits, align, frames, freq):
    samples = blip(frames, rate, freq)
    if tag == 0x11:
        if channels != 1:
            raise ValueError(f'{path}: only mono ADPCM is written')
        write_ima_adpcm(path, rate, align, samples)
    else:
        write_pcm(path, channels, rate, bits, samples)

# --- the assets --------------------------------------------------------------------------------------------------

def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__.strip().split('\n\n')[-1])
    sdk, resources, out = sys.argv[1:]
    crank = os.path.join(sdk, 'CoreLibs', 'assets', 'crank')
    keyboard = os.path.join(sdk, 'CoreLibs', 'assets', 'keyboard')
    sfx = os.path.join(sdk, 'CoreLibs', 'assets', 'sfx')
    made = []

    def image(c, path):
        c.png(path)
        made.append(path)

    # the SDK 3.1.1 crank indicator
    tables = {}
    for name in sorted(os.listdir(crank)):
        m = re.fullmatch(r'(crank-frames-(\d+)x)-table-(\d+)-(\d+)\.png', name)
        if m:
            base, cw, ch = m.group(1), int(m.group(3)), int(m.group(4))
            w, h = png_size(os.path.join(crank, name))
            count = (w // cw) * (h // ch)
            tables[m.group(2)] = (cw, ch, count)
            image(crank_table(cw, ch, count), os.path.join(out, 'crank-3.1.1', f'{base}-table-{cw}-{ch}.png'))
        elif re.fullmatch(r'crank-notice-(bubble|text)(-\d+x)?\.png', name):
            w, h = png_size(os.path.join(crank, name))
            draw = notice_bubble if 'bubble' in name else notice_text
            image(draw(w, h), os.path.join(out, 'crank-3.1.1', name))

    # the SDK 3.1.1 keyboard keys and sounds
    keys = {}
    for name in ('menu-cancel', 'menu-del', 'menu-ok', 'menu-space'):
        w, h = png_size(os.path.join(keyboard, name + '.png'))
        keys[name] = (w, h)
        image(menu_key(name, w, h), os.path.join(out, 'keyboard-3.1.1', name + '.png'))
    for i, name in enumerate(('click', 'denial', 'key', 'selection', 'selection-reverse')):
        src = os.path.join(sfx, name + '.wav')
        if os.path.exists(src):
            path = os.path.join(out, 'keyboard-3.1.1', name + '.wav')
            sound(path, *wav_format(src), freq=660.0 + 110.0 * i)
            made.append(path)

    # Cranked's own older copies (sizes from the compiled files when present, else from the SDK's equivalents)
    def upstream(name, fallback):
        path = os.path.join(resources, name)
        return compiled_info(path) if os.path.exists(path) else fallback

    up = os.path.join(out, 'upstream')
    for suffix, scale in (('', '1'), ('-2x', '2'), ('-4x', '4'), ('-8x', '8')):
        cw, ch, count = upstream(f'crank-frames{suffix}.pdt', tables.get(scale))
        image(crank_table(cw, ch, count), os.path.join(up, f'crank-frames{suffix}-table-{cw}-{ch}.png'))
    for name, sdk_name in (('crank-notice-bubble', 'crank-notice-bubble-1x'), ('crank-notice-bubble-2x', None),
                           ('crank-notice-bubble-4x', None), ('crank-notice-bubble-8x', None),
                           ('crank-notice-text', 'crank-notice-text-1x'), ('crank-notice-text-2x', None)):
        w, h = upstream(name + '.pdi', png_size(os.path.join(crank, (sdk_name or name) + '.png')))
        image((notice_bubble if 'bubble' in name else notice_text)(w, h), os.path.join(up, name + '.png'))
    for name in keys:
        w, h = upstream(name + '.pdi', keys[name])
        image(menu_key(name, w, h), os.path.join(up, name + '.png'))
    fmt, rate, frames = upstream('bounce.pda', (3, 44100, 28483))
    if fmt not in (0, 1, 2, 3):
        fmt = 2
    channels, bits = (1 if fmt in (0, 2) else 2), (8 if fmt in (0, 1) else 16)
    path = os.path.join(up, 'bounce.wav')
    sound(path, 1, channels, rate, bits, channels * bits // 8, frames, freq=330.0)
    made.append(path)

    for path in made:
        print(os.path.relpath(path, out))


if __name__ == '__main__':
    main()
