import unittest
from voice_catalog_capabilities import update_capabilities
class CapabilityRegeneration(unittest.TestCase):
 def test_removed_voice_no_longer_advertises_speech(self):
  source='.init(id: "hy", hasVoice: true)\n.init(id: "ru", hasVoice: true)'
  self.assertEqual(update_capabilities(source,{'hy','ru'},[]),source.replace('"hy", hasVoice: true','"hy", hasVoice: false'))
 def test_shared_replacement_and_unrelated_flags_survive(self):
  source='.init(id: "ms", hasVoice: true)\n.init(id: "az", hasVoice: false)\n.init(id: "xx", hasVoice: true)'
  voice={'language':'ms','languageAliases':{'ms':'ms','az':'az'}}
  self.assertEqual(update_capabilities(source,{'ms','az'},[voice]),source.replace('"az", hasVoice: false','"az", hasVoice: true'))
if __name__=='__main__':unittest.main()
