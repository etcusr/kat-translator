"""Production glossary selection, isolation, cancellation and token accounting."""
from pathlib import Path
import importlib.util
import sys
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'shared/native/IndexMLX'))
sys.path.insert(0, str(ROOT / 'Dependencies/build/mac-glossary/libraries'))
import index_glossary as glossary
import index_mlx

class GlossaryTests(unittest.TestCase):
    def engine(self): return index_mlx.Engine.__new__(index_mlx.Engine)
    def test_default_disabled_does_not_load_glossary_or_generate(self):
        engine = self.engine()
        with patch('index_glossary.build_fast_glossary', side_effect=AssertionError('Disabled')):
            self.assertEqual(engine.prepare_glossary('', '', lambda: False), 0)
        self.assertEqual(engine._prefix('prefix', 'текст'), 'prefix')

    def test_reuses_only_same_document_and_clear_drops_old_terms(self):
        engine = self.engine()
        terms = [dict(source='дрон', aliases=['дрон', 'дроны'], target='drone')]
        with patch('index_glossary.build_fast_glossary', return_value=dict(terms=terms)) as build:
            for identity in ['one', 'one', 'two']:
                self.assertEqual(engine.prepare_glossary('Дроны летают.', identity, lambda: False), 0)
            self.assertEqual(build.call_count, 2)
        self.assertIn('drone', engine._prefix('prefix', 'Дроны летают.'))
        self.assertEqual(engine._prefix('prefix', 'Аэродромы открыты.'), 'prefix')
        self.assertEqual(engine._prefix('', 'Дроны летают.'), '')
        engine.prepare_glossary('', '', lambda: False)
        self.assertEqual(engine._prefix('prefix', 'Дроны летают.'), 'prefix')

    def test_cancelled_or_invalid_preparation_never_publishes_terms(self):
        engine = self.engine()
        self.assertEqual(engine.prepare_glossary('Текст', 'one', lambda: True), 2)
        for failure in [glossary.GlossaryCancelled(), ValueError('Invalid JSON')]:
            engine._glossary = ['old']; engine._glossary_identity = 'old'
            with patch('index_glossary.build_fast_glossary', side_effect=failure):
                if isinstance(failure, ValueError):
                    with self.assertRaises(ValueError): engine.prepare_glossary('Текст', 'new', lambda: False)
                else: self.assertEqual(engine.prepare_glossary('Текст', 'new', lambda: False), 2)
            self.assertEqual(engine._glossary, [])
            self.assertIsNone(engine._glossary_identity)

    def test_actual_morphology_matches_frozen_experiment(self):
        sys.path.insert(0, str(ROOT / 'scripts/research/mac-context-terms'))
        import fast_glossary as lab
        blocks=['Система охлаждения контролирует расход. Датчики проверяют систему.',
                'При снижении расхода датчик отключает насос. Насос защищает систему охлаждения.']
        morph=glossary.morphology()
        new=glossary.select_candidates(blocks,morph)
        old=lab.select_candidates(blocks,morph)
        self.assertEqual(new,old)
        self.assertEqual(glossary.supplement_nouns(blocks,morph,*new[:2]),lab.supplement_nouns(blocks,morph,*old[:2]))

    def test_cpu_selection_is_cancellable(self):
        with self.assertRaises(glossary.GlossaryCancelled):
            glossary.select_candidates(['Машины едут. Машина остановилась.'],glossary.morphology(),cancelled=lambda:True)

    def test_no_candidates_skip_model_and_generation_uses_cancel_callback(self):
        class Engine:
            def count(self,*args): return 30
            def run(self,*args):
                self.callback=args[3]
                return 2,'',-1
        engine=Engine()
        self.assertEqual(glossary.build_fast_glossary(engine,['Добрый день.'])['terms'],[])
        callback=lambda:False
        with self.assertRaises(glossary.GlossaryCancelled):
            glossary.build_fast_glossary(engine,['Банки открыты. В банках работают люди.'],cancelled=callback)
        self.assertIs(engine.callback,callback)

    def test_budget_and_invalid_json_fail_explicitly(self):
        engine=types.SimpleNamespace(count=lambda *a:1025,run=lambda *a: self.fail('Should not generate'))
        with self.assertRaises(ValueError): glossary.build_fast_glossary(engine,['Банки открыты. Банки работают.'])
        items=[dict(source='банк',aliases=['банк'])]
        for raw in ['[]','[null]','["bank","shore"]','not JSON']:
            with self.subTest(raw=raw),self.assertRaises(ValueError): glossary.parse_targets(raw,items)

    def test_token_preflight_and_generation_use_identical_augmented_prompt(self):
        engine=self.engine(); seen=[]
        engine._glossary=[dict(source='насос',aliases=['насос'],target='pump')]
        engine.tokenizer=types.SimpleNamespace(encode=lambda text,**kw: seen.append(text) or [1],eos_token_ids={0},decode=lambda _: 'pump')
        engine.model=None; engine.mx=types.SimpleNamespace(synchronize=lambda:None)
        class Generator:
            def __init__(self,*a,**kw): pass
            def insert(self,*a): pass
            def next(self): return None,[types.SimpleNamespace(token=1,finish_reason='stop')]
            def close(self): pass
        engine.count('prefix','Насос включен.','suffix')
        with patch.dict(sys.modules,{'mlx_lm.generate':types.SimpleNamespace(BatchGenerator=Generator)}):
            self.assertEqual(engine.run('prefix','Насос включен.','suffix',lambda:False)[0],0)
        self.assertEqual(seen[0],seen[1]); self.assertIn('насос → pump',seen[0])

if __name__=='__main__': unittest.main()
