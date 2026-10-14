"""Exercise the real C/Python bridge: a failed request must not pin model objects."""
from pathlib import Path
import subprocess, sysconfig
root=Path(__file__).resolve().parents[2]
target=root/'.build/mac-mlx-release/error-lifetime';target.mkdir(parents=True,exist_ok=True)
py=Path('/opt/homebrew/opt/python@3.11/Frameworks/Python.framework/Versions/3.11')
resources=target/'resources';(resources/'python/lib').mkdir(parents=True,exist_ok=True)
stdlib=resources/'python/lib/python3.11'
if not stdlib.exists():stdlib.symlink_to(py/'lib/python3.11')
index=resources/'IndexPython';index.mkdir(exist_ok=True)
(index/'index_mlx.py').write_text('''import gc, weakref
refs=[]
class Payload: pass
class Engine:
 def __init__(self,path):
  self.model=Payload();refs.append(weakref.ref(self.model))
 def run(self,*args):
  held=self.model
  raise MemoryError('synthetic GPU allocation failure')
 def close(self):
  self.model=None;gc.collect()
def alive():
 gc.collect();return any(ref() is not None for ref in refs)
''')
(target/'probe.c').write_text('''#include <Python.h>
#include "MLXRuntime.h"
int main(int argc, char **argv) {
 void *engine=kat_mlx_load(argv[1],"fixture");if(!engine)return 10;
 void *flag=kat_mlx_flag_create();char output[64];double first;
 int result=kat_mlx_run(engine,"","hello","",flag,output,sizeof(output),&first);
 kat_mlx_flag_free(flag);kat_mlx_free(engine);
 if(result!=-1||output[0]!=0||first!=-1)return 11;
 PyGILState_STATE gil=PyGILState_Ensure();
 PyObject *m=PyImport_ImportModule("index_mlx");PyObject *alive=PyObject_CallMethod(m,"alive",NULL);
 int retained=PyObject_IsTrue(alive);Py_DECREF(alive);Py_DECREF(m);PyGILState_Release(gil);
 return retained?12:0;
}''')
source=root/'shared/native/app/Translation/MLXRuntime.c'
old=target/'before.c';old.write_text(source.read_text().replace('PyErr_PrintEx(0)','PyErr_PrintEx(1)').replace('"../Speech/WayuFrontend.h"','"WayuFrontend.h"'))
common=['xcrun','clang','-DOT_MACOS=1','-I'+str(py/'include/python3.11'),'-I'+str(source.parent),'-I'+str(root/'shared/native/app/Speech'),str(target/'probe.c'),str(root/'shared/native/app/Speech/WayuFrontend.c'),str(py/'Python')]
results={}
for label,cfile in [('before',old),('after',source)]:
 binary=target/label
 subprocess.run(common+[str(cfile),'-o',str(binary)],check=True,capture_output=True)
 run=subprocess.run([str(binary),str(resources)],capture_output=True,text=True)
 (target/(label+'.log')).write_text(run.stderr)
 results[label]=run.returncode
assert results=={'before':12,'after':0},results
print('PASS: old bridge retains failed-request model; corrected bridge releases it:',results)
