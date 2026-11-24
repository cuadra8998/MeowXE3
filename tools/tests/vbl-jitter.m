// vbl-jitter: records the display's vertical-blank callbacks (what Core Animation paces its frames by) for N seconds
// and prints the interval spread, late/missed ticks, and the GPU clock (MeowXE3GPUFreq, refreshed every 5 s).
// Build: xcrun clang -O2 -fobjc-arc -framework Foundation -framework CoreVideo -framework IOKit -o vbl-jitter vbl-jitter.m
// Run:   ./vbl-jitter 20      (open Launchpad, swipe spaces, minimize a window while it runs)
#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <IOKit/IOKitLib.h>
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <math.h>
#include <sys/sysctl.h>

#define MAXT 20000
static uint64_t gHost[MAXT];      // host time the callback ran
static uint64_t gVbl[MAXT];       // the display link's own vblank timestamp (inNow->hostTime)
static _Atomic int gN;
static double gTick;              // ns per mach tick

static CVReturn cb(CVDisplayLinkRef l, const CVTimeStamp *now, const CVTimeStamp *out, CVOptionFlags f, CVOptionFlags *fo, void *c) {
    int i = atomic_fetch_add(&gN, 1);
    if (i < MAXT) { gHost[i] = mach_absolute_time(); gVbl[i] = now->hostTime; }
    return kCVReturnSuccess;
}

static NSString *gpuFreq(void) {
    io_iterator_t it; NSString *s = nil;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOFramebuffer"), &it) != KERN_SUCCESS) return nil;
    for (io_object_t o; (o = IOIteratorNext(it)); IOObjectRelease(o)) {
        CFTypeRef v = IORegistryEntryCreateCFProperty(o, CFSTR("MeowXE3GPUFreq"), kCFAllocatorDefault, 0);
        if (v) { s = (__bridge_transfer NSString *)v; }
    }
    IOObjectRelease(it);
    return s;
}

static long long sc(const char *n) { long long v = 0; size_t l = sizeof v; if (sysctlbyname(n, &v, &l, NULL, 0)) return -1; return l == 4 ? (long long)*(int *)&v : v; }

static int cmpd(const void *a, const void *b) { double x = *(double *)a, y = *(double *)b; return x < y ? -1 : x > y; }

static void stats(const char *name, uint64_t *t, int n, double period) {
    if (n < 3) return;
    double *d = malloc(sizeof(double) * n); int m = 0, late = 0, missed = 0;
    for (int i = 1; i < n; i++) {
        double ms = (t[i] - t[i - 1]) * gTick / 1e6; d[m++] = ms;
        if (ms > period * 1.5) missed += (int)(ms / period + 0.5) - 1;
        else if (ms > period * 1.1) late++;
    }
    qsort(d, m, sizeof(double), cmpd);
    double sum = 0, sq = 0; for (int i = 0; i < m; i++) { sum += d[i]; }
    double mean = sum / m; for (int i = 0; i < m; i++) sq += (d[i] - mean) * (d[i] - mean);
    printf("%-9s n=%d mean %.3f ms (%.2f Hz)  sd %.3f  min %.3f  p50 %.3f  p99 %.3f  max %.3f  >10%% late %d  missed %d\n",
           name, m, mean, 1000 / mean, sqrt(sq / m), d[0], d[m / 2], d[(int)(m * 0.99)], d[m - 1], late, missed);
    free(d);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        double secs = argc > 1 ? atof(argv[1]) : 15;
        mach_timebase_info_data_t tb; mach_timebase_info(&tb); gTick = (double)tb.numer / tb.denom;
        CVDisplayLinkRef link; CVDisplayLinkCreateWithActiveCGDisplays(&link);
        CVTime p = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link);
        double period = p.timeScale ? 1000.0 * p.timeValue / p.timeScale : 16.667;
        printf("nominal refresh period %.3f ms; recording %.0f s\n", period, secs);
        printf("GPU: %s\n", gpuFreq().UTF8String ?: "?");
        CVDisplayLinkSetOutputCallback(link, cb, NULL);
        CVDisplayLinkStart(link);
        // composited frames per 250 ms (debug.nvaccel_iop_ok) and the copy cost per frame (debug.nvaccel_iop_copy_us)
        printf("frames/s per 250 ms (copy us/frame), a line per second:\n");
        long long f0 = sc("debug.nvaccel_iop_ok"), c0 = sc("debug.nvaccel_iop_copy_us");
        for (int q = 0; q < (int)(secs * 4); q++) {
            [NSThread sleepForTimeInterval:0.25];
            long long f1 = sc("debug.nvaccel_iop_ok"), c1 = sc("debug.nvaccel_iop_copy_us");
            long long df = f1 - f0, dc = c1 - c0; f0 = f1; c0 = c1;
            printf(" %3lld(%4lld)", df * 4, df ? dc / df : 0);
            if (q % 4 == 3) { printf("   t=%ds\n", q / 4 + 1); fflush(stdout); }
            if (q % 20 == 19) printf("        GPU: %s\n", gpuFreq().UTF8String ?: "?");
        }
        CVDisplayLinkStop(link);
        int n = MIN(atomic_load(&gN), MAXT);
        stats("callback", gHost, n, period);
        stats("vbl-stamp", gVbl, n, period);
        // the 5 longest callback gaps and when they happened
        printf("longest gaps (ms @ s):");
        static double gap[MAXT];
        for (int i = 1; i < n; i++) gap[i] = (gHost[i] - gHost[i - 1]) * gTick / 1e6;
        for (int k = 0; k < 5; k++) {
            int bi = -1; double best = 0;
            for (int i = 1; i < n; i++) if (gap[i] > best) { best = gap[i]; bi = i; }
            if (bi < 0) break;
            printf("  %.1f@%.1f", best, (gHost[bi] - gHost[0]) * gTick / 1e9);
            gap[bi] = 0;
        }
        printf("\n");
    }
    return 0;
}
