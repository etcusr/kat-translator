// Android-only confidence adapter. Compile the original shared runtime here so its
// opaque handle and helper layout cannot drift; Apple continues compiling it directly.
#include "Camera/OCRRuntime.c"

int ot_ocr_run_scored(void *handle, const float *input, int width, int *ids, float *scores, int capacity) {
    OCR *c = handle; if (!c || !input || !ids || width < 8 || width > 4096 || capacity < 1) return -1;
    int64_t dims[4] = {1,3,c->height,width}; OrtValue *in = NULL, *out = NULL; OrtTensorTypeAndShapeInfo *shape = NULL; int result = -1;
    size_t bytes = (size_t)3*c->height*width*sizeof(float);
    if (!ok(c,c->api->CreateTensorWithDataAsOrtValue(c->memory,(void *)input,bytes,dims,4,ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,&in))) goto end;
    const OrtValue *inputs[] = {in}; const char *names[] = {c->input}, *outputs[] = {c->output};
    if (!ok(c,c->api->Run(c->session,NULL,names,inputs,1,outputs,1,&out)) || !ok(c,c->api->GetTensorTypeAndShape(out,&shape))) goto end;
    size_t rank = 0; int64_t sizes[3]; ONNXTensorElementDataType dtype;
    if (!ok(c,c->api->GetDimensionsCount(shape,&rank)) || rank != 3 || !ok(c,c->api->GetDimensions(shape,sizes,3)) ||
        !ok(c,c->api->GetTensorElementType(shape,&dtype)) || dtype != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT ||
        sizes[0] != 1 || sizes[1] < 1 || sizes[1] > capacity || sizes[2] < 2 || sizes[2] > 30000) goto end;
    float *values = NULL; if (!ok(c,c->api->GetTensorMutableData(out,(void **)&values))) goto end;
    for (int t=0; t<sizes[1]; ++t) {
        int best = 0; float score = -INFINITY;
        for (int j=0; j<sizes[2]; ++j) { float value = values[t*sizes[2]+j]; if (!isfinite(value)) goto end; if (value > score) { score=value; best=j; } }
        ids[t]=best;
        if (scores) { if (score < 0 || score > 1) goto end; scores[t]=score; }
    }
    result = (int)sizes[1];
end:
    if (shape) c->api->ReleaseTensorTypeAndShapeInfo(shape);
    if (out) c->api->ReleaseValue(out);
    if (in) c->api->ReleaseValue(in);
    return result;
}
