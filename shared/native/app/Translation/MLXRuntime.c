#if defined(OT_MACOS)
#include "MLXRuntime.h"
#include "../Speech/WayuFrontend.h"
#include <Python.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

typedef struct { atomic_bool cancelled; } Flag;
void *kat_mlx_flag_create(void) { Flag *f = calloc(1, sizeof(Flag)); if(f) atomic_init(&f->cancelled, false); return f; }
void kat_mlx_flag_cancel(void *f) { if(f) atomic_store(&((Flag *)f)->cancelled, true); }
void kat_mlx_flag_free(void *f) { free(f); }
static int cancelled(void *f) { return f && atomic_load(&((Flag *)f)->cancelled); }
// Python may retain a callback in an exception or in user code. Its capsule owns
// this state, and the GIL protects invalidation before the synchronous run ends.
typedef struct { void *flag; kat_mlx_partial_callback partial; void *user; } Request;
static void release_request(PyObject *capsule) {
    free(PyCapsule_GetPointer(capsule, "kat.index.request"));
}
static PyObject *is_cancelled(PyObject *self, PyObject *args) {
    (void)args;
    Request *request = PyCapsule_GetPointer(self, "kat.index.request");
    if(!request) return NULL;
    return PyBool_FromLong(!request->flag || cancelled(request->flag));
}
static PyObject *report_partial(PyObject *self, PyObject *value) {
    Request *request = PyCapsule_GetPointer(self, "kat.index.request");
    if(!request) return NULL;
    if(request->flag && request->partial && !cancelled(request->flag)) {
        const char *text = PyUnicode_AsUTF8(value);
        if(!text) return NULL;
        request->partial(text, request->user);
    }
    Py_RETURN_NONE;
}
static PyMethodDef cancel_method = {"cancelled", is_cancelled, METH_NOARGS, NULL};
static PyMethodDef partial_method = {"partial", report_partial, METH_O, NULL};
void *kat_mlx_load(const char *resources, const char *directory) {
    if(!resources || !directory || !ot_wayu_python_init(resources)) return NULL;
    PyGILState_STATE gil = PyGILState_Ensure();
    PyObject *module = PyImport_ImportModule("index_mlx");
    PyObject *type = module ? PyObject_GetAttrString(module, "Engine") : NULL;
    PyObject *engine = type ? PyObject_CallFunction(type, "s", directory) : NULL;
    if(PyErr_Occurred()) PyErr_PrintEx(0);
    Py_XDECREF(type); Py_XDECREF(module); PyGILState_Release(gil); return engine;
}
void kat_mlx_free(void *engine) {
    if(!engine) return; PyGILState_STATE gil = PyGILState_Ensure();
    PyObject *value = PyObject_CallMethod(engine, "close", NULL); Py_XDECREF(value);
    if(PyErr_Occurred()) PyErr_PrintEx(0); Py_DECREF((PyObject *)engine); PyGILState_Release(gil);
}
int kat_mlx_count(void *engine, const char *prefix, const char *text, const char *suffix) {
    if(!engine || !prefix || !text || !suffix) return -1;
    PyGILState_STATE gil = PyGILState_Ensure();
    PyObject *out = PyObject_CallMethod(engine, "count", "sss", prefix, text, suffix);
    long count = out ? PyLong_AsLong(out) : -1;
    if(PyErr_Occurred()) { PyErr_PrintEx(0); count = -1; }
    Py_XDECREF(out); PyGILState_Release(gil); return count > 0 && count < 2147483647 ? (int)count : -1;
}
int kat_mlx_run(void *engine, const char *prefix, const char *text, const char *suffix,
                void *flag, char *output, size_t capacity, double *first) {
    return kat_mlx_run_stream(engine, prefix, text, suffix, flag, output, capacity, first, NULL, NULL);
}
int kat_mlx_run_stream(void *engine, const char *prefix, const char *text, const char *suffix,
                      void *flag, char *output, size_t capacity, double *first,
                      kat_mlx_partial_callback partial, void *user) {
    if(output && capacity) output[0] = 0; if(first) *first = -1;
    if(cancelled(flag)) return 2;
    if(!engine || !flag || !prefix || !text || !suffix || !output || capacity < 1 || !first) return -1;
    PyGILState_STATE gil = PyGILState_Ensure();
    Request *request = calloc(1, sizeof(Request));
    if(!request) { PyGILState_Release(gil); return -1; }
    request->flag = flag; request->partial = partial; request->user = user;
    PyObject *capsule = PyCapsule_New(request, "kat.index.request", release_request);
    PyObject *callback = capsule ? PyCFunction_New(&cancel_method, capsule) : NULL;
    PyObject *report = capsule && partial ? PyCFunction_New(&partial_method, capsule) : NULL;
    PyObject *out = NULL;
    if(callback && (!partial || report)) {
        out = partial ? PyObject_CallMethod(engine, "run", "sssOO", prefix, text, suffix, callback, report)
                      : PyObject_CallMethod(engine, "run", "sssO", prefix, text, suffix, callback);
    }
    request->flag = NULL; request->partial = NULL; request->user = NULL;
    if(!capsule) free(request);
    int result = -1;
    if(out && PyTuple_Check(out) && PyTuple_Size(out) == 3) {
        result = (int)PyLong_AsLong(PyTuple_GetItem(out, 0));
        if(result == 0) {
            Py_ssize_t length = 0;
            const char *bytes = PyUnicode_AsUTF8AndSize(PyTuple_GetItem(out, 1), &length);
            double seconds = PyFloat_AsDouble(PyTuple_GetItem(out, 2));
            if(bytes && length >= 0 && (size_t)length < capacity && !PyErr_Occurred()) {
                memcpy(output, bytes, (size_t)length); output[length] = 0; *first = seconds;
            } else result = 1;
        }
    }
    if(PyErr_Occurred()) { PyErr_PrintEx(0); result = -1; }
    if(cancelled(flag)) result = 2;
    if(result != 0) { output[0] = 0; *first = -1; }
    Py_XDECREF(out); Py_XDECREF(report); Py_XDECREF(callback); Py_XDECREF(capsule); PyGILState_Release(gil); return result;
}
#endif
