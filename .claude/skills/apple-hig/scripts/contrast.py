#!/usr/bin/env python3
"""WCAG 2.x 대비 비율 계산기 — design-critic이 색 토큰 조합을 수치로 검증한다.

사용법:
    python3 contrast.py "#FFFFFF" "#7A5AF8"
    python3 contrast.py FAF9FF 1C1830

출력: 대비 비율 + 일반/큰 글자에 대한 AA·AAA PASS/FAIL.

WCAG 기준:
    일반 텍스트  AA >= 4.5:1   AAA >= 7:1
    큰 텍스트    AA >= 3:1     AAA >= 4.5:1
    (큰 텍스트 = 18.66px bold 또는 24px+ regular)
"""
import sys


def _hex_to_rgb(h: str):
    h = h.strip().lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    if len(h) != 6:
        raise ValueError(f"잘못된 hex 색상: {h!r} (예: #7A5AF8)")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def _linearize(c: float) -> float:
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def _luminance(rgb) -> float:
    r, g, b = (_linearize(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(fg: str, bg: str) -> float:
    l1, l2 = _luminance(_hex_to_rgb(fg)), _luminance(_hex_to_rgb(bg))
    lighter, darker = max(l1, l2), min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)


def _verdict(ratio: float, threshold: float) -> str:
    return "PASS" if ratio >= threshold else "FAIL"


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 2
    fg, bg = argv[1], argv[2]
    try:
        ratio = contrast_ratio(fg, bg)
    except ValueError as e:
        print(f"오류: {e}")
        return 2
    print(f"{fg}  vs  {bg}")
    print(f"대비 비율: {ratio:.2f}:1")
    print(f"  일반 텍스트  AA(4.5):  {_verdict(ratio, 4.5)}   AAA(7):   {_verdict(ratio, 7.0)}")
    print(f"  큰 텍스트    AA(3.0):  {_verdict(ratio, 3.0)}   AAA(4.5): {_verdict(ratio, 4.5)}")
    return 0 if ratio >= 4.5 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
