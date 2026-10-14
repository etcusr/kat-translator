"""Extract Russian UI literals, including Swift interpolation, for the catalog audit."""
from pathlib import Path
import re,json

def string_end(s,start):
 i=start+1; chunks=[]; literal=''; args=[]
 while i<len(s):
  if s[i]=='"':chunks.append(literal);return i+1,chunks,args
  if s[i]=='\\':
   if s[i+1]=='(':
    chunks.append(literal);literal='';j=i+2;level=1
    while level:
     if s[j]=='"': j=string_end(s,j)[0];continue
     if s[j]=='(':level+=1
     if s[j]==')':level-=1
     j+=1
    args.append(s[i+2:j-1]);i=j;continue
   literal+=s[i:i+2];i+=2;continue
  literal+=s[i];i+=1
 raise ValueError(start)
def literals(s):
 i=0
 while i<len(s):
  if s.startswith('//',i):
   end=s.find('\n',i);i=len(s) if end<0 else end;continue
  if s.startswith('/*',i):
   end=s.find('*/',i+2);i=len(s) if end<0 else end+2;continue
  if s[i]=='"':
   end,chunks,args=string_end(s,i)
   if any(re.search('[А-Яа-яЁё]',part) for part in chunks):
    key='%@'.join(json.loads('"'+part+'"').replace('%','%%') for part in chunks)
    yield i,end,key,s[i:end],args
   i=end;continue
  i+=1
