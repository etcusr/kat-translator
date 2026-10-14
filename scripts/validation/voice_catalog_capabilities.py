"""Keep generated capability flags consistent with routes in the final catalog."""
import re
BUILTIN_VOICE_CODES=set('ru en zh th ban es fr de it pt ja ko ar tr hi nl pl ro sv vi id uk cs el da hu fi sk bg lt sl et lv hr'.split())
def covered_codes(voices):
 return BUILTIN_VOICE_CODES | {code for voice in voices for code in [voice['language'],*voice.get('languageAliases',{})]}
def update_capabilities(source,scope,voices):
 active=covered_codes(voices)
 for code in scope:
  value='true' if code in active else 'false'
  source=re.sub(r'(\.init\(id: "'+re.escape(code)+r'",[^\n]*hasVoice: )(true|false)',lambda m:m.group(1)+value,source)
 return source
