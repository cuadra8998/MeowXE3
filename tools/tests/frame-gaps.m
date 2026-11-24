// frame-gaps: timestamps every frame that reaches the panel (debug.nvaccel_iop_ok, polled at ~1 kHz) for N seconds and
// lists the gaps longer than a threshold, so a one-off hitch (closing Launchpad, Mission Control) can be found in time.
// Build: xcrun clang -O2 -fobjc-arc -framework Foundation -o frame-gaps frame-gaps.m
// Run:   ./frame-gaps 15 [threshold_ms=34]      prints "t=…s gap … ms" with the frames-per-second either side
#import <Foundation/Foundation.h>
#include <sys/sysctl.h>
#include <mach/mach_time.h>

static long long sc(const char *n) { long long v = 0; size_t l = sizeof v; if (sysctlbyname(n, &v, &l, NULL, 0)) return -1; return l == 4 ? (long long)*(int *)&v : v; }

#define MAXF 20000
static double gT[MAXF];   // seconds since start, one per frame
static long long gCopy[MAXF];

int main(int argc, char **argv) {
    @autoreleasepool {
        double secs = argc > 1 ? atof(argv[1]) : 15, thr = argc > 2 ? atof(argv[2]) : 34;
        mach_timebase_info_data_t tb; mach_timebase_info(&tb);
        const uint64_t t0 = mach_absolute_time();
        long long last = sc("debug.nvaccel_iop_ok"), c = sc("debug.nvaccel_iop_copy_us");
        if (last < 0) { fprintf(stderr, "no debug.nvaccel_iop_ok: is MeowXE3 loaded?\n"); return 1; }
        int n = 0;
        printf("recording %.0f s (gaps over %.0f ms)... go\n", secs, thr); fflush(stdout);
        for (;;) {
            double t = (mach_absolute_time() - t0) * (double)tb.numer / tb.denom / 1e9;
            if (t >= secs) break;
            long long v = sc("debug.nvaccel_iop_ok");
            if (v != last) {
                long long c1 = sc("debug.nvaccel_iop_copy_us");
                for (long long k = last; k < v && n < MAXF; k++) { gT[n] = t; gCopy[n] = (v - last) ? (c1 - c) / (v - last) : 0; n++; }
                last = v; c = c1;
            }
            usleep(1000);
        }
        int big = 0; double worst = 0;
        for (int i = 1; i < n; i++) {
            double g = (gT[i] - gT[i - 1]) * 1000;
            if (g > worst) worst = g;
            if (g < thr) continue;
            big++;
            int before = 0, after = 0;   // frames in the 0.5 s either side
            for (int j = 0; j < n; j++) { if (gT[j] < gT[i - 1] && gT[j] >= gT[i - 1] - 0.5) before++; if (gT[j] >= gT[i] && gT[j] < gT[i] + 0.5) after++; }
            printf("t=%6.3fs  gap %6.1f ms   (%2d fps before, %2d fps after, copy %lld us)\n", gT[i - 1], g, before * 2, after * 2, gCopy[i]);
        }
        printf("%d frames in %.0f s (%.1f fps), %d gaps over %.0f ms, worst %.1f ms\n", n, secs, n / secs, big, thr, worst);
    }
    return 0;
}
