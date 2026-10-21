// ResolutionTrace - iOS Metal / Unity diagnostic instrument
// OBSERVATION ONLY: does not modify drawable sizes, game settings or rendering.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <MetalKit/MetalKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <execinfo.h>
#import <dispatch/dispatch.h>
#import <fcntl.h>
#import <unistd.h>
#import <stdint.h>
#import <stdlib.h>
#import <stdio.h>
#import <string.h>
#import <math.h>

static void (*originalLayerSetDrawableSize)(id, SEL, CGSize) = NULL;
static id<CAMetalDrawable> (*originalLayerNextDrawable)(id, SEL) = NULL;
static void (*originalViewSetDrawableSize)(id, SEL, CGSize) = NULL;
static __thread BOOL loggingNow = NO;
static int eventCount = 0;
static CGSize lastLayerSize = {-1, -1};
static CGSize lastViewSize = {-1, -1};
static CGSize lastTextureSize = {-1, -1};

static NSString *RTLogPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ResolutionTrace.log"];
}

static BOOL RTChanged(CGSize a, CGSize b) {
    return fabs(a.width - b.width) >= 0.5 || fabs(a.height - b.height) >= 0.5;
}

static void RTWrite(NSString *message, BOOL withBacktrace) {
    if (loggingNow || eventCount >= 250) return;
    loggingNow = YES;
    @autoreleasepool {
        NSMutableString *out = [NSMutableString stringWithFormat:@"[%@] %@\n", [NSDate date], message];
        if (withBacktrace) {
            void *frames[26];
            int n = backtrace(frames, 26);
            for (int i = 2; i < n && i < 22; i++) {
                Dl_info info = {0};
                if (dladdr(frames[i], &info) && info.dli_fname && info.dli_fbase) {
                    const char *name = strrchr(info.dli_fname, '/');
                    name = name ? name + 1 : info.dli_fname;
                    uintptr_t relative = (uintptr_t)frames[i] - (uintptr_t)info.dli_fbase;
                    [out appendFormat:@"  #%02d %s + 0x%llx %@\n", i - 2, name,
                     (unsigned long long)relative,
                     info.dli_sname ? [NSString stringWithUTF8String:info.dli_sname] : @""];
                }
            }
        }
        [out appendString:@"\n"];
        NSString *path = RTLogPath();
        const char *cpath = path.fileSystemRepresentation;
        int fd = open(cpath, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd >= 0) {
            NSData *data = [out dataUsingEncoding:NSUTF8StringEncoding];
            const uint8_t *p = data.bytes;
            size_t left = data.length;
            while (left > 0) {
                ssize_t sent = write(fd, p, left);
                if (sent <= 0) break;
                p += sent;
                left -= (size_t)sent;
            }
            close(fd);
        }
        eventCount++;
    }
    loggingNow = NO;
}

// Trace when Unity / Metal changes the pixel dimensions of the final drawable.
static void RTLayerSetDrawableSize(id self, SEL _cmd, CGSize newSize) {
    if (RTChanged(newSize, lastLayerSize)) {
        lastLayerSize = newSize;
        RTWrite([NSString stringWithFormat:@"CAMetalLayer.setDrawableSize = %.0f x %.0f", newSize.width, newSize.height], YES);
    }
    if (originalLayerSetDrawableSize) originalLayerSetDrawableSize(self, _cmd, newSize);
}

// Also observe the actual texture obtained for display; log only when dimensions change.
static id<CAMetalDrawable> RTLayerNextDrawable(id self, SEL _cmd) {
    id<CAMetalDrawable> drawable = originalLayerNextDrawable ? originalLayerNextDrawable(self, _cmd) : nil;
    if (drawable && !loggingNow) {
        id<MTLTexture> texture = drawable.texture;
        CGSize size = CGSizeMake((CGFloat)texture.width, (CGFloat)texture.height);
        if (RTChanged(size, lastTextureSize)) {
            lastTextureSize = size;
            RTWrite([NSString stringWithFormat:@"CAMetalLayer.nextDrawable texture = %.0f x %.0f", size.width, size.height], YES);
        }
    }
    return drawable;
}

// MTKView may configure the output independently of direct CAMetalLayer calls.
static void RTViewSetDrawableSize(id self, SEL _cmd, CGSize newSize) {
    if (RTChanged(newSize, lastViewSize)) {
        lastViewSize = newSize;
        RTWrite([NSString stringWithFormat:@"MTKView.setDrawableSize = %.0f x %.0f", newSize.width, newSize.height], YES);
    }
    if (originalViewSetDrawableSize) originalViewSetDrawableSize(self, _cmd, newSize);
}

// Require method to be implemented by the class, not inherited from a superclass.
static Method RTMethodOwnedByClass(Class cls, SEL selector) {
    if (!cls) return NULL;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    Method result = NULL;
    for (unsigned int i = 0; i < count; ++i) {
        if (sel_isEqual(method_getName(methods[i]), selector)) {
            result = methods[i];
            break;
        }
    }
    free(methods);
    return result;
}

__attribute__((constructor)) static void RTInstall(void) {
    @autoreleasepool {
        NSString *folder = [RTLogPath() stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:folder
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        RTWrite(@"ResolutionTrace START | observation-only; no resolution changes", NO);

        Method m = RTMethodOwnedByClass([CAMetalLayer class], @selector(setDrawableSize:));
        if (m) {
            originalLayerSetDrawableSize = (void (*)(id, SEL, CGSize))method_setImplementation(m, (IMP)RTLayerSetDrawableSize);
            RTWrite(@"Installed hook: CAMetalLayer.setDrawableSize", NO);
        } else RTWrite(@"UNAVAILABLE: CAMetalLayer.setDrawableSize", NO);

        m = RTMethodOwnedByClass([CAMetalLayer class], @selector(nextDrawable));
        if (m) {
            originalLayerNextDrawable = (id<CAMetalDrawable> (*)(id, SEL))method_setImplementation(m, (IMP)RTLayerNextDrawable);
            RTWrite(@"Installed hook: CAMetalLayer.nextDrawable", NO);
        } else RTWrite(@"UNAVAILABLE: CAMetalLayer.nextDrawable", NO);

        Class viewClass = NSClassFromString(@"MTKView");
        m = RTMethodOwnedByClass(viewClass, @selector(setDrawableSize:));
        if (m) {
            originalViewSetDrawableSize = (void (*)(id, SEL, CGSize))method_setImplementation(m, (IMP)RTViewSetDrawableSize);
            RTWrite(@"Installed hook: MTKView.setDrawableSize", NO);
        } else RTWrite(@"UNAVAILABLE: MTKView.setDrawableSize", NO);

        dispatch_async(dispatch_get_main_queue(), ^{
            UIScreen *screen = [UIScreen mainScreen];
            CGRect pixels = screen.nativeBounds;
            CGRect points = screen.bounds;
            RTWrite([NSString stringWithFormat:
                     @"UIScreen nativeBounds=%.0fx%.0f px; bounds=%.0fx%.0f pt; scale=%.3f; nativeScale=%.3f",
                     pixels.size.width, pixels.size.height,
                     points.size.width, points.size.height,
                     screen.scale, screen.nativeScale], NO);
        });
    }
}
