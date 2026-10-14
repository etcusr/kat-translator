import importlib.util
from pathlib import Path
import unittest
spec=importlib.util.spec_from_file_location('article',Path(__file__).resolve().parents[1]/'android/index-article-probe.py')
article=importlib.util.module_from_spec(spec);spec.loader.exec_module(article)

class ArticleSegments(unittest.TestCase):
    def test_preserves_all_characters(self):
        text='Первое предложение. Второе!\n\nТретье «слово». Последнее 😀'
        parts=article.segments(text)
        self.assertEqual(''.join(parts),text)
        self.assertEqual(len(parts),4)
    def test_decimal_is_not_sentence_boundary(self):
        self.assertEqual(article.segments('Стоимость 9.12 евро.'),['Стоимость 9.12 евро.'])
    def test_quoted_sentence_boundary(self):
        self.assertEqual(len(article.segments('Он сказал: "Стоп." Затем ушёл.')),2)
    def test_empty_and_single(self):
        self.assertEqual(article.segments(''),[])
        self.assertEqual(article.segments('😀'),['😀'])
if __name__=='__main__':unittest.main()
