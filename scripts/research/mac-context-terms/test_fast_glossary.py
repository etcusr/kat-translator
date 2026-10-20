import json
import unittest
from unittest.mock import patch
from fast_glossary import select_candidates,parse_targets,build_fast_glossary,morphology,supplement_nouns

class FastGlossaryTests(unittest.TestCase):
    def test_real_morphology_and_topic_without_manual_terms(self):
        blocks=['Заголовок','На выставке показали новые самолеты. Они летают далеко.',
                'Прошли испытания «самолетов». Показали образцы.',
                'Сегодня «самолеты» вернулись домой.']
        items,payload,method=select_candidates(blocks,morphology())
        self.assertEqual(method,'repeated_quoted_phrases')
        self.assertEqual(len(items),1)
        self.assertEqual(set(items[0]['aliases']),{'самолетов','самолеты'})
        self.assertIn('На выставке показали',payload)
        self.assertNotIn('Заголовок',payload)
        self.assertNotIn('aircraft',payload)

    def test_document_reset_and_fallback(self):
        m=morphology()
        first,_,_=select_candidates(['«Банки» открылись. «Банков» много.'],m)
        second,payload,method=select_candidates(['Машина едет. У машины колесо.'],m)
        self.assertTrue(first)
        self.assertEqual(method,'repeated_nouns')
        self.assertEqual(second[0]['source'],'Машина')
        self.assertNotIn('Банк',payload)

    def test_supplement_adds_repeated_common_nouns_without_duplicate_quotes(self):
        blocks=['«Самолеты» летят. Полет проходит над Москвой.',
                '«Самолетов» много. После полета Москва видна.']
        m=morphology();items,payload,_=select_candidates(blocks,m)
        expanded,payload=supplement_nouns(blocks,m,items,payload)
        self.assertEqual(len(expanded),2)
        self.assertEqual(expanded[1]['aliases'],['Полет','полета'])
        self.assertNotIn('Москва',[item['source'] for item in expanded])
        self.assertTrue(payload.endswith('术语2: Полет'))

    def test_targets_have_exact_count_and_no_explanations(self):
        items=[dict(source='банк',aliases=['банк'])]
        self.assertEqual(parse_targets('["bank"]',items)[0]['target'],'bank')
        for raw in ['[]','["bank","shore"]','Explanation: ["bank"]','[null]','["  "]','["bank\\nshore"]']:
            with self.subTest(raw=raw),self.assertRaises(ValueError):parse_targets(raw,items)

    def test_empty_candidates_skip_model_explicitly(self):
        class Engine:
            def count(self,*args):raise AssertionError('No model needed')
            def run(self,*args):raise AssertionError('No model needed')
        result=build_fast_glossary(Engine(),['Добрый день.'])
        self.assertEqual(result['terms'],[]);self.assertEqual(result['prompt_tokens'],0)

    def test_budget_error_never_calls_model(self):
        class Engine:
            def count(self,*args):return 1025
            def run(self,*args):raise AssertionError('Budget bypassed')
        with self.assertRaises(ValueError):build_fast_glossary(Engine(),['«Банки» открылись. «Банков» много.'])

    def test_runner_rebuilds_and_does_not_read_manual_glossary(self):
        from runner import Experiment
        class Case(dict):
            def get(self,key,*args):
                if key=='glossary':raise AssertionError('Manual seed accessed')
                return super().get(key,*args)
        class Engine:
            def count(self,*args):return 10
            def run(self,*args):return 0,'banks',0.1
        e=Experiment.__new__(Experiment);e.engine=Engine();e.count=len
        value=dict(terms=[],seconds=0.0,rejected_entries=0)
        with patch('fast_glossary.build_fast_glossary',return_value=value) as generate:
            for mode in ['fast_terms','focused_terms']:
                for _ in range(2):e.run(Case(blocks=['Банки открыты.']),mode)
            self.assertEqual(generate.call_count,4)
            self.assertTrue(generate.call_args.kwargs['include_nouns'])

if __name__=='__main__':unittest.main()
