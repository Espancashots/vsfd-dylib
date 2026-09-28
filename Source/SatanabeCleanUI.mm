#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

static NSString * const SCUIPrefsKey = @"com.satanabe.cleanui.v4";
static const void *SCUIOriginalHiddenKey = &SCUIOriginalHiddenKey;
static const void *SCUIGlassOverlayKey = &SCUIGlassOverlayKey;
static const void *SCUIOriginalBorderWidthKey = &SCUIOriginalBorderWidthKey;
static const void *SCUIOriginalBorderColorKey = &SCUIOriginalBorderColorKey;

static NSMutableDictionary *SCUIPrefs(void) {
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:SCUIPrefsKey];
    NSMutableDictionary *p = [@{
        @"glass": @NO,
        @"videoEnabled": @YES,
        @"videoMode": @0,              // 0 = original, 1 = personalizado
        @"glassIntensity": @0.62,
        @"cardColor": @[@0.08,@0.08,@0.08,@0.58],
        @"accentColor": @[@1.0,@1.0,@1.0,@1.0],
        @"bubbleX": @0.92,
        @"bubbleY": @0.28
    } mutableCopy];
    if (saved) [p addEntriesFromDictionary:saved];
    return p;
}

static void SCUISave(NSDictionary *p) {
    [[NSUserDefaults standardUserDefaults] setObject:p forKey:SCUIPrefsKey];
}

static UIColor *SCUIColorFromArray(NSArray *a, UIColor *fallback) {
    if (![a isKindOfClass:NSArray.class] || a.count < 4) return fallback;
    return [UIColor colorWithRed:[a[0] doubleValue]
                           green:[a[1] doubleValue]
                            blue:[a[2] doubleValue]
                           alpha:[a[3] doubleValue]];
}

static NSArray *SCUIArrayFromColor(UIColor *color) {
    CGFloat r=0,g=0,b=0,a=1;
    UIColor *c = color ?: UIColor.whiteColor;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w=0;
        if ([c getWhite:&w alpha:&a]) r=g=b=w;
    }
    return @[@(r),@(g),@(b),@(a)];
}

static NSArray<UIWindow *> *SCUIWindows(void) {
    NSMutableArray *result = [NSMutableArray array];
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        [result addObjectsFromArray:ws.windows];
    }
    return result;
}

@interface SCUICustomVideoLayer : AVPlayerLayer @end
@implementation SCUICustomVideoLayer @end

static void SCUIVisitLayers(CALayer *layer, void (^block)(CALayer *)) {
    if (!layer) return;
    block(layer);
    for (CALayer *child in [layer.sublayers copy]) SCUIVisitLayers(child, block);
}

static void SCUISetHostVideosHidden(UIWindow *window, BOOL hidden) {
    SCUIVisitLayers(window.layer, ^(CALayer *layer) {
        if (![layer isKindOfClass:AVPlayerLayer.class]) return;
        if ([layer isKindOfClass:SCUICustomVideoLayer.class]) return;
        NSNumber *stored = objc_getAssociatedObject(layer, SCUIOriginalHiddenKey);
        if (!stored) {
            objc_setAssociatedObject(layer, SCUIOriginalHiddenKey, @(layer.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            stored = @(layer.hidden);
        }
        layer.hidden = hidden ? YES : stored.boolValue;
    });
}

static BOOL SCUIIsExcludedView(UIView *v) {
    return [v isKindOfClass:UILabel.class] ||
           [v isKindOfClass:UIImageView.class] ||
           [v isKindOfClass:UIControl.class] ||
           [v isKindOfClass:UIVisualEffectView.class] ||
           [v isKindOfClass:UIStackView.class] ||
           [v isKindOfClass:UIScrollView.class] ||
           [v isKindOfClass:UIWindow.class];
}

static BOOL SCUILooksLikeCard(UIView *v, UIWindow *window) {
    if (!v || v.hidden || v.alpha < 0.05 || SCUIIsExcludedView(v)) return NO;
    if (v.window != window) return NO;
    CGRect r = [v convertRect:v.bounds toView:window];
    if (r.size.width < window.bounds.size.width * 0.70) return NO;
    if (r.size.height < 58 || r.size.height > 230) return NO;
    if (r.origin.y < window.safeAreaInsets.top + 70) return NO;
    NSString *name = NSStringFromClass(v.class);
    if ([name containsString:@"SCUI"]) return NO;
    CGFloat radius = v.layer.cornerRadius;
    UIColor *bg = v.backgroundColor;
    CGFloat alpha = CGColorGetAlpha(bg.CGColor ?: UIColor.clearColor.CGColor);
    return radius >= 12.0 || alpha >= 0.18;
}

static void SCUIRemoveGlassFromView(UIView *v) {
    UIView *overlay = objc_getAssociatedObject(v, SCUIGlassOverlayKey);
    if (overlay) {
        [overlay removeFromSuperview];
        objc_setAssociatedObject(v, SCUIGlassOverlayKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
    NSNumber *bw = objc_getAssociatedObject(v, SCUIOriginalBorderWidthKey);
    id bc = objc_getAssociatedObject(v, SCUIOriginalBorderColorKey);
    if (bw) v.layer.borderWidth = bw.doubleValue;
    if ([bc isKindOfClass:UIColor.class]) v.layer.borderColor = ((UIColor *)bc).CGColor;
    else if (bc == NSNull.null) v.layer.borderColor = nil;
}

static void SCUIApplyGlassToView(UIView *v, UIColor *cardColor, UIColor *accent, CGFloat intensity) {
    if (objc_getAssociatedObject(v, SCUIGlassOverlayKey)) return;

    objc_setAssociatedObject(v, SCUIOriginalBorderWidthKey, @(v.layer.borderWidth), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (v.layer.borderColor) {
        UIColor *colorObj = [UIColor colorWithCGColor:v.layer.borderColor];
        objc_setAssociatedObject(v, SCUIOriginalBorderColorKey, colorObj, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        objc_setAssociatedObject(v, SCUIOriginalBorderColorKey, NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIBlurEffectStyle style = UIBlurEffectStyleSystemUltraThinMaterialDark;
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:style]];
    blur.userInteractionEnabled = NO;
    blur.frame = v.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blur.alpha = MAX(0.15, MIN(1.0, intensity));
    blur.layer.cornerRadius = MAX(16.0, v.layer.cornerRadius);
    blur.clipsToBounds = YES;

    UIView *tint = [[UIView alloc] initWithFrame:blur.bounds];
    tint.userInteractionEnabled = NO;
    tint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tint.backgroundColor = cardColor;
    [blur.contentView addSubview:tint];

    [v insertSubview:blur atIndex:0];
    v.layer.borderWidth = 0.55;
    v.layer.borderColor = [accent colorWithAlphaComponent:0.34].CGColor;
    objc_setAssociatedObject(v, SCUIGlassOverlayKey, blur, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void SCUIWalkViews(UIView *v, void (^block)(UIView *)) {
    if (!v) return;

    // IMPORTANT: snapshot BEFORE block(v). The block may insert/remove subviews.
    // Walking newly inserted UIVisualEffectView internals recursively can grow the
    // hierarchy indefinitely and eventually terminate the host app.
    NSArray<UIView *> *children = [v.subviews copy];
    block(v);

    // Never inspect Apple's private blur hierarchy or our injected blur descendants.
    if ([v isKindOfClass:UIVisualEffectView.class]) return;

    for (UIView *child in children) {
        if ([child isKindOfClass:UIVisualEffectView.class]) continue;
        SCUIWalkViews(child, block);
    }
}

@class SCUIOverlay;

@interface SCUIManager : NSObject
@property(nonatomic, strong) NSMutableDictionary *prefs;
@property(nonatomic, strong) NSHashTable<SCUIOverlay *> *overlays;
@property(nonatomic, strong) AVQueuePlayer *customPlayer;
@property(nonatomic, strong) AVPlayerLooper *customLooper;
@property(nonatomic, strong) NSHashTable<SCUICustomVideoLayer *> *customLayers;
@property(nonatomic, strong) NSTimer *timer;
+ (instancetype)shared;
- (void)install;
- (void)apply;
- (void)reloadCustomVideo;
- (NSURL *)customVideoURL;
@end

@interface SCUIOverlay : UIView <UIDocumentPickerDelegate, UIColorPickerViewControllerDelegate>
@property(nonatomic, strong) UIButton *bubble;
@property(nonatomic, strong) UIVisualEffectView *panel;
@property(nonatomic, strong) UIStackView *stack;
@property(nonatomic, strong) UISwitch *glassSwitch;
@property(nonatomic, strong) UISwitch *videoSwitch;
@property(nonatomic, strong) UISegmentedControl *videoMode;
@property(nonatomic, strong) UISlider *glassSlider;
@property(nonatomic) NSInteger colorTarget;
- (void)refreshControls;
@end

@implementation SCUIManager

+ (instancetype)shared {
    static SCUIManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [SCUIManager new]; });
    return m;
}

- (instancetype)init {
    if ((self = [super init])) {
        _prefs = SCUIPrefs();
        _overlays = [NSHashTable weakObjectsHashTable];
        _customLayers = [NSHashTable weakObjectsHashTable];
    }
    return self;
}

- (NSURL *)customVideoURL {
    NSURL *dir = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                          inDomains:NSUserDomainMask] firstObject];
    dir = [dir URLByAppendingPathComponent:@"SatanabeCleanUI" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir URLByAppendingPathComponent:@"background.mp4"];
}

- (void)install {
    for (UIWindow *window in SCUIWindows()) {
        if (window.hidden || window.windowLevel != UIWindowLevelNormal) continue;
        BOOL found = NO;
        for (UIView *v in window.subviews) {
            if ([v isKindOfClass:SCUIOverlay.class]) { found = YES; [window bringSubviewToFront:v]; break; }
        }
        if (!found) {
            SCUIOverlay *o = [[SCUIOverlay alloc] initWithFrame:window.bounds];
            o.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [window addSubview:o];
            [self.overlays addObject:o];
        }
    }
    [self apply];
}

- (void)reloadCustomVideo {
    [self.customPlayer pause];
    self.customPlayer = nil;
    self.customLooper = nil;

    NSURL *url = [self customVideoURL];
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        [self apply];
        return;
    }

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    AVQueuePlayer *player = [AVQueuePlayer queuePlayerWithItems:@[]];
    player.muted = YES;
    self.customPlayer = player;
    self.customLooper = [AVPlayerLooper playerLooperWithPlayer:player templateItem:item];
    [player play];
    [self apply];
}

- (void)apply {
    BOOL glass = [self.prefs[@"glass"] boolValue];
    BOOL videoEnabled = [self.prefs[@"videoEnabled"] boolValue];
    NSInteger videoMode = [self.prefs[@"videoMode"] integerValue];
    CGFloat intensity = [self.prefs[@"glassIntensity"] doubleValue];
    UIColor *card = SCUIColorFromArray(self.prefs[@"cardColor"], [UIColor colorWithWhite:0.08 alpha:0.58]);
    UIColor *accent = SCUIColorFromArray(self.prefs[@"accentColor"], UIColor.whiteColor);

    for (UIWindow *window in SCUIWindows()) {
        if (window.hidden || window.windowLevel != UIWindowLevelNormal) continue;

        BOOL hideHostVideo = !videoEnabled || videoMode == 1;
        SCUISetHostVideosHidden(window, hideHostVideo);

        SCUICustomVideoLayer *custom = nil;
        for (CALayer *l in self.customLayers) if (l.superlayer == window.layer) { custom = l; break; }

        if (videoEnabled && videoMode == 1 && self.customPlayer) {
            if (!custom) {
                custom = [SCUICustomVideoLayer playerLayerWithPlayer:self.customPlayer];
                custom.videoGravity = AVLayerVideoGravityResizeAspectFill;
                [window.layer insertSublayer:custom atIndex:0];
                [self.customLayers addObject:custom];
            }
            custom.frame = window.bounds;
            custom.hidden = NO;
            if (self.customPlayer.timeControlStatus != AVPlayerTimeControlStatusPlaying) [self.customPlayer play];
        } else {
            custom.hidden = YES;
        }

        SCUIWalkViews(window, ^(UIView *v) {
            for (SCUIOverlay *overlay in self.overlays) {
                if (v == overlay || [v isDescendantOfView:overlay]) return;
            }
            if (glass && SCUILooksLikeCard(v, window)) {
                SCUIApplyGlassToView(v, card, accent, intensity);
            } else if (!glass) {
                SCUIRemoveGlassFromView(v);
            }
        });
    }

    for (SCUIOverlay *o in self.overlays) [o refreshControls];
}

@end

@implementation SCUIOverlay

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = YES;

        _bubble = [UIButton buttonWithType:UIButtonTypeCustom];
        [_bubble setTitle:@"S" forState:UIControlStateNormal];
        [_bubble setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        _bubble.titleLabel.font = [UIFont boldSystemFontOfSize:20];
        _bubble.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.78];
        _bubble.layer.cornerRadius = 28;
        _bubble.layer.borderWidth = 0.8;
        _bubble.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.75].CGColor;
        _bubble.layer.shadowColor = UIColor.blackColor.CGColor;
        _bubble.layer.shadowOpacity = 0.28;
        _bubble.layer.shadowRadius = 8;
        [_bubble addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
        [_bubble addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
        [self addSubview:_bubble];
    }
    return self;
}

- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e {
    if ([self.bubble pointInside:[self.bubble convertPoint:p fromView:self] withEvent:e]) return YES;
    if (self.panel && !self.panel.hidden &&
        [self.panel pointInside:[self.panel convertPoint:p fromView:self] withEvent:e]) return YES;
    return NO;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!self.bubble.superview) return;
    CGFloat d = 56;
    if (CGRectIsEmpty(self.bubble.frame)) {
        CGFloat x = self.bounds.size.width - d - 14;
        CGFloat y = self.safeAreaInsets.top + 150;
        self.bubble.frame = CGRectMake(x, y, d, d);
    }
    self.bubble.layer.cornerRadius = d/2;
}

- (UILabel *)label:(NSString *)text size:(CGFloat)size {
    UILabel *l = [UILabel new];
    l.text = text;
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont systemFontOfSize:size weight:UIFontWeightMedium];
    l.numberOfLines = 0;
    [self.stack addArrangedSubview:l];
    return l;
}

- (UIView *)rowWithTitle:(NSString *)title control:(UIView *)control {
    UILabel *l = [UILabel new];
    l.text = title;
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[l, control]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.distribution = UIStackViewDistributionEqualSpacing;
    [self.stack addArrangedSubview:row];
    return row;
}

- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    b.layer.cornerRadius = 12;
    b.layer.borderWidth = 0.5;
    b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.22].CGColor;
    [b.heightAnchor constraintEqualToConstant:42].active = YES;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)buildPanel {
    UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
    self.panel = [[UIVisualEffectView alloc] initWithEffect:effect];
    self.panel.layer.cornerRadius = 24;
    self.panel.clipsToBounds = YES;
    self.panel.layer.borderWidth = 0.65;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;
    [self addSubview:self.panel];

    CGFloat w = MIN(360, self.bounds.size.width - 28);
    CGFloat h = MIN(590, self.bounds.size.height - self.safeAreaInsets.top - self.safeAreaInsets.bottom - 50);
    self.panel.frame = CGRectMake((self.bounds.size.width-w)/2,
                                  self.safeAreaInsets.top + 18, w, h);

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectInset(self.panel.bounds, 16, 16)];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.panel.contentView addSubview:scroll];

    self.stack = [UIStackView new];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 13;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [self.stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [self.stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [self.stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];

    UILabel *title = [self label:@"SATANABE • VISUAL" size:20];
    title.font = [UIFont boldSystemFontOfSize:20];
    UILabel *sub = [self label:@"Apenas aparência. Não altera keys, Supabase ou patches." size:11];
    sub.textColor = [UIColor colorWithWhite:1 alpha:0.58];

    self.glassSwitch = [UISwitch new];
    [self.glassSwitch addTarget:self action:@selector(glassChanged:) forControlEvents:UIControlEventValueChanged];
    [self rowWithTitle:@"Liquid Glass" control:self.glassSwitch];

    self.glassSlider = [UISlider new];
    self.glassSlider.minimumValue = 0.15;
    self.glassSlider.maximumValue = 1.0;
    [self.glassSlider addTarget:self action:@selector(glassIntensityChanged:) forControlEvents:UIControlEventValueChanged];
    [self label:@"Intensidade do Glass" size:13];
    [self.stack addArrangedSubview:self.glassSlider];

    [self.stack addArrangedSubview:[self button:@"Cor dos cards" action:@selector(pickCardColor)]];
    [self.stack addArrangedSubview:[self button:@"Cor do destaque / bordas" action:@selector(pickAccentColor)]];

    self.videoSwitch = [UISwitch new];
    [self.videoSwitch addTarget:self action:@selector(videoChanged:) forControlEvents:UIControlEventValueChanged];
    [self rowWithTitle:@"Vídeo de fundo" control:self.videoSwitch];

    [self label:@"Fonte do vídeo" size:13];
    self.videoMode = [[UISegmentedControl alloc] initWithItems:@[@"Original", @"Personalizado"]];
    [self.videoMode addTarget:self action:@selector(videoModeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:self.videoMode];

    [self.stack addArrangedSubview:[self button:@"Escolher / trocar vídeo" action:@selector(chooseVideo)]];
    [self.stack addArrangedSubview:[self button:@"Restaurar visual original" action:@selector(resetVisual)]];

    UIButton *close = [self button:@"Fechar" action:@selector(togglePanel)];
    [self.stack addArrangedSubview:close];

    [self refreshControls];
}

- (void)refreshControls {
    SCUIManager *m = SCUIManager.shared;
    self.glassSwitch.on = [m.prefs[@"glass"] boolValue];
    self.videoSwitch.on = [m.prefs[@"videoEnabled"] boolValue];
    self.videoMode.selectedSegmentIndex = [m.prefs[@"videoMode"] integerValue];
    self.glassSlider.value = [m.prefs[@"glassIntensity"] floatValue];

    UIColor *accent = SCUIColorFromArray(m.prefs[@"accentColor"], UIColor.whiteColor);
    self.bubble.layer.borderColor = [accent colorWithAlphaComponent:self.panel && !self.panel.hidden ? 1.0 : 0.72].CGColor;
    self.bubble.layer.borderWidth = self.panel && !self.panel.hidden ? 1.15 : 0.75;
}

- (void)togglePanel {
    if (!self.panel) { [self buildPanel]; self.panel.hidden = YES; }
    self.panel.hidden = !self.panel.hidden;
    [self refreshControls];
    if (!self.panel.hidden) [self bringSubviewToFront:self.panel];
}

- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self];
    CGPoint c = self.bubble.center;
    c.x += t.x; c.y += t.y;
    CGFloat r = self.bubble.bounds.size.width/2;
    c.x = MAX(r+8, MIN(self.bounds.size.width-r-8, c.x));
    c.y = MAX(self.safeAreaInsets.top+r+8, MIN(self.bounds.size.height-self.safeAreaInsets.bottom-r-8, c.y));
    self.bubble.center = c;
    [g setTranslation:CGPointZero inView:self];
}

- (void)glassChanged:(UISwitch *)s {
    SCUIManager.shared.prefs[@"glass"] = @(s.on);
    SCUISave(SCUIManager.shared.prefs);
    [SCUIManager.shared apply];
}
- (void)glassIntensityChanged:(UISlider *)s {
    SCUIManager.shared.prefs[@"glassIntensity"] = @(s.value);
    SCUISave(SCUIManager.shared.prefs);
    // Remove old overlays so the new intensity is visible immediately.
    for (UIWindow *w in SCUIWindows()) {
        SCUIWalkViews(w, ^(UIView *v){ SCUIRemoveGlassFromView(v); });
    }
    [SCUIManager.shared apply];
}
- (void)videoChanged:(UISwitch *)s {
    SCUIManager.shared.prefs[@"videoEnabled"] = @(s.on);
    SCUISave(SCUIManager.shared.prefs);
    [SCUIManager.shared apply];
}
- (void)videoModeChanged:(UISegmentedControl *)s {
    SCUIManager.shared.prefs[@"videoMode"] = @(s.selectedSegmentIndex);
    SCUISave(SCUIManager.shared.prefs);
    if (s.selectedSegmentIndex == 1) [SCUIManager.shared reloadCustomVideo];
    else [SCUIManager.shared apply];
}

- (void)pickCardColor { self.colorTarget = 0; [self showColorPickerForKey:@"cardColor"]; }
- (void)pickAccentColor { self.colorTarget = 1; [self showColorPickerForKey:@"accentColor"]; }

- (void)showColorPickerForKey:(NSString *)key {
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.delegate = self;
    picker.supportsAlpha = YES;
    picker.selectedColor = SCUIColorFromArray(SCUIManager.shared.prefs[key], UIColor.whiteColor);
    UIViewController *vc = self.window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    [vc presentViewController:picker animated:YES completion:nil];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    NSString *key = self.colorTarget == 0 ? @"cardColor" : @"accentColor";
    SCUIManager.shared.prefs[key] = SCUIArrayFromColor(viewController.selectedColor);
    SCUISave(SCUIManager.shared.prefs);
    if (self.colorTarget == 0) {
        for (UIWindow *w in SCUIWindows()) SCUIWalkViews(w, ^(UIView *v){ SCUIRemoveGlassFromView(v); });
    }
    [SCUIManager.shared apply];
}

- (void)chooseVideo {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeMovie, UTTypeMPEG4Movie] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    UIViewController *vc = self.window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    [vc presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *src = urls.firstObject;
    if (!src) return;
    NSURL *dst = [SCUIManager.shared customVideoURL];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm removeItemAtURL:dst error:nil];
    NSError *error = nil;
    BOOL access = [src startAccessingSecurityScopedResource];
    [fm copyItemAtURL:src toURL:dst error:&error];
    if (access) [src stopAccessingSecurityScopedResource];
    if (!error) {
        SCUIManager.shared.prefs[@"videoMode"] = @1;
        SCUIManager.shared.prefs[@"videoEnabled"] = @YES;
        SCUISave(SCUIManager.shared.prefs);
        [SCUIManager.shared reloadCustomVideo];
    }
    (void)controller;
}

- (void)resetVisual {
    SCUIManager *m = SCUIManager.shared;
    m.prefs[@"glass"] = @NO;
    m.prefs[@"videoEnabled"] = @YES;
    m.prefs[@"videoMode"] = @0;
    SCUISave(m.prefs);
    for (UIWindow *w in SCUIWindows()) {
        SCUIWalkViews(w, ^(UIView *v){ SCUIRemoveGlassFromView(v); });
        SCUISetHostVideosHidden(w, NO);
    }
    [m apply];
}

@end

__attribute__((constructor))
static void SCUIStart(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        SCUIManager *m = SCUIManager.shared;
        [m install];

        for (NSNotificationName n in @[UIApplicationDidBecomeActiveNotification,
                                      UIWindowDidBecomeKeyNotification,
                                      UISceneDidActivateNotification]) {
            [[NSNotificationCenter defaultCenter] addObserverForName:n object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                    [m install];
                }];
        }

        m.timer = [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(__unused NSTimer *timer) {
            // Only make sure the floating control survives view/window changes.
            // Do not continuously rebuild the host visual hierarchy.
            for (UIWindow *window in SCUIWindows()) {
                if (window.hidden || window.windowLevel != UIWindowLevelNormal) continue;
                BOOL found = NO;
                for (UIView *v in window.subviews) {
                    if ([v isKindOfClass:SCUIOverlay.class]) {
                        found = YES;
                        [window bringSubviewToFront:v];
                        break;
                    }
                }
                if (!found) {
                    SCUIOverlay *o = [[SCUIOverlay alloc] initWithFrame:window.bounds];
                    o.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                    [window addSubview:o];
                    [m.overlays addObject:o];
                }
            }
        }];

        if ([m.prefs[@"videoMode"] integerValue] == 1) [m reloadCustomVideo];
    });
}
