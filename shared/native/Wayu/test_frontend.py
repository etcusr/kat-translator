import unittest
from wayu_frontend import phonemes, tokens
class FrontendTests(unittest.TestCase):
    def test_greeting_preserves_tones(self):
        self.assertEqual(phonemes('สวัสดีค่ะ สบายดีไหมคะ?'), 'sa˩wat˩diː→kʰa↘ sa˩baːj→diː→maj↓kʰa↗ ?')
    def test_numbers_are_spoken(self):
        self.assertEqual(phonemes('ราคา 250 บาท'), phonemes('ราคา สองร้อยห้าสิบ บาท'))
    def test_english_is_not_lost(self):
        self.assertIn('ɡɹˈæb', phonemes('เรียก Grab'))
    def test_unknown_word_fails_instead_of_dropping(self):
        with self.assertRaises(ValueError): phonemes('สวัสดี xyzqqzz')
    def test_bounds(self):
        with self.assertRaises(ValueError): tokens('x'*2001)
    def test_sentinels(self):
        ids=tokens('ขอบคุณครับ');self.assertEqual((ids[0],ids[-1]),(0,0));self.assertGreater(len(ids),5)
if __name__=='__main__': unittest.main()
