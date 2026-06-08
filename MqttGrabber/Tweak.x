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
// MARK: - 悬浮窗
// ============================================

@interface MqttFloatingWindow : UIWindow
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, assign) CGPoint startPoint;
@property (nonatomic, assign) BOOL isDragging;
@end

@implementation MqttFloatingWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.windowLevel = UIWindowLevelStatusBar + 100;
        self.backgroundColor = [UIColor clearColor];
        self.layer.cornerRadius = 25;
        self.clipsToBounds = YES;
        
        // 毛玻璃效果
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
        blur.frame = self.bounds;
        blur.layer.cornerRadius = 25;
        blur.clipsToBounds = YES;
        [self addSubview:blur];
        
        // 按钮
        self.button = [UIButton buttonWithType:UIButtonTypeSystem];
        self.button.frame = self.bounds;
        [self.button setTitle:@"📡" forState:UIControlStateNormal];
        self.button.titleLabel.font = [UIFont systemFontOfSize:24];
        [self.button addTarget:self action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.button];
        
        // 拖动手势
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)onPan:(UIPanGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self.superview];
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.startPoint = location;
        self.isDragging = NO;
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat dx = location.x - self.startPoint.x;
        CGFloat dy = location.y - self.startPoint.y;
        
        if (fabs(dx) > 5 || fabs(dy) > 5) {
            self.isDragging = YES;
        }
        
        if (self.isDragging) {
            self.center = location;
        }
    } else if (gesture.state == UIGestureRecognizerStateEnded) {
        if (!self.isDragging) {
            [self onTap];
        }
        
        // 吸附到屏幕边缘
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        CGFloat finalX = self.center.x;
        CGFloat finalY = self.center.y;
        
        if (finalX < screenBounds.size.width / 2) {
            finalX = 30;
        } else {
            finalX = screenBounds.size.width - 30;
        }
        
        finalY = MAX(60, MIN(finalY, screenBounds.size.height - 60));
        
        [UIView animateWithDuration:0.3 animations:^{
            self.center = CGPointMake(finalX, finalY);
        }];
    }
}

- (void)onTap {
    MqttLogViewController *vc = [[MqttLogViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    nav.navigationBar.tintColor = [UIColor whiteColor];
    
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    [rootVC presentViewController:nav animated:YES completion:nil];
}

@end

// ============================================
// MARK: - Hook 点
// ============================================

// 悬浮窗实例
static MqttFloatingWindow *floatingWindow = nil;

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

%end

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request 
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    
    NSString *url = request.URL.absoluteString;
    
    if ([url containsString:@"botai"] || 
        [url containsString:@"mqtt"] ||
        [url containsString:@"token"]) {
        
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
    
    return %orig(request, completionHandler);
}

%end

// ============================================
// MARK: - 构造函数
// ============================================

%ctor {
    %init;
    
    [[MqttLogManager sharedInstance] addLog:@"[MQTT GRABBER] Tweak 已加载！"];
    
    // 延迟创建悬浮窗，等待 app 启动完成
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        floatingWindow = [[MqttFloatingWindow alloc] initWithFrame:CGRectMake(0, 200, 50, 50)];
        floatingWindow.hidden = NO;
        [floatingWindow makeKeyAndVisible];
        
        [[MqttLogManager sharedInstance] addLog:@"[MQTT GRABBER] 悬浮窗已创建"];
    });
}
