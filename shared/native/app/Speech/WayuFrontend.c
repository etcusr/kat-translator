#include "WayuFrontend.h"
#if defined(OT_MACOS)
#include <Python.h>
#else
#include <Python/Python.h>
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mach-o/dyld.h>
#include <pthread.h>
static PyObject *frontend=NULL;
static int initialize_python(const char *bundle) {
    if(!Py_IsInitialized()){
        PyPreConfig pre;PyPreConfig_InitIsolatedConfig(&pre);pre.utf8_mode=1;
        if(PyStatus_Exception(Py_PreInitialize(&pre)))return 0;
        PyConfig cfg;PyConfig_InitIsolatedConfig(&cfg);
        cfg.install_signal_handlers=0;cfg.write_bytecode=0;cfg.site_import=0;
        cfg.module_search_paths_set=1;
        #if defined(OT_MACOS)
        const char *suffixes[]={"/python/lib/python3.11","/python/lib/python3.11/lib-dynload","/IndexPython","/WayuPython"};
        #else
        const char *suffixes[]={"/python/lib/python3.13","/python/lib/python3.13/lib-dynload","/WayuPython"};
        #endif
        PyStatus status=PyStatus_Ok();
        uint32_t size=0;_NSGetExecutablePath(NULL,&size);
        char *executable=malloc(size);
        if(!executable){PyConfig_Clear(&cfg);return 0;}
        if(_NSGetExecutablePath(executable,&size)!=0){free(executable);PyConfig_Clear(&cfg);return 0;}
        status=PyConfig_SetBytesString(&cfg,&cfg.executable,executable);free(executable);
        if(PyStatus_Exception(status)){PyConfig_Clear(&cfg);return 0;}
        for(int i=0;i<(int)(sizeof(suffixes)/sizeof(suffixes[0]));i++){
            char *path=malloc(strlen(bundle)+strlen(suffixes[i])+1);if(!path){PyConfig_Clear(&cfg);return 0;}
            strcpy(path,bundle);strcat(path,suffixes[i]);wchar_t *wide=Py_DecodeLocale(path,NULL);free(path);
            if(!wide){PyConfig_Clear(&cfg);return 0;}
            status=PyWideStringList_Append(&cfg.module_search_paths,wide);PyMem_RawFree(wide);
            if(PyStatus_Exception(status))break;
        }
        if(!PyStatus_Exception(status))status=Py_InitializeFromConfig(&cfg);
        PyConfig_Clear(&cfg);
        if(PyStatus_Exception(status)){fprintf(stderr,"Wayu Python initialization failed\n");return 0;}
        PyEval_SaveThread();
    }
    return 1;
}
int ot_wayu_python_init(const char *bundle) {
    static pthread_mutex_t initialization = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&initialization);
    int result=initialize_python(bundle);
    pthread_mutex_unlock(&initialization);
    return result;
}
static int initialize_frontend(const char *bundle) {
    if(frontend)return 1;
    if(!ot_wayu_python_init(bundle))return 0;
    PyGILState_STATE gil=PyGILState_Ensure();
    frontend=PyImport_ImportModule("wayu_frontend");if(!frontend)PyErr_Print();
    PyGILState_Release(gil);return frontend!=NULL;
}
int ot_wayu_frontend_init(const char *bundle) {
    static pthread_mutex_t initialization = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&initialization);
    int result=initialize_frontend(bundle);
    pthread_mutex_unlock(&initialization);
    return result;
}
int ot_wayu_frontend_tokens(const char *text,int64_t *tokens,int capacity) {
    if(!frontend||!text||!tokens)return -1;
    PyGILState_STATE gil=PyGILState_Ensure();int result=-1;
    PyObject *out=PyObject_CallMethod(frontend,"tokens","s",text);
    if(out && PyList_Check(out)){
        Py_ssize_t n=PyList_Size(out);
        if(n>capacity)result=-2;
        else {result=(int)n;for(int i=0;i<n;i++){tokens[i]=PyLong_AsLongLong(PyList_GetItem(out,i));if(PyErr_Occurred()){result=-1;break;}}}
    }
    if(PyErr_Occurred()){if(PyErr_ExceptionMatches(PyExc_OverflowError))result=-2;PyErr_Clear();}
    Py_XDECREF(out);PyGILState_Release(gil);return result;
}
int ot_wayu_frontend_style(const char *path,const char *voice,int length,float *style){
    if(!frontend||!style)return 0;
    PyGILState_STATE gil=PyGILState_Ensure();int valid=0;
    PyObject *out=PyObject_CallMethod(frontend,"style","ssi",path,voice,length);
    if(out && PyTuple_Check(out) && PyTuple_Size(out)==256){valid=1;for(int i=0;i<256;i++)style[i]=(float)PyFloat_AsDouble(PyTuple_GetItem(out,i));}
    if(PyErr_Occurred()){valid=0;PyErr_Print();}Py_XDECREF(out);PyGILState_Release(gil);return valid;
}
