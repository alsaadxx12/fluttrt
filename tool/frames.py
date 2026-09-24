"""Frame drops while scrolling, measured on the phone over adb.

Turns SurfaceFlinger's frame statistics on, swipes the screen up and down
a few times, and prints how many of the app's frames arrived a whole
refresh late (one dropped) or later (a stall). Run it before and after a
change, on the same page, and compare the numbers instead of the feeling.

    python tool/frames.py                 # 3 swipes each way, full height
    python tool/frames.py --swipes 5 --from 1500 --to 700   # a shorter stroke
"""
import argparse
import re
import subprocess
import time

PKG = 'com.antigravity.yt.youtube_downloader'


def adb(*args, capture=False):
    r = subprocess.run(['adb', 'shell', *args], capture_output=True, text=True, encoding='utf-8', errors='replace')
    return r.stdout if capture else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--swipes', type=int, default=3)
    ap.add_argument('--x', type=int, default=540)
    ap.add_argument('--from', dest='y_from', type=int, default=1900)
    ap.add_argument('--to', dest='y_to', type=int, default=500)
    ap.add_argument('--ms', type=int, default=350, help='swipe duration')
    a = ap.parse_args()

    adb('dumpsys', 'SurfaceFlinger', '--timestats', '-enable')
    adb('dumpsys', 'SurfaceFlinger', '--timestats', '-clear')
    for _ in range(a.swipes):
        adb('input', 'swipe', str(a.x), str(a.y_from), str(a.x), str(a.y_to), str(a.ms))
        time.sleep(0.25)
    for _ in range(a.swipes):
        adb('input', 'swipe', str(a.x), str(a.y_to), str(a.x), str(a.y_from), str(a.ms))
        time.sleep(0.25)
    time.sleep(1)
    dump = adb('dumpsys', 'SurfaceFlinger', '--timestats', '-dump', capture=True) or ''
    adb('dumpsys', 'SurfaceFlinger', '--timestats', '-disable')

    # The app's own surface, not the launcher's or the shade's.
    block = None
    for part in dump.split('layerName = ')[1:]:
        head = part.split('\n', 1)[0]
        if PKG in head and 'SurfaceView' in head:
            block = part
            break
    if block is None:
        print('the app was not on screen (no frames from it)')
        return

    total = int(re.search(r'^totalFrames = (\d+)', block, re.M).group(1))
    hist = re.search(r'present2present histogram is as below:\n(.*)', block).group(1)
    buckets = {int(k): int(v) for k, v in re.findall(r'(\d+)ms=(\d+)', hist)}
    period = 1000 / 120
    on_time = sum(v for k, v in buckets.items() if k <= period)
    one_late = sum(v for k, v in buckets.items() if period < k <= 2 * period)
    stalls = {k: v for k, v in buckets.items() if k > 2 * period and v}
    print(f'frames: {total}   on time: {on_time}   one dropped: {one_late} ({100 * one_late / max(total, 1):.1f}%)')
    print('stalls:', ' '.join(f'{k}ms x{v}' for k, v in sorted(stalls.items())) or 'none')


if __name__ == '__main__':
    main()
