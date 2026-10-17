"""Exercise partial delivery with the real Engine loop and deterministic tokens."""
import importlib.util
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('index_mlx_stream_test', ROOT / 'shared/native/IndexMLX/index_mlx.py')
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class StreamingTests(unittest.TestCase):
    def setUp(self):
        self.events = []
        events = self.events
        class Generator:
            def __init__(self, *args, **kwargs):
                self.index = 0
            def insert(self, _): pass
            def next(self):
                self.index += 1
                events.append(('step', self.index))
                return None, [types.SimpleNamespace(token=self.index, finish_reason='stop' if self.index == 3 else None)]
            def close(self): events.append(('close',))
        self.engine = runtime.Engine.__new__(runtime.Engine)
        self.engine.model = object()
        self.engine.mx = types.SimpleNamespace(synchronize=lambda: None)
        self.engine.tokenizer = types.SimpleNamespace(
            encode=lambda *a, **k: [1], eos_token_ids={3},
            decode=lambda tokens: {0: '', 1: 'Hello.', 2: 'Hello. World.'}[len(tokens)])
        self.patch = patch.dict(sys.modules, {'mlx_lm.generate': types.SimpleNamespace(BatchGenerator=Generator)})
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def test_partial_precedes_next_generation_and_final_matches_plain_run(self):
        plain = self.engine.run('', 'source', '', lambda: False)
        self.events.clear()
        result = self.engine.run('', 'source', '', lambda: False,
                                 lambda text: self.events.append(('partial', text)))
        self.assertEqual(result[:2], plain[:2])
        self.assertEqual([e for e in self.events if e[0] == 'partial'],
                         [('partial', 'Hello.'), ('partial', 'Hello. World.')])
        self.assertLess(self.events.index(('partial', 'Hello.')), self.events.index(('step', 2)))
        self.assertEqual(self.events[-1], ('close',))

    def test_cancel_from_partial_stops_generation_and_reuse_has_no_old_text(self):
        cancelled = False
        def partial(text):
            nonlocal cancelled
            cancelled = True
            self.events.append(('partial', text))
        self.assertEqual(self.engine.run('', 'source', '', lambda: cancelled, partial), (2, '', -1.))
        self.assertNotIn(('step', 2), self.events)
        self.assertEqual(self.events[-1], ('close',))
        fresh = []
        result = self.engine.run('', 'source', '', lambda: False, fresh.append)
        self.assertEqual(result[:2], (0, 'Hello. World.'))
        self.assertEqual(fresh, ['Hello.', 'Hello. World.'])

    def test_callback_error_closes_generator_and_allows_reuse(self):
        def fail(_): raise RuntimeError('synthetic callback error')
        with self.assertRaisesRegex(RuntimeError, 'synthetic callback error'):
            self.engine.run('', 'source', '', lambda: False, fail)
        self.assertEqual(self.events[-1], ('close',))
        self.assertEqual(self.engine.run('', 'source', '', lambda: False)[:2], (0, 'Hello. World.'))

    def test_partial_does_not_publish_incomplete_unicode(self):
        self.engine.tokenizer.decode = lambda tokens: 'Hello. �' if len(tokens) == 1 else 'Hello. Я.'
        partials = []
        result = self.engine.run('', 'source', '', lambda: False, partials.append)
        self.assertEqual(partials, ['Hello. Я.'])
        self.assertEqual(result[:2], (0, 'Hello. Я.'))

if __name__ == '__main__': unittest.main()
