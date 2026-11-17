// nmx-metal-render: renders a triangle (vertex + fragment shaders compiled at run time) into a 256x256 texture cleared
// to blue, reads the pixels back and checks them: the inside of the triangle must be red, the corners blue.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static NSString *const kSource =
    @"#include <metal_stdlib>\nusing namespace metal;\n"
     "struct VOut { float4 pos [[position]]; float4 color; };\n"
     "vertex VOut vs(uint vid [[vertex_id]], constant float2 *pts [[buffer(0)]]) {\n"
     "    VOut o; o.pos = float4(pts[vid], 0.0, 1.0); o.color = float4(1, 0, 0, 1); return o; }\n"
     "fragment float4 fs(VOut in [[stage_in]]) { return in.color; }\n";

static void bench(id<MTLDevice> dev, id<MTLRenderPipelineState> ps, id<MTLBuffer> vb, NSUInteger W, NSUInteger H) {
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                   width:W height:H mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget;
    td.storageMode = MTLStorageModePrivate;
    id<MTLTexture> tex = [dev newTextureWithDescriptor:td];
    id<MTLCommandQueue> q = [dev newCommandQueue];
    for (int pass = 0; pass < 2; pass++) {
        BOOL wait = pass == 0;
        const int N = 300;
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        id<MTLCommandBuffer> last = nil;
        for (int i = 0; i < N; i++) {
            MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
            rp.colorAttachments[0].texture = tex;
            rp.colorAttachments[0].loadAction = MTLLoadActionClear;
            rp.colorAttachments[0].storeAction = MTLStoreActionStore;
            id<MTLCommandBuffer> cb = [q commandBuffer];
            id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
            [enc setRenderPipelineState:ps];
            [enc setVertexBuffer:vb offset:0 atIndex:0];
            [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
            [enc endEncoding];
            [cb commit];
            if (wait) [cb waitUntilCompleted];
            last = cb;
        }
        [last waitUntilCompleted];
        double s = CFAbsoluteTimeGetCurrent() - t0;
        printf("bench %lux%lu, %s: %d frames in %.2f s = %.0f frames/s (%.2f ms each)\n", (unsigned long)W,
               (unsigned long)H, wait ? "wait for each frame" : "queued", N, s, N / s, s * 1000.0 / N);
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        if (!dev) { printf("RESULT: no Metal device\n"); return 1; }
        printf("device: %s\n", dev.name.UTF8String);
        NSError *err = nil;
        id<MTLLibrary> lib = [dev newLibraryWithSource:kSource options:nil error:&err];
        if (!lib) { printf("compile failed: %s\n", err.localizedDescription.UTF8String); return 1; }
        MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
        pd.vertexFunction = [lib newFunctionWithName:@"vs"];
        pd.fragmentFunction = [lib newFunctionWithName:@"fs"];
        pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        id<MTLRenderPipelineState> ps = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
        if (!ps) { printf("pipeline failed: %s\n", err.localizedDescription.UTF8String); return 1; }
        const NSUInteger W = 256, H = 256;
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                       width:W height:H mipmapped:NO];
        td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        td.storageMode = MTLStorageModeManaged;
        id<MTLTexture> tex = [dev newTextureWithDescriptor:td];
        float pts[] = { -0.8f, -0.8f, 0.8f, -0.8f, 0.0f, 0.8f };
        id<MTLBuffer> vb = [dev newBufferWithBytes:pts length:sizeof(pts) options:MTLResourceStorageModeShared];
        if (argc > 1 && strcmp(argv[1], "bench") == 0) {
            bench(dev, ps, vb, 640, 480);
            bench(dev, ps, vb, 1920, 1080);
            return 0;
        }
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = tex;
        rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 1, 1);
        id<MTLCommandQueue> q = [dev newCommandQueue];
        id<MTLCommandBuffer> cb = [q commandBuffer];
        id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
        [enc setRenderPipelineState:ps];
        [enc setVertexBuffer:vb offset:0 atIndex:0];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [enc endEncoding];
        id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
        [bl synchronizeResource:tex];
        [bl endEncoding];
        [cb commit];
        [cb waitUntilCompleted];
        if (cb.status != MTLCommandBufferStatusCompleted) {
            printf("command buffer status %ld: %s\nRESULT: render failed\n", (long)cb.status, cb.error.localizedDescription.UTF8String);
            return 1;
        }
        uint32_t *px = malloc(W * H * 4);
        [tex getBytes:px bytesPerRow:W * 4 fromRegion:MTLRegionMake2D(0, 0, W, H) mipmapLevel:0];
        // BGRA8 little endian: 0xAARRGGBB
        uint32_t center = px[(H / 2) * W + W / 2], corner = px[2 * W + 2];
        NSUInteger red = 0, blue = 0, other = 0;
        for (NSUInteger i = 0; i < W * H; i++) {
            if (px[i] == 0xFFFF0000u) red++; else if (px[i] == 0xFF0000FFu) blue++; else other++;
        }
        printf("center 0x%08x (want 0xffff0000 red), corner 0x%08x (want 0xff0000ff blue)\n", center, corner);
        printf("pixels: %lu red, %lu blue, %lu other (a triangle covers about 32%%)\n", (unsigned long)red,
               (unsigned long)blue, (unsigned long)other);
        BOOL ok = center == 0xFFFF0000u && corner == 0xFF0000FFu && red > W * H / 5 && red < W * H / 2;
        printf("RESULT: %s\n", ok ? "Metal rendering works" : "wrong pixels");
        return ok ? 0 : 1;
    }
}
