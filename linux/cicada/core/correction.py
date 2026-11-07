"""改正听错的词: which of the AI service's proposed fixes to take, and the line as shown once they are
in. A port of the Mac's Correction.swift, rule for rule (its tests are tests/test_correction.py)."""
from __future__ import annotations


def _word(c: str) -> bool:
    """A character of a Latin word: ASCII letters and digits."""
    return c.isascii() and c.isalnum()


def core(frm: str, to: str) -> tuple:
    """The part an edit changes, as a word: "解除质压" → "解除质押" is "质压" → "质押" (at least two
    characters, so one refusal doesn't block every 压 → 押), and a Latin word stays whole
    ("Un450P三" → "Uniswap V3", not "450P三" → "iswap V3")."""
    a, b = frm, to
    i = 0
    while i < min(len(a), len(b)) and a[i] == b[i]:
        i += 1
    j = 0
    while j < min(len(a), len(b)) - i and a[len(a) - 1 - j] == b[len(b) - 1 - j]:
        j += 1

    def from_edge(k):
        return (k < len(a) and _word(a[k])) or (k < len(b) and _word(b[k]))
    # Only a change that starts or ends inside a Latin word takes the rest of the word.
    if from_edge(i):
        while i > 0 and _word(a[i - 1]):
            i -= 1
    if (len(a) - j - 1 >= 0 and _word(a[len(a) - j - 1])) or (len(b) - j - 1 >= 0 and _word(b[len(b) - j - 1])):
        while j > 0 and _word(a[len(a) - j]):
            j -= 1
    # Two characters at least, taken from the Chinese side: "FFT制押" → "FFT质押" is "制押" → "质押".
    while len(a) - j - i < 2 or len(b) - j - i < 2:
        if j > 0 and not _word(a[len(a) - j]):
            j -= 1
        elif i > 0 and not _word(a[i - 1]):
            i -= 1
        else:
            break
    return a[i:len(a) - j], b[i:len(b) - j]


def apply(fixes: list, src: str) -> tuple:
    """The line as shown: each applied fix replaces its words where they still are. The marks are the
    replaced words as (start, end) character offsets into the text, for the underline."""
    text = src
    spans = []  # replacement and its character offset, kept valid as the text changes
    # The user's own last: written against the line as it was shown, other fixes in.
    ordered = [f for f in fixes if f.user is not True] + [f for f in fixes if f.user is True]
    for f in ordered:
        if not f.applied or not f.from_:
            continue
        start = text.find(f.from_)
        if start < 0:
            continue
        delta = len(f.to) - len(f.from_)
        spans = [(w, o + delta) if o > start else (w, o) for w, o in spans]
        text = text[:start] + f.to + text[start + len(f.from_):]
        spans.append((f.to, start))
    marks = sorted((o, o + len(w)) for w, o in spans if o + len(w) <= len(text))
    return text, marks
