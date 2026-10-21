#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <Metal/Metal.h>
extern "C" int kat_metrics(double *out) {
    @autoreleasepool {
        task_vm_info_data_t v{};
        mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
        int rc = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&v, &n);
        if (rc != KERN_SUCCESS) return rc;
        out[0]=v.phys_footprint; out[1]=v.resident_size; out[2]=v.resident_size_peak;
        out[3]=(int)NSProcessInfo.processInfo.thermalState;
        out[4]=MTLCreateSystemDefaultDevice().currentAllocatedSize;
        return 0;
    }
}
