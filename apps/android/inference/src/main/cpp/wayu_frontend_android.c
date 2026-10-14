// Android embedding adapter. Linguistic implementation is the same bundled
// shared/native/Wayu/wayu_frontend.py and pinned prepared TLTK/PyThaiNLP data.
#include <Python.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <android/log.h>
static PyObject *frontend=NULL;
static _Thread_local char init_error[2048];
const char *kat_wayu_error(void){return init_error[0]?init_error:"Unknown Python initialization error";}
static void status_error(PyStatus status){
 snprintf(init_error,sizeof(init_error),"%s: %s",status.func?status.func:"Python",status.err_msg?status.err_msg:"initialization failed");
 __android_log_write(ANDROID_LOG_ERROR,"kat_wayu",init_error);
}
static void import_error(void){
 PyObject *type=NULL,*value=NULL,*traceback=NULL;PyErr_Fetch(&type,&value,&traceback);PyErr_NormalizeException(&type,&value,&traceback);
 PyObject *description=value?PyObject_Str(value):NULL;const char *message=description?PyUnicode_AsUTF8(description):NULL;
 snprintf(init_error,sizeof(init_error),"wayu_frontend import: %s",message?message:"unknown Python exception");
 __android_log_write(ANDROID_LOG_ERROR,"kat_wayu",init_error);
 Py_XDECREF(description);PyErr_Restore(type,value,traceback);PyErr_Print();
}
int kat_wayu_init(const char *root) {
 init_error[0]=0;
 static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;pthread_mutex_lock(&lock);
 if(frontend){pthread_mutex_unlock(&lock);return 1;}
 if(!Py_IsInitialized()){
  PyPreConfig pre;PyPreConfig_InitIsolatedConfig(&pre);pre.utf8_mode=1;
  PyStatus status=Py_PreInitialize(&pre);
  if(PyStatus_Exception(status)){status_error(status);pthread_mutex_unlock(&lock);return 0;}
  PyConfig config;PyConfig_InitIsolatedConfig(&config);config.install_signal_handlers=0;config.write_bytecode=0;config.site_import=0;config.module_search_paths_set=1;
  status=PyConfig_SetBytesString(&config,&config.home,root);
  const char *suffixes[]={"/lib/python3.14","/lib/python3.14/lib-dynload","/WayuPython"};
  for(int i=0;i<3&&!PyStatus_Exception(status);i++){
   size_t n=strlen(root)+strlen(suffixes[i])+1;char *path=malloc(n);if(!path){PyConfig_Clear(&config);pthread_mutex_unlock(&lock);return 0;}
   snprintf(path,n,"%s%s",root,suffixes[i]);wchar_t *wide=Py_DecodeLocale(path,NULL);free(path);
   if(!wide){PyConfig_Clear(&config);pthread_mutex_unlock(&lock);return 0;}
   status=PyWideStringList_Append(&config.module_search_paths,wide);PyMem_RawFree(wide);
  }
  if(!PyStatus_Exception(status))status=Py_InitializeFromConfig(&config);
  if(PyStatus_Exception(status))status_error(status);
  PyConfig_Clear(&config);if(PyStatus_Exception(status)){pthread_mutex_unlock(&lock);return 0;}PyEval_SaveThread();
 }
 PyGILState_STATE gil=PyGILState_Ensure();frontend=PyImport_ImportModule("wayu_frontend");if(PyErr_Occurred())import_error();PyGILState_Release(gil);
 pthread_mutex_unlock(&lock);return frontend!=NULL;
}
int kat_wayu_tokens(const char *text,int64_t *tokens,int capacity){
 if(!frontend)return -1;PyGILState_STATE gil=PyGILState_Ensure();int result=-1;
 PyObject *out=PyObject_CallMethod(frontend,"tokens","s",text);
 if(out&&PyList_Check(out)){Py_ssize_t n=PyList_Size(out);if(n>capacity)result=-2;else{result=(int)n;for(int i=0;i<n;i++){tokens[i]=PyLong_AsLongLong(PyList_GetItem(out,i));if(PyErr_Occurred()){result=-1;break;}}}}
 if(PyErr_Occurred()){if(PyErr_ExceptionMatches(PyExc_OverflowError))result=-2;PyErr_Clear();}Py_XDECREF(out);PyGILState_Release(gil);return result;
}
int kat_wayu_style(const char *path,const char *voice,int length,float *style){
 if(!frontend)return 0;PyGILState_STATE gil=PyGILState_Ensure();int valid=0;PyObject *out=PyObject_CallMethod(frontend,"style","ssi",path,voice,length);
 if(out&&PyTuple_Check(out)&&PyTuple_Size(out)==256){valid=1;for(int i=0;i<256;i++)style[i]=(float)PyFloat_AsDouble(PyTuple_GetItem(out,i));}
 if(PyErr_Occurred()){valid=0;PyErr_Clear();}Py_XDECREF(out);PyGILState_Release(gil);return valid;
}
