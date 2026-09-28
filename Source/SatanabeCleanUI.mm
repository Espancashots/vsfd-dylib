#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "SCUIConfig.h"

static const void *kSCUIBlockedPlayerKey = &kSCUIBlockedPlayerKey;
static const void *kSCUIBlurViewKey = &kSCUIBlurViewKey;
static const void *kSCUIStyledCardKey = &kSCUIStyledCardKey;

static IMP gOrigUIViewDidMoveToWindow = NULL;
static IMP gOrigUIViewControllerViewDidAppear = NULL;
static IMP gOrigAVPlayerPlay = NULL;
static IMP gOrigAVPlayerPlayImmediately = NULL;
static IMP gOrigUIControlSetHighlighted = NULL;

static inline UIColor *SCUIWhite(CGFloat alpha) {
    return [UIColor colorWithWhite:1.0 alpha:alpha];
}

static inline UIColor *SCUIBlack(CGFloat alpha) {
    return [UIColor colorWithWhite:0.0 alpha:alpha];
}

static BOOL SCUIClassNameContains(id obj, NSString *needle) {
    if (!obj || !needle.length) return NO;
    NSString *name = NSStringFromClass([obj class]);
    return [name rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL SCUIIsLoopingVideoView(UIView *view) {
    if (!view) return NO;
    if (SCUIClassNameContains(view, @"LoopingPlayerView")) return YES;
    return [view.layer isKindOfClass:[AVPlayerLayer class]];
}

static void SCUIBlockPlayer(AVPlayer *player) {
    if (!player) return;
    objc_setAssociatedObject(player, kSCUIBlockedPlayerKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [player pause];
    if ([player isKindOfClass:[AVQueuePlayer class]]) {
        [(AVQueuePlayer *)player removeAllItems];
    }
}

static void SCUIDisableVideoView(UIView *view) {
    if (!view || !SCUIIsLoopingVideoView(view)) return;

    if ([view.layer isKindOfClass:[AVPlayerLayer class]]) {
        AVPlayerLayer *layer = (AVPlayerLayer *)view.layer;
        AVPlayer *player = layer.player;
        SCUIBlockPlayer(player);
        layer.player = nil;
        layer.backgroundColor = UIColor.blackColor.CGColor;
    }

    // Keep the representable view in place as an opaque black cover. This is
    // intentional: it hides both the old video and PatchBackground image while
    // preserving the SwiftUI layout above it.
    view.hidden = NO;
    view.alpha = 1.0;
    view.opaque = YES;
    view.backgroundColor = UIColor.blackColor;
    view.userInteractionEnabled = NO;
}

static UIVisualEffect *SCUIGlassEffect(void) {
    // Use public UIKit material. It gives a stable glass look across iOS builds
    // without linking against private SwiftUI implementation details.
    if (@available(iOS 13.0, *)) {
        return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
}

static BOOL SCUIShouldStyleAsCard(UIView *view, UIWindow *window) {
    if (!view || !window || view.hidden || view.alpha < 0.02) return NO;
    if ([view isKindOfClass:[UIWindow class]] ||
        [view isKindOfClass:[UILabel class]] ||
        [view isKindOfClass:[UIImageView class]] ||
        [view isKindOfClass:[UIVisualEffectView class]] ||
        [view isKindOfClass:[UIScrollView class]] ||
        [view isKindOfClass:[UIStackView class]] ||
        [view isKindOfClass:[UIControl class]]) {
        return NO;
    }

    CGRect b = view.bounds;
    if (CGRectIsEmpty(b) || b.size.width < 120.0 || b.size.height < 40.0 || b.size.height > 180.0) return NO;
    if (b.size.width > window.bounds.size.width * 0.96) return NO;

    CGFloat radius = view.layer.cornerRadius;
    CGFloat alpha = CGColorGetAlpha(view.backgroundColor.CGColor ?: UIColor.clearColor.CGColor);
    BOOL alreadyRounded = radius >= 10.0;
    BOOL hasTranslucentBackground = alpha > 0.04 && alpha < 0.90;
    return alreadyRounded || hasTranslucentBackground;
}

static void SCUIStyleVisualEffectView(UIVisualEffectView *effectView) {
    if (!effectView) return;
    effectView.effect = SCUIGlassEffect();
    effectView.backgroundColor = SCUIBlack(0.08);
    effectView.layer.borderColor = SCUIWhite(SCUI_GLASS_BORDER_ALPHA).CGColor;
    effectView.layer.borderWidth = SCUI_GLASS_BORDER_WIDTH;
    if (effectView.layer.cornerRadius < 10.0) {
        effectView.layer.cornerRadius = SCUI_GLASS_CORNER_RADIUS;
    }
    effectView.clipsToBounds = YES;
}

static void SCUIStyleCard(UIView *view) {
    if (!view || [objc_getAssociatedObject(view, kSCUIStyledCardKey) boolValue]) return;
    objc_setAssociatedObject(view, kSCUIStyledCardKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    view.backgroundColor = SCUIBlack(SCUI_GLASS_BLACK_ALPHA);
    if (view.layer.cornerRadius < 10.0) view.layer.cornerRadius = SCUI_GLASS_CORNER_RADIUS;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderColor = SCUIWhite(SCUI_GLASS_BORDER_ALPHA).CGColor;
    view.layer.borderWidth = SCUI_GLASS_BORDER_WIDTH;
    view.clipsToBounds = YES;

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:SCUIGlassEffect()];
    blur.userInteractionEnabled = NO;
    blur.frame = view.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blur.alpha = 0.76;
    blur.layer.cornerRadius = view.layer.cornerRadius;
    blur.clipsToBounds = YES;
    [view insertSubview:blur atIndex:0];
    objc_setAssociatedObject(view, kSCUIBlurViewKey, blur, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL SCUIIsFloatingControl(UIControl *control) {
    if (!control || control.hidden || !control.userInteractionEnabled) return NO;
    CGSize s = control.bounds.size;
    if (s.width < 34.0 || s.height < 34.0 || s.width > 86.0 || s.height > 86.0) return NO;
    return fabs(s.width - s.height) <= 18.0;
}

static void SCUIStyleControl(UIControl *control) {
    if (!control) return;
    control.tintColor = UIColor.whiteColor;

    if ([control isKindOfClass:[UISwitch class]]) {
        UISwitch *sw = (UISwitch *)control;
        sw.onTintColor = SCUIWhite(0.92);
        sw.thumbTintColor = UIColor.whiteColor;
        sw.tintColor = SCUIWhite(0.22);
    } else if ([control isKindOfClass:[UISegmentedControl class]]) {
        UISegmentedControl *seg = (UISegmentedControl *)control;
        seg.selectedSegmentTintColor = SCUIWhite(0.16);
        NSDictionary *normal = @{ NSForegroundColorAttributeName: SCUIWhite(0.66) };
        NSDictionary *selected = @{ NSForegroundColorAttributeName: UIColor.whiteColor };
        [seg setTitleTextAttributes:normal forState:UIControlStateNormal];
        [seg setTitleTextAttributes:selected forState:UIControlStateSelected];
        seg.layer.cornerRadius = 12.0;
        seg.layer.borderWidth = SCUI_GLASS_BORDER_WIDTH;
        seg.layer.borderColor = SCUIWhite(SCUI_GLASS_BORDER_ALPHA).CGColor;
        seg.clipsToBounds = YES;
    }

    if (SCUIIsFloatingControl(control)) {
        CGFloat r = MIN(control.bounds.size.width, control.bounds.size.height) * 0.5;
        control.layer.cornerRadius = r;
        control.layer.cornerCurve = kCACornerCurveContinuous;
        control.backgroundColor = SCUIBlack(0.32);
        control.layer.borderColor = SCUIWhite(SCUI_FLOATING_IDLE_BORDER_ALPHA).CGColor;
        control.layer.borderWidth = SCUI_FLOATING_IDLE_BORDER_WIDTH;
        control.clipsToBounds = YES;
    }
}

static void SCUIProcessView(UIView *view, UIWindow *window) {
    if (!view) return;

    if (SCUIIsLoopingVideoView(view)) {
        SCUIDisableVideoView(view);
    }

    if ([view isKindOfClass:[UIVisualEffectView class]]) {
        SCUIStyleVisualEffectView((UIVisualEffectView *)view);
    }

    if ([view isKindOfClass:[UIControl class]]) {
        SCUIStyleControl((UIControl *)view);
    }

    if (SCUIShouldStyleAsCard(view, window)) {
        SCUIStyleCard(view);
    }

    for (UIView *subview in view.subviews.copy) {
        SCUIProcessView(subview, window);
    }
}

static NSArray<UIWindow *> *SCUIWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (window) [windows addObject:window];
        }
    }
    return windows;
}

static void SCUIApplyCleanUI(void) {
    NSCAssert(NSThread.isMainThread, @"SatanabeCleanUI must style UIKit on the main thread");

    for (UIWindow *window in SCUIWindows()) {
#if SCUI_BACKGROUND_BLACK
        window.backgroundColor = UIColor.blackColor;
        if (window.rootViewController.view) {
            window.rootViewController.view.backgroundColor = UIColor.blackColor;
        }
#endif
        window.tintColor = UIColor.whiteColor;
        SCUIProcessView(window, window);
    }
}

#pragma mark - Swizzles

static void scui_AVPlayer_play(AVPlayer *self, SEL _cmd) {
    if ([objc_getAssociatedObject(self, kSCUIBlockedPlayerKey) boolValue]) {
        [self pause];
        return;
    }
    ((void (*)(id, SEL))gOrigAVPlayerPlay)(self, _cmd);
}

static void scui_AVPlayer_playImmediatelyAtRate(AVPlayer *self, SEL _cmd, float rate) {
    if ([objc_getAssociatedObject(self, kSCUIBlockedPlayerKey) boolValue]) {
        [self pause];
        return;
    }
    if (gOrigAVPlayerPlayImmediately) {
        ((void (*)(id, SEL, float))gOrigAVPlayerPlayImmediately)(self, _cmd, rate);
    }
}

static void scui_UIView_didMoveToWindow(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigUIViewDidMoveToWindow)(self, _cmd);
    if (!self.window) return;
    if (SCUIIsLoopingVideoView(self) || [self isKindOfClass:[UIVisualEffectView class]] || [self isKindOfClass:[UIControl class]]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SCUIProcessView(self, self.window);
        });
    }
}

static void scui_UIViewController_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    ((void (*)(id, SEL, BOOL))gOrigUIViewControllerViewDidAppear)(self, _cmd, animated);
    dispatch_async(dispatch_get_main_queue(), ^{
        SCUIApplyCleanUI();
    });
}

static void scui_UIControl_setHighlighted(UIControl *self, SEL _cmd, BOOL highlighted) {
    ((void (*)(id, SEL, BOOL))gOrigUIControlSetHighlighted)(self, _cmd, highlighted);

    if (!SCUIIsFloatingControl(self)) return;
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.12];
    self.layer.borderColor = SCUIWhite(highlighted ? SCUI_FLOATING_ACTIVE_BORDER_ALPHA : SCUI_FLOATING_IDLE_BORDER_ALPHA).CGColor;
    self.layer.borderWidth = highlighted ? SCUI_FLOATING_ACTIVE_BORDER_WIDTH : SCUI_FLOATING_IDLE_BORDER_WIDTH;
    [CATransaction commit];
}

static UIColor *scui_UIColor_systemOrangeColor(id self, SEL _cmd) {
    return UIColor.whiteColor;
}

static UIColor *scui_UIColor_orangeColor(id self, SEL _cmd) {
    return UIColor.whiteColor;
}

static void SCUISwizzleInstanceMethod(Class cls, SEL originalSelector, IMP replacement, IMP *originalOut) {
    Method method = class_getInstanceMethod(cls, originalSelector);
    if (!method) return;
    IMP original = method_getImplementation(method);
    if (originalOut) *originalOut = original;
    method_setImplementation(method, replacement);
}

static void SCUIReplaceClassMethod(Class cls, SEL selector, IMP replacement) {
    Method method = class_getClassMethod(cls, selector);
    if (!method) return;
    method_setImplementation(method, replacement);
}

static void SCUIInstallHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SCUISwizzleInstanceMethod([UIView class], @selector(didMoveToWindow), (IMP)scui_UIView_didMoveToWindow, &gOrigUIViewDidMoveToWindow);
        SCUISwizzleInstanceMethod([UIViewController class], @selector(viewDidAppear:), (IMP)scui_UIViewController_viewDidAppear, &gOrigUIViewControllerViewDidAppear);
        SCUISwizzleInstanceMethod([AVPlayer class], @selector(play), (IMP)scui_AVPlayer_play, &gOrigAVPlayerPlay);
        SCUISwizzleInstanceMethod([UIControl class], @selector(setHighlighted:), (IMP)scui_UIControl_setHighlighted, &gOrigUIControlSetHighlighted);

        Method immediate = class_getInstanceMethod([AVPlayer class], @selector(playImmediatelyAtRate:));
        if (immediate) {
            gOrigAVPlayerPlayImmediately = method_getImplementation(immediate);
            method_setImplementation(immediate, (IMP)scui_AVPlayer_playImmediatelyAtRate);
        }

#if SCUI_REPLACE_SYSTEM_ORANGE_WITH_WHITE
        SCUIReplaceClassMethod([UIColor class], @selector(systemOrangeColor), (IMP)scui_UIColor_systemOrangeColor);
        SCUIReplaceClassMethod([UIColor class], @selector(orangeColor), (IMP)scui_UIColor_orangeColor);
#endif
    });
}

__attribute__((constructor))
static void SatanabeCleanUIEntry(void) {
    @autoreleasepool {
        SCUIInstallHooks();
        dispatch_async(dispatch_get_main_queue(), ^{
            SCUIApplyCleanUI();
            [NSTimer scheduledTimerWithTimeInterval:SCUI_RESCAN_INTERVAL repeats:YES block:^(__unused NSTimer *timer) {
                SCUIApplyCleanUI();
            }];

            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                              object:nil
                                                               queue:NSOperationQueue.mainQueue
                                                          usingBlock:^(__unused NSNotification *note) {
                SCUIApplyCleanUI();
            }];
        });
    }
}
