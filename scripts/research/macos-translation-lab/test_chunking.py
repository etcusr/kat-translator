"""Lossless coverage and bounded prompts for experimental translation chunks."""
import unittest
from chunking import plan, context_input, extract_current, translate, START, END

class FakeTokenizer:
    def encode(self,text,add_special_tokens=False): return list(text)

class FailedBoundaryEngine:
    tokenizer=FakeTokenizer()
    def count(self,prefix,text,suffix): return len(prefix+text+suffix)
    def run(self,*args): return 0,'Translation without boundary markers',.01

class ChunkingTests(unittest.TestCase):
    def test_lossless_unicode_and_dialogue(self):
        text='Анна: Я приехала вчера.\nИгорь: Цена 3.14 евро?\n\nДа!  Телефон 📱 остался дома. '
        chunks=plan(text,len,24)
        self.assertEqual(''.join(c['raw'] for c in chunks),text)
        self.assertGreater(len(chunks),1)
        self.assertTrue(all(len(c['raw'])<=24 for c in chunks))
        self.assertEqual([c['start'] for c in chunks],[0]+[c['end'] for c in chunks[:-1]])
    def test_single_huge_sentence_and_word(self):
        for text in ['word '*300,'界'*500]:
            chunks=plan(text,len,31)
            self.assertEqual(''.join(c['raw'] for c in chunks),text)
            self.assertTrue(all(0<len(c['raw'])<=31 for c in chunks))
    def test_paragraph_boundary(self):
        chunks=plan('One sentence.\n\nTwo sentences. Fine.',len,20)
        self.assertEqual(chunks[0]['separator'],'\n\n')
    def test_context_is_source_only_and_bounded(self):
        before='Anna is a woman. '*100
        text=before+'CURRENT.'+' After.'*100
        chunk={'start':len(before),'end':len(before)+8}
        marked=context_input(text,chunk,len)
        self.assertLess(len(marked),230)
        self.assertEqual(extract_current(marked),'CURRENT.')
    def test_reject_missing_duplicate_or_reordered_markers(self):
        self.assertEqual(extract_current('before '+START+' translation '+END+' after'),'translation')
        for text in ['translation',END+START,START+END,START+'one'+START+'two'+END]:
            with self.assertRaises(ValueError):extract_current(text)
    def test_blank_and_invalid_limit(self):
        self.assertEqual(plan('',len,10),[])
        with self.assertRaises(ValueError):plan('abc',len,0)
    def test_bad_model_boundaries_are_not_a_successful_translation(self):
        events=[]
        result=translate(FailedBoundaryEngine(),'A sentence. '*30,'ru','',
                         progress=events.append)
        self.assertEqual(result['code'],-4)
        self.assertEqual(result['output'],'')
        self.assertFalse(result['complete'])
        self.assertEqual(events,[])
    def test_reserved_source_markers_rejected(self):
        with self.assertRaises(ValueError):
            translate(FailedBoundaryEngine(),'A sentence. '*30+START,'ru','')

if __name__=='__main__':unittest.main()
