import json
from pathlib import Path
import unittest

from corpus_runner import run_request
from corpus_summary import summarize


class CorpusTests(unittest.TestCase):
    def test_failure_retains_partial_and_does_not_retry(self):
        class Failed:
            calls = 0
            def run(self, case, mode, emit):
                self.calls += 1
                emit(dict(event="partial", output="Unfinished"))
                raise ValueError("Budget exceeded")
        engine = Failed()
        result = run_request(engine, {}, "focused_terms")
        self.assertFalse(result["ok"])
        self.assertEqual(result["events"][0]["output"], "Unfinished")
        self.assertIn("Budget exceeded", result["error"])
        self.assertEqual(engine.calls, 1)

    def test_summary_excludes_warmup_and_failures_from_latency(self):
        corpus = dict(cases=[dict(id="a", title="A", kind="dialogue", quoted=False, blocks=["A"])])
        successful = dict(ok=True, case_id="a", mode="plain", phase="warm", seconds=4,
                          first_body_part_seconds=2, glossary_seconds=0, output="Result")
        report = dict(complete=True, frozen={}, load_seconds=7, planner_parity={},
                      results=[dict(successful, phase="warmup", seconds=80), successful,
                               dict(ok=False, case_id="a", mode="plain", phase="warm",
                                    seconds=1, error="failure")])
        result = summarize(corpus, report)
        mode = result["cases"][0]["modes"]["plain"]
        self.assertEqual((mode["attempts"], mode["succeeded"]), (2, 1))
        self.assertEqual(mode["seconds"]["median"], 4)
        self.assertEqual(mode["errors"], ["failure"])
        self.assertNotIn("seconds", result["cases"][0]["modes"]["focused_terms"])

    def test_corpus_is_unseeded_and_quotes_are_labelled(self):
        corpus = json.loads(Path(__file__).with_name("corpus.json").read_text())
        cases = corpus["cases"]
        self.assertEqual(len(cases), 8)
        self.assertEqual(len({c["id"] for c in cases}), 8)
        self.assertEqual(sum(not c["quoted"] for c in cases), 7)
        for case in cases:
            self.assertNotIn("glossary", case)
            self.assertGreater(sum(map(len, case["blocks"])), 1400)
            self.assertLess(len(case["blocks"][0]), 100)  # heading is not first substantive piece
            self.assertEqual(len(case["checks"]), 5)
            if not case["quoted"]:
                self.assertFalse(set('«»“”"') & set("".join(case["blocks"])))


if __name__ == "__main__":
    unittest.main()
