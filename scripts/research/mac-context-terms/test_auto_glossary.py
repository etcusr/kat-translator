import json
import unittest
from auto_glossary import validate_glossary, build_glossary

class GlossaryTests(unittest.TestCase):
    def test_keeps_attested_forms_and_rejects_invented_sources(self):
        rows=json.dumps([{'source':'самолеты','target':'aircraft'}, {'source':'отсутствует','target':'absent'}],ensure_ascii=False)
        terms, rejected=validate_glossary(rows,'Самолеты прилетели. Обломки самолетов найдены.')
        self.assertEqual(len(terms),1)
        self.assertEqual(set(terms[0]['aliases']),{'Самолеты','самолетов'})
        self.assertEqual(rejected,1)

    def test_rejects_substrings_inside_unrelated_words(self):
        terms,rejected=validate_glossary('[{"source":"кот","target":"cat"}]','Котел работает.')
        self.assertEqual(terms,[]);self.assertEqual(rejected,1)

    def test_no_approximate_names_or_transliterated_sources(self):
        terms,rejected=validate_glossary('[{"source":"ОЗОН","target":"OZON"}]','Склад OZON открыт.')
        self.assertEqual(terms,[]);self.assertEqual(rejected,1)

    def test_rejects_explanations_and_invalid_shape(self):
        for raw in ['Here is the list: []','{}','[{"source":3,"target":"x"}]','[{"source":"word","target":""}]']:
            with self.subTest(raw=raw):
                with self.assertRaises(ValueError): validate_glossary(raw,'word')

    def test_casefold_and_yo_variants(self):
        terms,_=validate_glossary('[{"source":"самолёты","target":"aircraft"}]','Самолеты и самолётов много.')
        self.assertEqual(len(terms),1)
        self.assertIn('Самолеты',terms[0]['aliases'])
        self.assertIn('самолётов',terms[0]['aliases'])

    def test_conflicting_duplicate_not_silently_applied(self):
        with self.assertRaises(ValueError):
            validate_glossary('[{"source":"банк","target":"bank"},{"source":"банк","target":"shore"}]','банк')

    def test_builder_uses_source_only_and_fails_on_native_limit(self):
        class Engine:
            def count(self,*args): return 1025
            def run(self,*args): raise AssertionError('No inference above limit')
        with self.assertRaises(ValueError): build_glossary(Engine(),['text'])

    def test_builder_has_no_manual_seed(self):
        class Engine:
            def count(self,*args): return 10
            def run(self,prefix,text,suffix,cancel):
                self.text=text
                return 0,'[{"source":"слово","target":"word"}]',0.1
        engine=Engine();result=build_glossary(engine,['слово'])
        self.assertEqual(engine.text,'слово')
        self.assertEqual(result['terms'][0]['target'],'word')

    def test_auto_mode_ignores_manual_dictionary_and_rebuilds_each_document(self):
        from runner import Experiment
        class Case(dict):
            def get(self,key,*args):
                if key=='glossary': raise AssertionError('Manual dictionary accessed')
                return super().get(key,*args)
        class Engine:
            def __init__(self): self.extractions=0
            def count(self,*args): return 10
            def run(self,prefix,text,suffix,cancel):
                if 'JSON' in prefix:
                    self.extractions+=1
                    return 0,'[{"source":"слово","target":"word"}]',0.1
                return 0,'word',0.1
        runner=Experiment.__new__(Experiment);runner.engine=Engine();runner.count=len
        for _ in range(2):
            result=runner.run(Case(blocks=['слово']),'auto_terms')
            self.assertGreaterEqual(result['seconds'],result['glossary_seconds'])
        self.assertEqual(runner.engine.extractions,2)

    def test_automatic_short_alias_matches_whole_words_only(self):
        from runner import prompt
        terms,_=validate_glossary('[{"source":"кот","target":"cat"}]','кот')
        self.assertNotIn('кот → cat',prompt('terms','котел',None,terms)[0])

if __name__=='__main__': unittest.main()
