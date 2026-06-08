// MqttGrabber Tweak
// 捕获 MQTT 凭据来源

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <substrate.h>
#include <objc/runtime.h>

// ============================================
// MARK: - 日志管理器
// ============================================

@interface MqttLogManager : NSObject
@property (nonatomic, strong) NSMutableArray *logs;
@property (nonatomic, copy) void (^onNewLog)(NSString *log);
+ (instancetype)sharedInstance;
- (void)addLog:(NSString *)log;
@end

@implementation MqttLogManager

+ (instancetype)sharedInstance {
    static MqttLogManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MqttLogManager alloc] init];
        instance.logs = [NSMutableArray array];
    });
    return instance;
}

- (void)addLog:(NSString *)log {
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                        dateStyle:NSDateFormatterNoStyle
                                                        timeStyle:NSDateFormatterMediumStyle];
    NSString *logEntry = [NSString stringWithFormat:@"%@ %@", timestamp, log];
    
    @synchronized (self.logs) {
        [self.logs insertObject:logEntry atIndex:0];
        if (self.logs.count > 500) {
            [self.logs removeLastObject];
        }
    }
    
    // 打印到系统日志
    NSLog(@"%@", logEntry);
    
    // 通知 UI 更新
    if (self.onNewLog) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.onNewLog(logEntry);
        });
    }
}

@end

// ============================================
// MARK: - 日志查看控制器
// ============================================

@interface MqttLogViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *logs;
@end

@implementation MqttLogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MQTT 抓包";
    self.view.backgroundColor = [UIColor blackColor];
    
    // 导航栏
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭"
                                                                            style:UIBarButtonItemStyleDone
                                                                           target:self
                                                                           action:@selector(close)];
    
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"清空"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(clearLogs)],
        [[UIBarButtonItem alloc] initWithTitle:@"复制"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(copyLogs)]
    ];
    
    // 表格
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:self.tableView];
    
    // 初始数据
    @synchronized ([MqttLogManager sharedInstance].logs) {
        self.logs = [[MqttLogManager sharedInstance].logs copy];
    }
    
    // 监听新日志
    __weak typeof(self) weakSelf = self;
    [MqttLogManager sharedInstance].onNewLog = ^(NSString *log) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            @synchronized ([MqttLogManager sharedInstance].logs) {
                strongSelf.logs = [[MqttLogManager sharedInstance].logs copy];
            }
            [strongSelf.tableView reloadData];
        }
    };
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)clearLogs {
    @synchronized ([MqttLogManager sharedInstance].logs) {
        [[MqttLogManager sharedInstance].logs removeAllObjects];
        self.logs = @[];
    }
    [self.tableView reloadData];
}

- (void)copyLogs {
    @synchronized ([MqttLogManager sharedInstance].logs) {
        NSString *allLogs = [[MqttLogManager sharedInstance].logs componentsJoinedByString:@"\n"];
        [UIPasteboard generalPasteboard].string = allLogs;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已复制"
                                                                  message:@"日志已复制到剪贴板"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.logs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"LogCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = [UIFont fontWithName:@"Menlo" size:12];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.backgroundColor = [UIColor blackColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    
    NSString *log = self.logs[indexPath.row];
    cell.textLabel.text = log;
    
    // 根据日志类型设置颜色
    if ([log containsString:@"[MQTT CONNECT]"]) {
        cell.textLabel.textColor = [UIColor systemGreenColor];
    } else if ([log containsString:@"[MQTT PAIR]"] && [log containsString:@"setUsername"]) {
        cell.textLabel.textColor = [UIColor systemYellowColor];
    } else if ([log containsString:@"[MQTT PAIR]"] && [log containsString:@"setPassword"]) {
        cell.textLabel.textColor = [UIColor systemOrangeColor];
    } else if ([log containsString:@"[MQTT HTTP]"]) {
        cell.textLabel.textColor = [UIColor systemBlueColor];
    } else if ([log containsString:@"[MQTT VC]"]) {
        cell.textLabel.textColor = [UIColor systemPurpleColor];
    }
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

@end

// ============================================
// MARK: - 悬浮按钮（参考 WulingBleAS）
// ============================================

@interface MqttFloatingButton : UIView
@property (nonatomic, strong) UIView *capsule;
@property (nonatomic, strong) UILabel *statusLabel;
+ (instancetype)shared;
- (void)installIfNeeded;
- (void)updateStatus:(NSString *)status;
@end

@implementation MqttFloatingButton

static MqttFloatingButton *_shared = nil;

+ (instancetype)shared {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [MqttFloatingButton new];
    });
    return _shared;
}

- (UIWindow *)activeWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ws.windows) if (w.isKeyWindow) return w;
        if (ws.windows.count) return ws.windows.firstObject;
    }
    return nil;
}

- (void)installIfNeeded {
    if (self.capsule) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [self activeWindow];
        if (!window) return;
        
        CGFloat screenW = window.bounds.size.width;
        CGFloat capsuleW = 120;
        CGFloat capsuleH = 36;
        
        // 右上位置
        CGFloat safeTop = 0;
        if (@available(iOS 13.0, *)) {
            UIWindowScene *ws = window.windowScene;
            if (ws) safeTop = ws.statusBarManager.statusBarFrame.size.height;
        }
        if (safeTop == 0) safeTop = 44;
        
        CGFloat capsuleY = safeTop + 8;
        CGFloat capsuleX = screenW - capsuleW - 12;
        
        UIView *c = [[UIView alloc] initWithFrame:CGRectMake(capsuleX, capsuleY, capsuleW, capsuleH)];
        c.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
        c.layer.cornerRadius = capsuleH / 2;
        c.layer.masksToBounds = YES;
        c.layer.borderWidth = 1;
        c.layer.borderColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.6].CGColor;
        
        // 图标
        UILabel *icon = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, 20, capsuleH)];
        icon.text = @"📡";
        icon.font = [UIFont systemFontOfSize:14];
        [c addSubview:icon];
        
        // 状态标签
        _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(28, 0, capsuleW - 36, capsuleH)];
        _statusLabel.text = @"MQTT";
        _statusLabel.textColor = [UIColor whiteColor];
        _statusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        [c addSubview:_statusLabel];
        
        // 点击
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openLog)];
        [c addGestureRecognizer:tap];
        
        // 拖动
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [c addGestureRecognizer:pan];
        
        [window addSubview:c];
        self.capsule = c;
    });
}

- (void)updateStatus:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_statusLabel.text = status;
    });
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *c = gesture.view;
    UIWindow *window = [self activeWindow];
    if (!window) return;
    
    CGPoint translation = [gesture translationInView:window];
    CGFloat halfW = c.bounds.size.width / 2;
    CGFloat halfH = c.bounds.size.height / 2;
    CGFloat newX = c.center.x + translation.x;
    CGFloat newY = c.center.y + translation.y;
    
    // 边界
    newX = MAX(halfW, MIN(window.bounds.size.width - halfW, newX));
    newY = MAX(halfH, MIN(window.bounds.size.height - halfH, newY));
    
    c.center = CGPointMake(newX, newY);
    [gesture setTranslation:CGPointZero inView:window];
}

- (void)openLog {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [self activeWindow];
        UIViewController *root = window.rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;
        
        MqttLogViewController *vc = [[MqttLogViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.navigationBar.barStyle = UIBarStyleBlack;
        nav.navigationBar.tintColor = [UIColor whiteColor];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        [root presentViewController:nav animated:YES completion:nil];
    });
}

@end

// ============================================
// MARK: - 显示 HUD 的函数
// ============================================

static BOOL hudShowing = NO;

static void showHUDIfNeeded(void) {
    if (hudShowing) return;
    hudShowing = YES;
    
    NSLog(@"[MQTT GRABBER] 🚀 showHUDIfNeeded 被调用!");
    
    dispatch_async(dispatch_get_main_queue(), ^{
        MqttFloatingButton *btn = [MqttFloatingButton shared];
        [btn installIfNeeded];
        [btn updateStatus:@"已启动"];
    });
}

// ============================================
// MARK: - Hook 点
// ============================================

%hook CYGoHasCarVC

- (void)loginMQTT {
    [[MqttLogManager sharedInstance] addLog:@"[MQTT VC] >>> loginMQTT 被调用"];
    
    // 打印调用堆栈
    NSArray *callStack = [NSThread callStackSymbols];
    for (NSString *symbol in callStack) {
        if ([symbol containsString:@"LingLingBang"]) {
            [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT VC]   %@", symbol]];
        }
    }
    
    // 更新 HUD 状态
    [[MqttFloatingButton shared] updateStatus:@"获取凭据..."];
    
    %orig;
    
    [[MqttLogManager sharedInstance] addLog:@"[MQTT VC] <<< loginMQTT 完成"];
}

%end

%hook CYUnifiedMQTTHelperPair

- (void)setUsername:(NSString *)username {
    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT PAIR] setUsername: %@", username]];
    
    NSArray *callStack = [NSThread callStackSymbols];
    for (NSString *symbol in callStack) {
        if ([symbol containsString:@"LingLingBang"]) {
            [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT PAIR]   %@", symbol]];
        }
    }
    
    %orig;
}

- (void)setPassword:(NSString *)password {
    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT PAIR] setPassword: %@", password]];
    
    NSArray *callStack = [NSThread callStackSymbols];
    for (NSString *symbol in callStack) {
        if ([symbol containsString:@"LingLingBang"]) {
            [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT PAIR]   %@", symbol]];
        }
    }
    
    %orig;
}

- (void)setVin:(NSString *)vin {
    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT PAIR] setVin: %@", vin]];
    %orig;
}

- (void)setClientId:(NSString *)clientId {
    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT PAIR] setClientId: %@", clientId]];
    
    NSArray *callStack = [NSThread callStackSymbols];
    for (NSString *symbol in callStack) {
        if ([symbol containsString:@"LingLingBang"]) {
            [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT PAIR]   %@", symbol]];
        }
    }
    
    %orig;
}

- (void)setVintime:(NSString *)vintime {
    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT PAIR] setVintime: %@", vintime]];
    %orig;
}

// hook init 方法
- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = %orig;
    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT PAIR] initWithDictionary: %@", dict]];
    
    NSArray *callStack = [NSThread callStackSymbols];
    for (NSString *symbol in callStack) {
        if ([symbol containsString:@"LingLingBang"]) {
            [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT PAIR]   %@", symbol]];
        }
    }
    
    return self;
}

- (instancetype)initWithData:(id)data {
    self = %orig;
    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT PAIR] initWithData: %@", data]];
    
    NSArray *callStack = [NSThread callStackSymbols];
    for (NSString *symbol in callStack) {
        if ([symbol containsString:@"LingLingBang"]) {
            [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT PAIR]   %@", symbol]];
        }
    }
    
    return self;
}

- (instancetype)initWithJSON:(id)json {
    self = %orig;
    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT PAIR] initWithJSON: %@", json]];
    
    NSArray *callStack = [NSThread callStackSymbols];
    for (NSString *symbol in callStack) {
        if ([symbol containsString:@"LingLingBang"]) {
            [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT PAIR]   %@", symbol]];
        }
    }
    
    return self;
}

%end

%hook CYUnifiedMQTTHelper

- (void)connectWithUsername:(NSString *)username 
                   password:(NSString *)password 
                   clientId:(NSString *)clientId 
                    success:(id)success 
                    failure:(id)failure {
    
    [[MqttLogManager sharedInstance] addLog:@"[MQTT CONNECT] ============================"];
    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT CONNECT] Username: %@", username]];
    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT CONNECT] Password: %@", password]];
    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT CONNECT] ClientID: %@", clientId]];
    [[MqttLogManager sharedInstance] addLog:@"[MQTT CONNECT] ============================"];
    
    // 打印调用堆栈
    NSArray *callStack = [NSThread callStackSymbols];
    for (NSString *symbol in callStack) {
        if ([symbol containsString:@"LingLingBang"]) {
            [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT CONNECT]   %@", symbol]];
        }
    }
    
    // 更新 HUD 状态
    [[MqttFloatingButton shared] updateStatus:@"已连接"];
    
    %orig;
}

- (void)subcribeTopicsWithCompletion:(id)completion {
    [[MqttLogManager sharedInstance] addLog:@"[MQTT HELPER] >>> subcribeTopicsWithCompletion"];
    %orig;
}

- (void)reConnectMTQQ {
    [[MqttLogManager sharedInstance] addLog:@"[MQTT HELPER] >>> reConnectMTQQ"];
    %orig;
}

- (void)disconnectMQTT {
    [[MqttLogManager sharedInstance] addLog:@"[MQTT HELPER] >>> disconnectMQTT"];
    %orig;
}

// Hook getTokenAndLoginWithVin 方法
- (void)getTokenAndLoginWithVin:(NSString *)vin 
                       complete:(void(^)(id pair))complete {
    
    [[MqttLogManager sharedInstance] addLog:@"[MQTT HELPER] >>> getTokenAndLoginWithVin"];
    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT HELPER]   vin: %@", vin]];
    
    // 包装回调，拦截返回的 pair
    void(^wrappedComplete)(id pair) = ^(id pair) {
        [[MqttLogManager sharedInstance] addLog:@"[MQTT HELPER] <<< getTokenAndLoginWithVin 回调返回"];
        [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT HELPER]   pair class: %@", [pair class]]];
        
        // 用 KVC 读取所有属性
        unsigned int count;
        objc_property_t *props = class_copyPropertyList([pair class], &count);
        for (unsigned int i = 0; i < count; i++) {
            const char *name = property_getName(props[i]);
            NSString *key = [NSString stringWithUTF8String:name];
            @try {
                id value = [pair valueForKey:key];
                [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT HELPER]   pair.%@ = %@", key, value]];
            } @catch (NSException *e) {
                [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT HELPER]   pair.%@ = (异常)", key]];
            }
        }
        free(props);
        
        // 打印调用堆栈
        NSArray *callStack = [NSThread callStackSymbols];
        for (NSString *symbol in callStack) {
            if ([symbol containsString:@"LingLingBang"]) {
                [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT HELPER]   %@", symbol]];
            }
        }
        
        if (complete) {
            complete(pair);
        }
    };
    
    %orig(vin, wrappedComplete);
}

// Hook initWithPair 方法
- (instancetype)initWithPair:(id)pair {
    self = %orig;
    [[MqttLogManager sharedInstance] addLog:@"[MQTT HELPER] initWithPair"];
    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT HELPER]   pair class: %@", [pair class]]];
    
    // 用 KVC 读取所有属性
    unsigned int count;
    objc_property_t *props = class_copyPropertyList([pair class], &count);
    for (unsigned int i = 0; i < count; i++) {
        const char *name = property_getName(props[i]);
        NSString *key = [NSString stringWithUTF8String:name];
        @try {
            id value = [pair valueForKey:key];
            [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT HELPER]   pair.%@ = %@", key, value]];
        } @catch (NSException *e) {
            [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT HELPER]   pair.%@ = (异常)", key]];
        }
    }
    free(props);
    
    return self;
}

%end

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request 
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    
    NSString *url = request.URL.absoluteString;
    
    // 拦截所有请求，记录到日志
    [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT HTTP] >>> Request: %@ %@", request.HTTPMethod, url]];
    
    if (request.HTTPBody) {
        NSString *body = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
        [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT HTTP] >>> Body: %@", body]];
    }
    
    void(^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            NSString *responseStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT HTTP] <<< Response: %@", responseStr]];
        }
        if (completionHandler) {
            completionHandler(data, response, error);
        }
    };
    
    return %orig(request, wrappedHandler);
}

%end

// Hook NSUserDefaults
%hook NSUserDefaults

- (void)setObject:(id)value forKey:(NSString *)defaultName {
    %orig;
    
    // 记录所有写入的 key
    if ([defaultName containsString:@"mqtt"] || 
        [defaultName containsString:@"MQTT"] ||
        [defaultName containsString:@"username"] ||
        [defaultName containsString:@"password"] ||
        [defaultName containsString:@"token"] ||
        [defaultName containsString:@"Token"]) {
        
        [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT USERDEFAULTS] setObject: %@ = %@", defaultName, value]];
        
        // 打印调用堆栈
        NSArray *callStack = [NSThread callStackSymbols];
        for (NSString *symbol in callStack) {
            if ([symbol containsString:@"LingLingBang"]) {
                [[MqttLogManager sharedInstance] addLog:[NSString stringWithFormat:@"[MQTT USERDEFAULTS]   %@", symbol]];
            }
        }
    }
}

%end

// ============================================
// MARK: - Hook UIApplication
// ============================================

%hook UIApplication

- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    NSLog(@"[MQTT GRABBER] 📱 applicationDidBecomeActive!");
    showHUDIfNeeded();
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    %orig;
    NSLog(@"[MQTT GRABBER] 📱 applicationWillEnterForeground!");
    showHUDIfNeeded();
}

%end

// ============================================
// MARK: - Hook UIViewController
// ============================================

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // 第一次 viewDidAppear 时触发
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[MQTT GRABBER] 📱 第一个 UIViewController viewDidAppear!");
        showHUDIfNeeded();
    });
}

%end

// ============================================
// MARK: - 构造函数
// ============================================

%ctor {
    NSLog(@"[MQTT GRABBER] =============================================");
    NSLog(@"[MQTT GRABBER] 🚀🚀🚀 MQTT 抓包插件已加载! 🚀🚀🚀");
    NSLog(@"[MQTT GRABBER] 📱 Bundle: %@", [[NSBundle mainBundle] bundleIdentifier]);
    NSLog(@"[MQTT GRABBER] 📱 可执行文件: %@", [[NSProcessInfo processInfo] processName]);
    NSLog(@"[MQTT GRABBER] =============================================");
    
    [[MqttLogManager sharedInstance] addLog:@"[MQTT GRABBER] Tweak 已加载！"];
    
    // 立即显示 HUD（不延迟，确保能抓到数据）
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[MQTT GRABBER] 🚀 立即显示 HUD");
        showHUDIfNeeded();
    });
}
