import ast,json,hashlib
from pathlib import Path
from types import SimpleNamespace
from jinja2 import Environment
p=Path('docs/benchmarks/model-search-round2');s=Path('scripts/validation/candidate-screening.py');tree=ast.parse(s.read_text());ns={}
for n in tree.body:
 if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='names' for t in n.targets):ns['names']=ast.literal_eval(n.value)
 if isinstance(n,ast.FunctionDef) and n.name=='prompt':exec(compile(ast.Module(body=[n],type_ignores=[]),str(s),'exec'),ns)
rows=json.loads((p/'screening.json').read_text());results={}
for family,file in [('qwen35','qwen-chat_template.jinja'),('mil','mil4-chat_template.jinja'),('mil','mil12-chat_template.jinja')]:
 template=Environment().from_string((p/'sources'/file).read_text());ns['a']=SimpleNamespace(family=family)
 for r in rows:
  pre,suf=ns['prompt'](r['source'],r['target']);actual=pre+r['text']+suf
  if family=='qwen35': content='Translate the following text from '+ns['names'][r['source']]+' into '+ns['names'][r['target']]+'. Output only the translation, without explanations.\n\n'+r['text']
  else: content='Translate this from '+ns['names'][r['source']]+' to '+ns['names'][r['target']]+':\n'+ns['names'][r['source']]+': '+r['text']+'\n'+ns['names'][r['target']]+':'
  rendered=template.render(messages=[dict(role='user',content=content)],add_generation_prompt=True,enable_thinking=False)
  assert rendered==actual,(file,r['id'],repr(rendered),repr(actual))
 results[file]=dict(count=len(rows),exact_match=True,sha256=hashlib.sha256((p/'sources'/file).read_bytes()).hexdigest())
(p/'prompt-validation.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results,indent=2))
