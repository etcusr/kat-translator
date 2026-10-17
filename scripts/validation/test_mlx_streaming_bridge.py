"""Compile the real MLX C bridge and exercise callback lifetime without model weights."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PYTHON = Path('/opt/homebrew/opt/python@3.11/Frameworks/Python.framework/Versions/3.11')


@unittest.skipUnless((PYTHON / 'Python').exists(), 'Local embedded Python 3.11 required')
class BridgeTests(unittest.TestCase):
    def test_stream_cancel_error_and_retained_callbacks(self):
        with tempfile.TemporaryDirectory(prefix='kat-mlx-stream-') as folder:
            work = Path(folder)
            (work / 'index_mlx.py').write_text('''
saved = []
class Engine:
 def __init__(self, path): pass
 def close(self): pass
 def run(self, prefix, text, suffix, cancelled, partial=None):
  saved.append((cancelled, partial))
  if partial:
   partial('Hello.')
   partial('Hello. World.')
  if text == 'error': raise RuntimeError('synthetic failure')
  if cancelled(): return (2, '', -1.)
  return (0, 'Hello. World.', 0.01)
def invoke_saved():
 for cancelled, partial in saved:
  assert cancelled(), 'expired request must be cancelled'
  if partial: partial('stale')
 saved.clear()
''')
            (work / 'probe.c').write_text(r'''
#include <Python.h>
#include <string.h>
#include "MLXRuntime.h"
static int reports, cancel_on_report;
static void *active_flag;
int ot_wayu_python_init(const char *path) {
 Py_Initialize();
 PyObject *p=PyUnicode_FromString(path);
 PyList_Insert(PySys_GetObject("path"),0,p);Py_DECREF(p);
 PyEval_SaveThread();return 1;
}
static void report(const char *text, void *user) {
 if(user != &reports || strcmp(text,"stale")==0) reports=1000;
 else reports++;
 if(cancel_on_report) kat_mlx_flag_cancel(active_flag);
}
static int saved(void) {
 PyGILState_STATE gil=PyGILState_Ensure();
 PyObject *m=PyImport_ImportModule("index_mlx");
 PyObject *result=PyObject_CallMethod(m,"invoke_saved",NULL);
 int ok=result!=NULL;if(!ok)PyErr_PrintEx(0);
 Py_XDECREF(result);Py_DECREF(m);PyGILState_Release(gil);return ok;
}
int main(int argc,char **argv) {
 void *engine=kat_mlx_load(argv[1],"fixture");if(!engine)return 10;
 char out[64];double first;
 active_flag=kat_mlx_flag_create();
 int result=kat_mlx_run_stream(engine,"","ok","",active_flag,out,sizeof(out),&first,report,&reports);
 kat_mlx_flag_free(active_flag);
 if(result!=0||reports!=2||strcmp(out,"Hello. World.")||first<0)return 11;
 if(!saved()||reports!=2)return 12;
 reports=0;cancel_on_report=1;active_flag=kat_mlx_flag_create();
 result=kat_mlx_run_stream(engine,"","ok","",active_flag,out,sizeof(out),&first,report,&reports);
 kat_mlx_flag_free(active_flag);
 if(result!=2||reports!=1||out[0]||first!=-1||!saved()||reports!=1)return 13;
 reports=0;cancel_on_report=0;active_flag=kat_mlx_flag_create();
 result=kat_mlx_run_stream(engine,"","error","",active_flag,out,sizeof(out),&first,report,&reports);
 kat_mlx_flag_free(active_flag);
 if(result!=-1||reports!=2||out[0]||first!=-1||!saved()||reports!=2)return 14;
 reports=0;active_flag=kat_mlx_flag_create();kat_mlx_flag_cancel(active_flag);
 result=kat_mlx_run_stream(engine,"","ok","",active_flag,out,sizeof(out),&first,report,&reports);
 kat_mlx_flag_free(active_flag);
 if(result!=2||reports||out[0]||first!=-1)return 15;
 active_flag=kat_mlx_flag_create();
 result=kat_mlx_run(engine,"","ok","",active_flag,out,sizeof(out),&first);
 kat_mlx_flag_free(active_flag);kat_mlx_free(engine);
 if(result!=0||strcmp(out,"Hello. World.")||!saved())return 16;
 return 0;
}
''')
            source = ROOT / 'shared/native/app/Translation/MLXRuntime.c'
            binary = work / 'probe'
            compile_result = subprocess.run(['xcrun', 'clang', '-DOT_MACOS=1',
                '-I' + str(PYTHON / 'include/python3.11'), '-I' + str(source.parent),
                str(work / 'probe.c'), str(source), str(PYTHON / 'Python'), '-o', str(binary)],
                capture_output=True, text=True)
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            result = subprocess.run([str(binary), str(work)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)

if __name__ == '__main__': unittest.main()
