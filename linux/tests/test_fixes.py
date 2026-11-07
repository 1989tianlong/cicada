"""改正听错的词: the record's fixes, read and written as the Mac does (mac-fixes-session.json is a record
the Mac dev build wrote), and the line as shown in display, search and export.
    python3 -m unittest discover -s linux/tests      (scripts/test.sh)"""
from __future__ import annotations

import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from cicada.core import session_store  # noqa: E402
from cicada.core.correction import apply  # noqa: E402
from cicada.core.models import LineFix, Session, TranscriptLine  # noqa: E402
from cicada.core.support import Paths  # noqa: E402


class Base(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp(prefix="cicada-fixes-")
        Paths.home_override = self.home
        Paths.log_override = os.path.join(self.home, "debug.log")

    def tearDown(self):
        Paths.home_override = None
        Paths.log_override = None
        shutil.rmtree(self.home, ignore_errors=True)


class RecordFormat(Base):
    def test_mac_record_with_fixes_round_trips_byte_for_byte(self):
        with open(os.path.join(HERE, "mac-fixes-session.json"), encoding="utf-8") as f:
            text = f.read()
        s = Session.read(text)
        self.assertEqual(s.lines[0].fixes, [LineFix("开布特", "Curve", user=True)])
        self.assertIsNone(s.lines[1].fixes)
        self.assertEqual(s.lines[0].src, "最近那个开布特提了好几次他们那个协议的更新慢。")
        self.assertEqual(s.lines[0].shown, "最近那个Curve提了好几次他们那个协议的更新慢。")
        self.assertEqual(s.lines[2].shown, "就是你不更新它数量就不变但质押这种基本不怎么变。")
        self.assertEqual(s.write(), text)

    def test_unchanged_without_fixes(self):
        line = TranscriptLine(id="1", t=0, speaker="them", src="a", srcLang="zh", dstLang="en")
        s = Session(id="x", title="t", lines=[line])
        self.assertNotIn("fixes", s.write())
        line.fixes = []
        self.assertNotIn("fixes", s.write())  # none is absent, as the Mac stores nil
        line.fixes = [LineFix("a", "b")]
        back = Session.read(s.write()).lines[0]
        self.assertEqual(back.shown, "b")
        self.assertEqual(back.src, "a")
        self.assertIn('"fixes" : [\n        {\n          "from" : "a",\n          "to" : "b"\n        }\n      ]', s.write())

    def test_copy_keeps_fixes_apart(self):
        line = TranscriptLine(id="1", src="质压", fixes=[LineFix("质压", "质押")])
        c = line.copy()
        c.fixes[0].off = True
        self.assertEqual(line.shown, "质押")
        self.assertEqual(c.shown, "质压")

    def test_export_uses_the_shown_text(self):
        with open(os.path.join(HERE, "mac-fixes-session.json"), encoding="utf-8") as f:
            s = Session.read(f.read())
        md = session_store.markdown(s)
        self.assertIn("最近那个Curve提了", md)
        self.assertNotIn("开布特", md)

    def test_store_keeps_fixes_when_the_engine_replaces_a_line(self):
        store = session_store.SessionStore()
        s = store.begin()
        store.append(s.id, TranscriptLine(id="l0", src="但质压这种", fixes=[LineFix("质压", "质押")]))
        store.replace(s.id, TranscriptLine(id="l0", src="但质压这种", dst="But staking"))
        self.assertEqual(store.get(s.id).lines[0].shown, "但质押这种")


class Applying(unittest.TestCase):
    def test_apply_replaces_and_marks(self):
        fixes = [LineFix("莫拉", "Morpho"), LineFix("质压", "质押"), LineFix("开布特", "Curve", ask=True),
                 LineFix("ropax", "RoPax", off=True)]
        text, marks = apply(fixes, "解释这个莫拉的，质压和开布特，ropax")
        self.assertEqual(text, "解释这个Morpho的，质押和开布特，ropax")
        self.assertEqual([text[a:b] for a, b in marks], ["Morpho", "质押"])

    def test_apply_keeps_earlier_marks_when_later_fixes_shift(self):
        text, marks = apply([LineFix("质压", "质押"), LineFix("莫拉", "Morpho")], "莫拉说质压")
        self.assertEqual(text, "Morpho说质押")
        self.assertEqual([text[a:b] for a, b in marks], ["Morpho", "质押"])

    def test_fix_whose_words_went_away_is_skipped(self):
        self.assertEqual(apply([LineFix("莫拉", "Morpho")], "解释这个摩托的")[0], "解释这个摩托的")


if __name__ == "__main__":
    unittest.main()
