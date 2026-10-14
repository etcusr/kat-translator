import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('mtp_probe',Path(__file__).resolve().parents[1]/'android'/'mtp-probe.py')
probe=importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class MtpProbe(unittest.TestCase):
    def response(self):
        return {'content':'Hello! The meeting is tomorrow at 15:30.', 'tokens':list(probe.REFERENCE_TOKENS),
                'timings':{'cache_n':0,'prompt_n':46}, 'truncated':False}

    def test_baseline_is_valid(self):
        probe.validate_response(self.response())

    def test_identical_text_does_not_hide_token_difference(self):
        result=self.response();result['tokens'][-1]=0
        with self.assertRaisesRegex(AssertionError,'Token stream'):
            probe.validate_response(result)

    def test_cached_or_different_prompt_cannot_be_timed_as_full_prefill(self):
        for key,value in [('cache_n',45),('prompt_n',47)]:
            result=self.response();result['timings'][key]=value
            with self.assertRaisesRegex(AssertionError,'Prompt'):
                probe.validate_response(result)

    def test_truncated_generation_is_rejected(self):
        result=self.response();result['truncated']=True
        with self.assertRaisesRegex(AssertionError,'finish normally'):
            probe.validate_response(result)

    def test_corpus_facts_and_eos_are_required(self):
        case=probe.FIXTURES['changed-text-ru-en']
        result={'content':'No, the meeting is the day after tomorrow at 09:15, not tomorrow.',
                'tokens':[1,248046],'timings':{'cache_n':0,'prompt_n':49},'truncated':False}
        probe.validate_response(result,case)
        result['content']='The meeting is tomorrow at 09:15.'
        with self.assertRaisesRegex(AssertionError,'Missing translation fact'):
            probe.validate_response(result,case)
        result['tokens']=[1]
        with self.assertRaisesRegex(AssertionError,'Missing EOS'):
            probe.validate_response(result,case)

    def test_apple_comparison_requires_full_prompt_and_negation(self):
        case=probe.FIXTURES['iphone-en01']
        result={'content':'В образцах Бенну не обнаружили дезоксирибозу.',
                'tokens':[1,248046],'timings':{'cache_n':0,'prompt_n':49},'truncated':False}
        probe.validate_response(result,case)
        result['timings']['cache_n']=30
        with self.assertRaisesRegex(AssertionError,'Prompt'):
            probe.validate_response(result,case)
        result['timings']['cache_n']=0
        result['content']='В образцах Бенну обнаружили дезоксирибозу.'
        with self.assertRaisesRegex(AssertionError,'Missing translation fact'):
            probe.validate_response(result,case)
