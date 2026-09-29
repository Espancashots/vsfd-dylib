// UniversalUIInspector.m — generic, read-only UIKit/runtime diagnostics.
// Public APIs only. No swizzling, patching, credential access, or target-specific classes.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <zlib.h>

static NSString * const UIID = @"UniversalUIInspector";
static const NSUInteger kMaxStartupDepth = 8;
static const NSUInteger kMaxStartupNodes = 2000;

static NSString *ColorString(UIColor *c) {
    if (!c) return @"(nil)";
    CGFloat r=0,g=0,b=0,a=0;
    if ([c getRed:&r green:&g blue:&b alpha:&a]) return [NSString stringWithFormat:@"rgba(%.3f, %.3f, %.3f, %.3f)",r,g,b,a];
    CGFloat w=0;
    if ([c getWhite:&w alpha:&a]) return [NSString stringWithFormat:@"gray(%.3f, %.3f)",w,a];
    return c.description;
}
static NSString *LayerColorString(CGColorRef color) { return color ? ColorString([UIColor colorWithCGColor:color]) : @"(nil)"; }
static NSString *ViewLine(UIView *v) {
    return [NSString stringWithFormat:@"%@ %p frame=%@ bounds=%@ alpha=%.2f hidden=%@ bg=%@ layerBg=%@", NSStringFromClass(v.class),v,NSStringFromCGRect(v.frame),NSStringFromCGRect(v.bounds),v.alpha,v.hidden?@"YES":@"NO",ColorString(v.backgroundColor),LayerColorString(v.layer.backgroundColor)];
}

static NSURL *ReportsDirectory(void) {
    NSURL *documents = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL *dir = [documents URLByAppendingPathComponent:UIID isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}
static void WriteReport(NSString *name, NSString *text) {
    NSURL *url = [ReportsDirectory() URLByAppendingPathComponent:name];
    [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static NSString *ReportPath(NSString *name) { return [[ReportsDirectory() URLByAppendingPathComponent:name] path]; }

// Small uncompressed ZIP writer: creates a standards-compliant ZIP without third-party code.
static NSData *ZipData(NSDictionary<NSString *,NSData *> *files) {
    NSMutableData *zip=[NSMutableData data]; NSMutableArray *central=[NSMutableArray array]; NSUInteger offset=0;
    for (NSString *name in files) {
        NSData *data=files[name]; NSData *nameData=[name dataUsingEncoding:NSUTF8StringEncoding]; uLong crc=crc32(0,(const Bytef *)data.bytes,(uInt)data.length); uint32_t local[5]={0x04034b50,20,0,0,(uint32_t)crc};
        uint32_t sizes[2]={(uint32_t)data.length,(uint32_t)data.length}; [zip appendBytes:local length:sizeof(local)]; [zip appendBytes:sizes length:sizeof(sizes)]; uint16_t nl=(uint16_t)nameData.length; [zip appendBytes:&nl length:2]; uint16_t extra=0; [zip appendBytes:&extra length:2]; [zip appendData:nameData]; [zip appendData:data];
        NSMutableData *c=[NSMutableData data]; uint32_t ch[3]={0x02014b50,0x0314,20}; [c appendBytes:ch length:sizeof(ch)]; uint32_t flags[3]={0,0,(uint32_t)crc}; [c appendBytes:flags length:sizeof(flags)]; [c appendBytes:sizes length:sizeof(sizes)]; [c appendBytes:&nl length:2]; [c appendBytes:&extra length:2]; uint16_t comment=0,disk=0,intattr=0; uint32_t ext=0; [c appendBytes:&comment length:2]; [c appendBytes:&disk length:2]; [c appendBytes:&intattr length:2]; [c appendBytes:&ext length:4]; uint32_t off=(uint32_t)offset; [c appendBytes:&off length:4]; [c appendData:nameData]; [central addObject:c]; offset=zip.length;
    }
    NSUInteger centralOffset=zip.length; for (NSData *c in central) [zip appendData:c]; uint32_t end[4]={0x06054b50,(uint32_t)central.count,(uint32_t)central.count,(uint32_t)(zip.length-centralOffset),(uint32_t)centralOffset}; [zip appendBytes:end length:sizeof(end)]; return zip;
}

static void AppendViewTree(UIView *v, NSUInteger depth, NSUInteger *nodes, NSMutableString *out) {
    if (!v || depth>kMaxStartupDepth || *nodes>=kMaxStartupNodes) return; (*nodes)++;
    [out appendFormat:@"%@%@\n", [@"" stringByPaddingToLength:depth*2 withString:@" " startingAtIndex:0], ViewLine(v)];
    for (UIView *child in [v.subviews copy]) AppendViewTree(child,depth+1,nodes,out);
}
static UIWindow *FindHostWindow(UIWindowScene **sceneOut, NSString **evidence) {
    UIApplication *app=UIApplication.sharedApplication; NSMutableString *log=[NSMutableString string]; UIWindow *best=nil; UIWindowScene *bestScene=nil;
    for (UIScene *s in app.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue; UIWindowScene *ws=(UIWindowScene *)s;
        [log appendFormat:@"scene=%p state=%ld windows=%lu\n",ws,(long)ws.activationState,(unsigned long)ws.windows.count];
        if (ws.activationState!=UISceneActivationStateForegroundActive && ws.activationState!=UISceneActivationStateForegroundInactive) continue;
        for (UIWindow *w in ws.windows) { [log appendFormat:@"  window=%p hidden=%@ level=%.1f root=%@\n",w,w.hidden?@"YES":@"NO",w.windowLevel,w.rootViewController?NSStringFromClass(w.rootViewController.class):@"(nil)"]; if (!w.hidden && w.rootViewController && w.windowLevel==UIWindowLevelNormal && w.bounds.size.width>0 && w.bounds.size.height>0) { best=w; bestScene=ws; break; } }
        if (best) break;
    }
    if (sceneOut) *sceneOut=bestScene; if (evidence) *evidence=log; return best;
}

@interface InspectorWindow : UIWindow @end
@implementation InspectorWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)event { UIView *hit=[super hitTest:p withEvent:event]; if (hit==self || hit==self.rootViewController.view) return nil; return hit; }
@end

@class InspectorCore;
@interface InspectorRootController : UIViewController @property(nonatomic,weak) InspectorCore *core; @end
@interface InspectorButton : UIButton @property(nonatomic,weak) InspectorCore *core; @end


@interface SessionCapture : NSObject
@property(nonatomic,strong) NSString *sessionID;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *snapshots;
@property(nonatomic) BOOL active;
+ (instancetype)shared;
- (void)start:(UIWindow *)host;
- (void)capture:(UIWindow *)host label:(NSString *)label inspectorWindow:(UIWindow *)inspector;
- (void)stop;
- (NSURL *)stageSession:(UIWindow *)host error:(NSError **)error;
@end

static void SessionViewSnapshot(UIView *v, NSUInteger depth, NSUInteger *nodes, NSUInteger limit, NSMutableArray *out, NSHashTable *seen) {
    if (!v || depth>8 || *nodes>=limit || [seen containsObject:v]) return;
    [seen addObject:v]; (*nodes)++;
    NSMutableDictionary *d=[@{ @"class":NSStringFromClass(v.class), @"superclass":NSStringFromClass(v.superclass), @"address":[NSString stringWithFormat:@"%p",v], @"frame":NSStringFromCGRect(v.frame), @"bounds":NSStringFromCGRect(v.bounds), @"alpha":@(v.alpha), @"hidden":@(v.hidden), @"opaque":@(v.opaque), @"backgroundColor":ColorString(v.backgroundColor), @"layerClass":NSStringFromClass(v.layer.class), @"cornerRadius":@(v.layer.cornerRadius), @"borderWidth":@(v.layer.borderWidth), @"borderColor":LayerColorString(v.layer.borderColor), @"sublayerCount":@(v.layer.sublayers.count), @"accessibilityIdentifier":v.accessibilityIdentifier ?: @"", @"superview":v.superview ? NSStringFromClass(v.superview.class) : @"(nil)" } mutableCopy];
    if ([v isKindOfClass:UIScrollView.class]) { UIScrollView *sv=(UIScrollView *)v; d[@"contentOffset"]=NSStringFromCGPoint(sv.contentOffset); d[@"contentSize"]=NSStringFromCGSize(sv.contentSize); }
    if ([v isKindOfClass:UICollectionViewCell.class] || [v isKindOfClass:UITableViewCell.class]) d[@"visibleCellClass"]=NSStringFromClass(v.class);
    [out addObject:d]; for(UIView *child in [v.subviews copy]) SessionViewSnapshot(child,depth+1,nodes,limit,out,seen);
}
static void SessionControllerSnapshot(UIViewController *vc, NSUInteger depth, NSUInteger *nodes, NSMutableArray *out, NSHashTable *seen) {
    if(!vc||depth>16||*nodes>=500||[seen containsObject:vc]) return; [seen addObject:vc]; (*nodes)++;
    NSMutableDictionary *d=[@{ @"class":NSStringFromClass(vc.class), @"superclass":NSStringFromClass(vc.superclass), @"address":[NSString stringWithFormat:@"%p",vc], @"childCount":@(vc.childViewControllers.count), @"presented":vc.presentedViewController ? NSStringFromClass(vc.presentedViewController.class) : @"(nil)" } mutableCopy];
    if([vc isKindOfClass:UINavigationController.class]) d[@"navigationStack"]=[(UINavigationController *)vc.viewControllers valueForKeyPath:@"class.description"] ?: @[];
    if([vc isKindOfClass:UITabBarController.class]) d[@"selectedTab"]=(NSStringFromClass(((UITabBarController *)vc).selectedViewController.class) ?: @"(nil)");
    [out addObject:d]; for(UIViewController *c in vc.childViewControllers) SessionControllerSnapshot(c,depth+1,nodes,out,seen); SessionControllerSnapshot(vc.presentedViewController,depth+1,nodes,out,seen);
}
@implementation SessionCapture
+ (instancetype)shared { static SessionCapture *x; static dispatch_once_t once; dispatch_once(&once,^{x=[self new];}); return x; }
- (instancetype)init { if((self=[super init])) _snapshots=[NSMutableArray array]; return self; }
- (void)start:(UIWindow *)host { NSAssert(NSThread.isMainThread, @"UIKit capture must start on main"); self.sessionID=[NSUUID UUID].UUIDString; self.snapshots=[NSMutableArray array]; self.active=YES; [self capture:host label:@"session-start" inspectorWindow:nil]; }
- (void)capture:(UIWindow *)host label:(NSString *)label inspectorWindow:(UIWindow *)inspector { if(!NSThread.isMainThread||!host||!self.active)return; NSUInteger vn=0,cn=0; NSMutableArray *views=[NSMutableArray array],*controllers=[NSMutableArray array]; SessionViewSnapshot(host,0,&vn,2000,views,[NSHashTable weakObjectsHashTable]); SessionControllerSnapshot(host.rootViewController,0,&cn,controllers,[NSHashTable weakObjectsHashTable]); NSMutableDictionary *snap=[@{ @"sessionID":self.sessionID ?: @"", @"captureID":[NSUUID UUID].UUIDString, @"timestamp":[NSDate date].description, @"label":label ?: @"", @"scene":host.windowScene ? host.windowScene.session.persistentIdentifier : @"", @"hostWindow":[NSString stringWithFormat:@"%p",host], @"views":views, @"controllers":controllers, @"truncated":@(vn>=2000||cn>=500), @"viewCount":@(vn), @"controllerCount":@(cn) } mutableCopy];
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:host.bounds.size]; UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx){ [host drawViewHierarchyInRect:host.bounds afterScreenUpdates:NO]; }]; snap[@"screenshotData"]=UIImagePNGRepresentation(image) ?: [NSData data];
    NSDictionary *last=self.snapshots.lastObject; if(last && [last[@"views"] isEqual:views] && [last[@"controllers"] isEqual:controllers] && [last[@"label"] isEqual:label]) return; [self.snapshots addObject:snap];
}
- (void)stop { self.active=NO; }
- (NSURL *)stageSession:(UIWindow *)host error:(NSError **)error { if(NSThread.isMainThread){[self capture:host label:@"export" inspectorWindow:nil];} NSURL *base=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@",self.sessionID ?: [NSUUID UUID].UUIDString]] isDirectory:YES]; [[NSFileManager defaultManager] createDirectoryAtURL:base withIntermediateDirectories:YES attributes:nil error:error]; if(error&&*error)return nil; [[NSFileManager defaultManager] createDirectoryAtURL:[base URLByAppendingPathComponent:@"Screens"] withIntermediateDirectories:YES attributes:nil error:nil]; NSMutableArray *index=[NSMutableArray array]; dispatch_sync(dispatch_get_main_queue(),^{ for(NSDictionary *snap in self.snapshots){ NSString *cid=snap[@"captureID"]; NSURL *dir=[[base URLByAppendingPathComponent:@"Screens"] URLByAppendingPathComponent:cid isDirectory:YES]; [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil]; NSMutableDictionary *copy=[snap mutableCopy]; NSData *png=copy[@"screenshotData"]; [copy removeObjectForKey:@"screenshotData"]; [copy removeObjectForKey:@"views"]; [copy removeObjectForKey:@"controllers"]; [index addObject:copy]; [NSJSONSerialization dataWithJSONObject:snap[@"views"] options:NSJSONWritingPrettyPrinted error:nil]; [[NSJSONSerialization dataWithJSONObject:snap[@"views"] options:NSJSONWritingPrettyPrinted error:nil] writeToURL:[dir URLByAppendingPathComponent:@"views.json"] atomically:YES]; [[NSJSONSerialization dataWithJSONObject:snap[@"controllers"] options:NSJSONWritingPrettyPrinted error:nil] writeToURL:[dir URLByAppendingPathComponent:@"controllers.json"] atomically:YES]; [png writeToURL:[dir URLByAppendingPathComponent:@"screenshot.png"] atomically:YES]; } }); NSData *idx=[NSJSONSerialization dataWithJSONObject:@{ @"sessionID":self.sessionID ?: @"", @"snapshotCount":@(index.count), @"snapshots":index, @"coverage":"Observed screens only; not 100% app coverage." } options:NSJSONWritingPrettyPrinted error:error]; [idx writeToURL:[base URLByAppendingPathComponent:@"SESSION_INDEX.json"] options:NSDataWritingAtomic error:error]; [@"This session records screens actually observed and captured. It does not claim full app coverage.\n" writeToURL:[base URLByAppendingPathComponent:@"COVERAGE_REPORT.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil]; return base; }
@end

@interface InspectorCore : NSObject <UIDocumentPickerDelegate>
@property(nonatomic,strong) InspectorWindow *window;
@property(nonatomic,strong) InspectorRootController *root;
@property(nonatomic,strong) InspectorButton *button;
@property(nonatomic,weak) UIWindow *hostWindow;
@property(nonatomic,weak) UIWindowScene *scene;
@property(nonatomic,strong) NSMutableString *startup;
@property(nonatomic) BOOL started;
@property(nonatomic,strong) NSURL *selectedFolder;
+ (instancetype)shared;
- (void)start;
- (void)showMenu;
- (void)exportReports;
@end

@implementation InspectorButton
- (instancetype)initWithCore:(InspectorCore *)core { if((self=[super initWithFrame:CGRectMake(0,0,56,56)])){_core=core; self.accessibilityLabel=@"Universal UI Inspector"; self.backgroundColor=[UIColor colorWithRed:.05 green:.25 blue:.85 alpha:.96]; self.layer.cornerRadius=28; self.layer.borderWidth=2; self.layer.borderColor=UIColor.whiteColor.CGColor; self.layer.shadowColor=UIColor.blackColor.CGColor; self.layer.shadowOpacity=.45; self.layer.shadowRadius=5; [self setTitle:@"UI" forState:UIControlStateNormal]; [self setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; self.titleLabel.font=[UIFont boldSystemFontOfSize:15]; [self addTarget:self action:@selector(open:) forControlEvents:UIControlEventTouchUpInside]; UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]; [self addGestureRecognizer:pan]; } return self; }
- (void)open:(id)sender { [_core showMenu]; }
- (void)drag:(UIPanGestureRecognizer *)g { UIView *v=self; CGPoint t=[g translationInView:v.superview]; if(g.state==UIGestureRecognizerStateChanged){CGPoint c=v.center; c.x+=t.x;c.y+=t.y; UIEdgeInsets insets=v.superview.safeAreaInsets; CGFloat r=28; c.x=MAX(insets.left+r,MIN(v.superview.bounds.size.width-insets.right-r,c.x)); c.y=MAX(insets.top+r,MIN(v.superview.bounds.size.height-insets.bottom-r,c.y)); v.center=c; [g setTranslation:CGPointZero inView:v.superview];} }
@end

@implementation InspectorRootController
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; if(!self.core.button.superview) return; UIEdgeInsets insets=self.view.safeAreaInsets; if(CGRectIsEmpty(self.core.button.frame)||self.core.button.center.x<1){self.core.button.frame=CGRectMake(self.view.bounds.size.width-insets.right-70,insets.top+24,56,56);} else {CGPoint c=self.core.button.center; CGFloat r=28; c.x=MAX(insets.left+r,MIN(self.view.bounds.size.width-insets.right-r,c.x)); c.y=MAX(insets.top+r,MIN(self.view.bounds.size.height-insets.bottom-r,c.y)); self.core.button.center=c;} }
@end

@implementation InspectorCore
+ (instancetype)shared { static InspectorCore *x; static dispatch_once_t once; dispatch_once(&once,^{x=[self new];}); return x; }
- (instancetype)init { if((self=[super init])){_startup=[NSMutableString stringWithFormat:@"UniversalUIInspector startup %@\n",[NSDate date]];} return self; }
- (void)start { if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self start];});return;} if(self.started && self.window.superview)return; UIWindowScene *scene=nil; NSString *evidence=nil; UIWindow *host=FindHostWindow(&scene,&evidence); [self.startup appendFormat:@"Discovery:\n%@",evidence ?: @"(none)"]; if(!host||!scene){[self.startup appendFormat:@"ERROR: no foreground usable host window\n"]; [self writeStartupReports]; return;} self.hostWindow=host; self.scene=scene; self.started=YES; self.root=[InspectorRootController new]; self.root.core=self; self.window=[[InspectorWindow alloc] initWithWindowScene:scene]; self.window.frame=scene.coordinateSpace.bounds; self.window.windowLevel=UIWindowLevelAlert+1; self.window.backgroundColor=UIColor.clearColor; self.window.opaque=NO; self.window.rootViewController=self.root; self.button=[[InspectorButton alloc] initWithCore:self]; [self.root.view addSubview:self.button]; self.window.hidden=NO; [self.root viewDidLayoutSubviews]; [self.startup appendFormat:@"Host window: %p %@\nScene: %p state=%ld\nOverlay created: %p visible=%@ button=%@\n",host,NSStringFromClass(host.class),scene,(long)scene.activationState,self.window,self.window.hidden?@"NO":@"YES",self.button]; [self writeStartupReports]; }
- (void)writeStartupReports { if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self writeStartupReports];});return;} NSMutableString *tree=[NSMutableString stringWithString:@"STARTUP_VIEW_TREE.txt\n"]; NSUInteger nodes=0; AppendViewTree(self.hostWindow,0,&nodes,tree); [self.startup appendFormat:@"Startup tree nodes: %lu depth limit: %lu\n",(unsigned long)nodes,(unsigned long)kMaxStartupDepth]; NSString *boot=self.startup.copy; NSString *runtime=[NSString stringWithFormat:@"Runtime report %@\nloaded images: %u\nmain image: %s\ninspector window: %p\nhost window: %p\n",[NSDate date],_dyld_image_count(),_dyld_get_image_name(0) ?: "(nil)",self.window,self.hostWindow]; dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{WriteReport(@"BOOT_DIAGNOSTICS.txt",boot);WriteReport(@"RUNTIME_STARTUP_REPORT.txt",runtime);WriteReport(@"STARTUP_VIEW_TREE.txt",tree);}); }
- (UIViewController *)presenter { UIViewController *v=self.hostWindow.rootViewController; while(v.presentedViewController)v=v.presentedViewController; return v; }
- (NSString *)hierarchy { NSMutableString *s=[NSMutableString stringWithString:@"CURRENT_VIEW_HIERARCHY.txt\n"]; NSUInteger n=0; AppendViewTree(self.hostWindow,0,&n,s); return s; }
- (NSString *)controllers { NSMutableString *s=[NSMutableString stringWithString:@"CURRENT_CONTROLLERS.txt\n"]; UIViewController *v=self.hostWindow.rootViewController; [s appendFormat:@"root=%@\n",NSStringFromClass(v.class)]; while(v){[s appendFormat:@"%@ presented=%@ children=%lu\n",NSStringFromClass(v.class),v.presentedViewController?NSStringFromClass(v.presentedViewController.class):@"(nil)",(unsigned long)v.childViewControllers.count]; v=v.presentedViewController;} return s; }
- (NSString *)classes { int n=objc_getClassList(NULL,0); Class *cs=(Class *)malloc(sizeof(Class)*MAX(n,0)); n=objc_getClassList(cs,n); NSMutableString *s=[NSMutableString stringWithString:@"RUNTIME_CLASSES.txt\n"]; for(int i=0;i<n;i++){ Class c=cs[i]; [s appendFormat:@"%@ : %@\n",NSStringFromClass(c),NSStringFromClass(class_getSuperclass(c))]; unsigned mc=0; Method *ms=class_copyMethodList(c,&mc); for(unsigned j=0;j<mc;j++){Method m=ms[j];[s appendFormat:@"  instance %@ %p %s\n",NSStringFromSelector(method_getName(m)),method_getImplementation(m),method_getTypeEncoding(m)];} free(ms); unsigned pc=0; Method *pms=class_copyMethodList(object_getClass(c),&pc); for(unsigned j=0;j<pc;j++){Method m=pms[j];[s appendFormat:@"  class %@ %p %s\n",NSStringFromSelector(method_getName(m)),method_getImplementation(m),method_getTypeEncoding(m)];} free(pms); unsigned props=0; objc_property_t *ps=class_copyPropertyList(c,&props); for(unsigned j=0;j<props;j++) [s appendFormat:@"  property %s %s\n",property_getName(ps[j]),property_getAttributes(ps[j])]; free(ps); unsigned iv=0; Ivar *ivs=class_copyIvarList(c,&iv); for(unsigned j=0;j<iv;j++) [s appendFormat:@"  ivar %s %s offset=%td\n",ivar_getName(ivs[j]),ivar_getTypeEncoding(ivs[j]),ivar_getOffset(ivs[j])]; free(ivs); } free(cs); return s; }
- (NSString *)images { NSMutableString *s=[NSMutableString stringWithString:@"LOADED_IMAGES.txt\n"]; for(uint32_t i=0;i<_dyld_image_count();i++) [s appendFormat:@"%u base=%p slide=%ld %s\n",i,_dyld_get_image_header(i),_dyld_get_image_vmaddr_slide(i),_dyld_get_image_name(i) ?: "(nil)"]; return s; }
- (NSString *)diagnostics { return [NSString stringWithFormat:@"DIAGNOSTICS.txt\nmain thread=%@\nstarted=%@\nhost=%p\noverlay=%p hidden=%@\nreports=%@\n",NSThread.isMainThread?@"YES":@"NO",self.started?@"YES":@"NO",self.hostWindow,self.window,self.window.hidden?@"YES":@"NO",ReportsDirectory().path]; }
- (void)showMenu { if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self showMenu];});return;} UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Universal UI Inspector" message:@"Read-only diagnostics" preferredStyle:UIAlertControllerStyleActionSheet]; NSArray *items=@[ @[ @"Prepare Full Capture", ^{ [[SessionCapture shared] start:self.hostWindow]; } ], @[ @"Capture Current Screen", ^{ [[SessionCapture shared] capture:self.hostWindow label:@"manual" inspectorWindow:self.window]; } ], @[ @"Stop Capture", ^{ [[SessionCapture shared] stop]; } ], @[ @"Export Session", ^{ [self exportSession]; } ], @[ @"Choose Export Folder", ^{ [self chooseExportFolder]; } ], @[ @"Dump Visible Hierarchy", ^{ WriteReport(@"CURRENT_VIEW_HIERARCHY.txt",self.hierarchy); } ], @[ @"View Controllers", ^{ WriteReport(@"CURRENT_CONTROLLERS.txt",self.controllers); } ], @[ @"Runtime Classes (Detailed)", ^{ WriteReport(@"RUNTIME_CLASSES_DETAILED.txt",self.classes); } ], @[ @"Loaded Images", ^{ WriteReport(@"LOADED_IMAGES.txt",self.images); } ], @[ @"Diagnostics", ^{ WriteReport(@"DIAGNOSTICS.txt",self.diagnostics); } ] ]; for(NSArray *item in items) [a addAction:[UIAlertAction actionWithTitle:item[0] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ ((void(^)(void))item[1])(); }]]; [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]]; UIPopoverPresentationController *pop=a.popoverPresentationController; pop.sourceView=self.button; pop.sourceRect=self.button.bounds; pop.permittedArrowDirections=UIPopoverArrowDirectionAny; [[self presenter] presentViewController:a animated:YES completion:nil]; }
- (void)chooseExportFolder { UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[[UTType folder]] asCopy:NO]; picker.delegate=self; [[self presenter] presentViewController:picker animated:YES completion:nil]; }
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls { NSURL *u=urls.firstObject; if(!u)return; if([u startAccessingSecurityScopedResource]){self.selectedFolder=u; [self.startup appendFormat:@"Selected export folder: %@\n",u.path];} }
- (void)exportSession { dispatch_async(dispatch_get_main_queue(),^{ NSError *err=nil; NSURL *stage=[[SessionCapture shared] stageSession:self.hostWindow error:&err]; if(!stage){WriteReport(@"SESSION_EXPORT_ERROR.txt",err.localizedDescription ?: @"Unknown error");return;} NSMutableDictionary *files=[NSMutableDictionary dictionary]; NSDirectoryEnumerator *it=[[NSFileManager defaultManager] enumeratorAtURL:stage includingPropertiesForKeys:nil options:0 errorHandler:nil]; for(NSURL *u in it){if(!u.hasDirectoryPath){NSString *rel=[u.path substringFromIndex:stage.path.length+1]; NSData *d=[NSData dataWithContentsOfURL:u];if(d)files[rel]=d;}} NSData *zip=ZipData(files); NSURL *local=[stage URLByAppendingPathComponent:@"UniversalUIInspector-Session.zip"]; [zip writeToURL:local atomically:YES]; NSURL *target=self.selectedFolder ? [self.selectedFolder URLByAppendingPathComponent:local.lastPathComponent] : local; if(self.selectedFolder){NSError *copyError=nil; [[NSFileManager defaultManager] removeItemAtURL:target error:nil]; [[NSFileManager defaultManager] copyItemAtURL:local toURL:target error:&copyError]; if(copyError) WriteReport(@"SESSION_EXPORT_ERROR.txt",copyError.localizedDescription);} UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[target] applicationActivities:nil]; UIPopoverPresentationController *pop=share.popoverPresentationController;pop.sourceView=self.button;pop.sourceRect=self.button.bounds;[[self presenter] presentViewController:share animated:YES completion:nil]; }); }
- (void)exportReports { dispatch_async(dispatch_get_main_queue(),^{ NSArray *names=@[@"BOOT_DIAGNOSTICS.txt",@"RUNTIME_STARTUP_REPORT.txt",@"STARTUP_VIEW_TREE.txt",@"CURRENT_VIEW_HIERARCHY.txt",@"CURRENT_CONTROLLERS.txt",@"RUNTIME_CLASSES.txt",@"LOADED_IMAGES.txt",@"DIAGNOSTICS.txt"]; NSMutableDictionary *files=[NSMutableDictionary dictionary]; for(NSString *n in names){NSData *d=[NSData dataWithContentsOfFile:ReportPath(n)];if(d)files[n]=d;} NSData *zip=ZipData(files); NSURL *url=[ReportsDirectory() URLByAppendingPathComponent:@"UniversalUIInspector-Reports.zip"]; [zip writeToURL:url atomically:YES]; UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil]; UIPopoverPresentationController *pop=share.popoverPresentationController; pop.sourceView=self.button;pop.sourceRect=self.button.bounds; UIViewController *p=[self presenter]; [p presentViewController:share animated:YES completion:nil]; }); }
@end

static void UniversalUIInspectorInit(void) { dispatch_async(dispatch_get_main_queue(),^{ InspectorCore *core=InspectorCore.shared; NSArray *delays=@[@0.5,@1.0,@2.0,@4.0]; for(NSNumber *delay in delays) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if(!core.started)[core start];}); }); }
__attribute__((constructor)) static void UniversalUIInspectorConstructor(void) { UniversalUIInspectorInit(); }
