// nmx-metal-test: lists the Metal devices macOS offers this process, then runs a compute kernel (compiled from source at
// run time) on each and checks the result. Exit code 0 only when a device ran the kernel correctly.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static NSString *const kSource =
    @"#include <metal_stdlib>\n"
     "using namespace metal;\n"
     "kernel void add_arrays(device const float *a [[buffer(0)]], device const float *b [[buffer(1)]],\n"
     "                       device float *out [[buffer(2)]], uint i [[thread_position_in_grid]]) {\n"
     "    out[i] = a[i] * 2.0f + b[i];\n"
     "}\n";

static BOOL runOn(id<MTLDevice> dev) {
    NSError *err = nil;
    id<MTLLibrary> lib = [dev newLibraryWithSource:kSource options:nil error:&err];
    if (!lib) { printf("    compile failed: %s\n", err.localizedDescription.UTF8String); return NO; }
    id<MTLFunction> fn = [lib newFunctionWithName:@"add_arrays"];
    id<MTLComputePipelineState> ps = [dev newComputePipelineStateWithFunction:fn error:&err];
    if (!ps) { printf("    pipeline failed: %s\n", err.localizedDescription.UTF8String); return NO; }
    const NSUInteger n = 1 << 20;
    id<MTLBuffer> a = [dev newBufferWithLength:n * 4 options:MTLResourceStorageModeShared];
    id<MTLBuffer> b = [dev newBufferWithLength:n * 4 options:MTLResourceStorageModeShared];
    id<MTLBuffer> o = [dev newBufferWithLength:n * 4 options:MTLResourceStorageModeShared];
    float *pa = a.contents, *pb = b.contents, *po = o.contents;
    for (NSUInteger i = 0; i < n; i++) { pa[i] = (float)i; pb[i] = 1.0f; po[i] = -1.0f; }
    id<MTLCommandQueue> q = [dev newCommandQueue];
    id<MTLCommandBuffer> cb = [q commandBuffer];
    id<MTLComputeCommandEncoder> enc = [cb computeCommandEncoder];
    [enc setComputePipelineState:ps];
    [enc setBuffer:a offset:0 atIndex:0];
    [enc setBuffer:b offset:0 atIndex:1];
    [enc setBuffer:o offset:0 atIndex:2];
    NSUInteger tg = MIN(ps.maxTotalThreadsPerThreadgroup, (NSUInteger)256);
    [enc dispatchThreads:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(tg, 1, 1)];
    [enc endEncoding];
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [cb commit];
    [cb waitUntilCompleted];
    double ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
    if (cb.status != MTLCommandBufferStatusCompleted) {
        printf("    command buffer status %ld: %s\n", (long)cb.status, cb.error.localizedDescription.UTF8String);
        return NO;
    }
    NSUInteger bad = 0;
    for (NSUInteger i = 0; i < n; i++) if (po[i] != (float)i * 2.0f + 1.0f) bad++;
    printf("    %lu elements, %lu wrong, %.2f ms on the GPU\n", (unsigned long)n, (unsigned long)bad, ms);
    return bad == 0;
}

int main(void) {
    @autoreleasepool {
        NSArray<id<MTLDevice>> *devs = MTLCopyAllDevices();
        printf("Metal devices: %lu\n", (unsigned long)devs.count);
        BOOL ok = NO;
        for (id<MTLDevice> d in devs) {
            printf("  %s  (registry 0x%llx, low power %d, headless %d, unified memory %d)\n", d.name.UTF8String,
                   d.registryID, d.isLowPower, d.isHeadless, d.hasUnifiedMemory);
            ok |= runOn(d);
        }
        if (devs.count == 0) printf("No Metal device: the accelerator or the plugin did not offer one.\n");
        printf("%s\n", ok ? "RESULT: Metal compute works" : "RESULT: no device ran the kernel");
        return ok ? 0 : 1;
    }
}
