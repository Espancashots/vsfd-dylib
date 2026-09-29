// UniversalUIInspector.m — read-only, target-agnostic UIKit/runtime diagnostics.
// Build only with Apple's SDK. No private APIs, swizzling, credential access, or patching.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>

@interface UIInspectorCore : NSObject
@property(nonatomic,strong) UIWindow *panel;
@property(nonatomic,weak) UIWindow *hostWindow;
+ (instancetype)shared;
- (void)startWhenReady;
@end

static NSString *ColorString(UIColor *c) { if (!c) return @"(nil)"; CGFloat r=0,g=0,b=0,a=0; if ([c getRed:&r green:&g blue:&b alpha:&a]) return [NSString stringWithFormat:@"rgba(%.3f, %.3f, %.3f, %.3f)",r,g,b,a]; return [c description]; }
static NSString *ViewLine(UIView *v) { return [NSString stringWithFormat:@"%@ %p frame=%@ alpha=%.2f hidden=%@ bg=%@ layerBg=%@", NSStringFromClass(v.class),v,NSStringFromCGRect(v.frame),v.alpha,v.hidden?@"YES":@"NO",ColorString(v.backgroundColor),v.layer.backgroundColor ? [(__bridge UIColor *)v.layer.backgroundColor description] : @"(nil)"]; }

@interface FloatingInspector : NSObject
@property(nonatomic,weak) UIInspectorCore *core;
@property(nonatomic,strong) UIButton *button;
- (instancetype)initWithCore:(UIInspectorCore *)core;
@end
@implementation FloatingInspector
- (instancetype)initWithCore:(UIInspectorCore *)core { if ((self=[super init])) { _core=core; _button=[UIButton buttonWithType:UIButtonTypeSystem]; _button.frame=CGRectMake(12,80,92,40); [_button setTitle:@"Inspect" forState:UIControlStateNormal]; _button.backgroundColor=[UIColor colorWithWhite:0 alpha:.82]; [_button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; _button.layer.cornerRadius=10; [_button addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside]; } return self; }
- (void)toggle:(id)sender { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Universal UI Inspector" message:@"Read-only diagnostics\nUse Export to save the current hierarchy." preferredStyle:UIAlertControllerStyleActionSheet]; [a addAction:[UIAlertAction actionWithTitle:@"Hierarchy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ [self exportHierarchy]; }]]; [a addAction:[UIAlertAction actionWithTitle:@"Classes" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ [self exportClasses]; }]]; [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]]; UIViewController *vc=self.core.hostWindow.rootViewController; while (vc.presentedViewController) vc=vc.presentedViewController; [vc presentViewController:a animated:YES completion:nil]; }
- (void)exportHierarchy { NSMutableString *s=[NSMutableString stringWithString:@"CURRENT_SUBTREE.txt\n"]; [self appendView:self.core.hostWindow depth:0 to:s]; [self write:s name:@"CURRENT_SUBTREE.txt"]; }
- (void)appendView:(UIView *)v depth:(NSUInteger)d to:(NSMutableString *)s { if (!v || d>32) return; [s appendFormat:@"%@%@\n", [@"  " stringByPaddingToLength:d*2 withString:@" " startingAtIndex:0],ViewLine(v)]; for (UIView *x in v.subviews) [self appendView:x depth:d+1 to:s]; }
- (void)exportClasses { int n=objc_getClassList(NULL,0); Class *classes=malloc(sizeof(Class)*MAX(n,0)); n=objc_getClassList(classes,n); NSMutableString *s=[NSMutableString stringWithString:@"RUNTIME_CLASSES.txt\n"]; for(int i=0;i<n;i++) [s appendFormat:@"%@ : %@\n",NSStringFromClass(classes[i]),NSStringFromClass(class_getSuperclass(classes[i]))]; free(classes); [self write:s name:@"RUNTIME_CLASSES.txt"]; }
- (void)write:(NSString *)text name:(NSString *)name { NSURL *dir=[[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"UniversalUIInspector" isDirectory:YES]; [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil]; NSURL *url=[dir URLByAppendingPathComponent:name]; [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
@end

@implementation UIInspectorCore
+ (instancetype)shared { static UIInspectorCore *x; static dispatch_once_t once; dispatch_once(&once,^{x=[self new];}); return x; }
- (void)startWhenReady { dispatch_async(dispatch_get_main_queue(),^{ [self waitForWindow:0]; }); }
- (void)waitForWindow:(NSUInteger)attempt { UIApplication *app=UIApplication.sharedApplication; UIWindow *w=nil; for (UIWindow *candidate in app.windows) if (!candidate.hidden && candidate.rootViewController) { w=candidate; break; } if (!w && attempt<100) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[self waitForWindow:attempt+1];}); return; } if (!w) return; _hostWindow=w; _panel=[UIWindow windowWithFrame:UIScreen.mainScreen.bounds]; _panel.windowLevel=UIWindowLevelAlert+1; _panel.backgroundColor=UIColor.clearColor; _panel.rootViewController=[UIViewController new]; _panel.rootViewController.view.backgroundColor=UIColor.clearColor; _panel.rootViewController.view.userInteractionEnabled=YES; _panel.hidden=NO; FloatingInspector *f=[[FloatingInspector alloc] initWithCore:self]; [_panel.rootViewController.view addSubview:f.button]; objc_setAssociatedObject(_panel, @selector(waitForWindow:), f, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end

__attribute__((constructor)) static void UniversalUIInspectorInit(void) { dispatch_async(dispatch_get_main_queue(),^{ [UIInspectorCore.shared startWhenReady]; }); }
