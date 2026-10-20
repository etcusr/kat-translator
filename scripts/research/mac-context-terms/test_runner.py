import unittest
from runner import BASE, SUFFIX, Experiment, plan, prompt

class ProbeTests(unittest.TestCase):
    def test_chunk_coverage_and_budget(self):
        for text in ['First sentence. Second sentence!\n\nThird one.','Привет, мир! '+ 'длинный текст '*50, '漢字かな'*60]:
            pieces=plan(text,len,48)
            self.assertEqual(''.join(pieces),text)
            self.assertTrue(all(0<len(piece)<=48 for piece in pieces))

    def test_context_has_one_previous_pair_and_no_target_in_current_source(self):
        prefix,text,suffix=prompt('context','Current sentence.',('Previous sentence.','Предыдущее предложение.'),[])
        self.assertEqual(text,'Current sentence.')
        self.assertEqual(suffix,SUFFIX)
        self.assertEqual(prefix,BASE+'Previous sentence.'+SUFFIX+'Предыдущее предложение.<|im_end|>\n'+BASE)

    def test_terms_only_does_not_carry_previous_turn(self):
        terms=[dict(source='bank',aliases=['bank'],target='берег'),dict(source='hotel',aliases=['hotel'],target='отель')]
        prefix,_,_=prompt('terms','A river BANK.',('old-source','old-target'),terms)
        self.assertIn('bank → берег',prefix)
        self.assertNotIn('hotel →',prefix)
        self.assertNotIn('old-source',prefix)
        self.assertNotIn('old-target',prefix)

    def test_plain_prompt_is_production_prompt(self):
        self.assertEqual(prompt('plain','new',('old','previous'),[]),(BASE,'new',SUFFIX))

    def test_history_resets_between_documents(self):
        class Engine:
            def __init__(self): self.requests=[]
            def count(self,*parts): return sum(map(len,parts))
            def run(self,prefix,text,suffix,cancel):
                self.requests.append((prefix,text,suffix)); return 0,'translated '+text,0.01
        runner=Experiment.__new__(Experiment);runner.engine=Engine();runner.count=len
        case={'blocks':['Heading','Body sentence.']}
        for _ in range(2): runner.run(case,'context')
        self.assertEqual(runner.engine.requests[0],runner.engine.requests[2])
        self.assertNotIn('Body sentence.',runner.engine.requests[2][0])
        self.assertIn('translated Heading',runner.engine.requests[1][0])

if __name__=='__main__': unittest.main()
