// buftex-mip: a buffer-backed 54x54 texture with 6 mips (what WindowServer asks for Dock badges) must exist and follow the buffer
#import <Metal/Metal.h>
#include <stdio.h>
int main(void) { @autoreleasepool {
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice(); printf("device: %s\n", dev.name.UTF8String);
    const NSUInteger w = 54, h = 54, bpr = 256;
    id<MTLBuffer> b = [dev newBufferWithLength:bpr * h options:MTLResourceStorageModeShared];
    uint32_t *p = b.contents; for (NSUInteger i = 0; i < bpr * h / 4; i++) p[i] = 0xff0000ff;
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:w height:h mipmapped:YES];
    d.storageMode = MTLStorageModeShared; d.usage = MTLTextureUsageShaderRead;
    printf("asked for %lu mips\n", (unsigned long)d.mipmapLevelCount);
    id<MTLTexture> t = [b newTextureWithDescriptor:d offset:0 bytesPerRow:bpr];
    if (!t) { printf("RESULT: FAIL nil texture\n"); return 1; }
    printf("texture %lux%lu mips %lu\n", (unsigned long)t.width, (unsigned long)t.height, (unsigned long)t.mipmapLevelCount);
    uint32_t px = 0; [t getBytes:&px bytesPerRow:4 fromRegion:MTLRegionMake2D(10, 10, 1, 1) mipmapLevel:0];
    for (NSUInteger i = 0; i < bpr * h / 4; i++) p[i] = 0xff00ff00;   // written after the texture was made
    uint32_t px2 = 0; [t getBytes:&px2 bytesPerRow:4 fromRegion:MTLRegionMake2D(10, 10, 1, 1) mipmapLevel:0];
    printf("pixel 0x%08x (want 0xff0000ff), after buffer write 0x%08x (want 0xff00ff00)\n", px, px2);
    int ok = px == 0xff0000ff && px2 == 0xff00ff00;
    printf("RESULT: %s\n", ok ? "mipmapped buffer texture works" : "FAIL"); return !ok;
}}
