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
// MARK: - HUD 控制器（参考 baojun_ble_hud）
// ============================================

@interface MqttHUDViewController : UIViewController
@property (nonatomic, strong) UIView *hudView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) CGPoint dragOffset;
@property (nonatomic, assign) BOOL isShowing;
+ (instancetype)shared;
- (void)show;
- (void)hide;
- (void)updateStatus:(NSString *)status;
@end

@implementation MqttHUDViewController

static MqttHUDViewController *_shared = nil;

+ (instancetype)shared {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _shared = [[MqttHUDViewController alloc] init];
    });
    return _shared;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    [self setupHUD];
}

- (void)setupHUD {
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat x = screenWidth - 180;
    CGFloat y = 100;
    
    // 主 HUD 容器
    _hudView = [[UIView alloc] initWithFrame:CGRectMake(x, y, 170, 80)];
    _hudView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
    _hudView.layer.cornerRadius = 16;
    _hudView.layer.borderWidth = 1;
    _hudView.layer.borderColor = [[UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.6] CGColor];
    _hudView.layer.shadowColor = [UIColor blackColor].CGColor;
    _hudView.layer.shadowOffset = CGSizeMake(0, 4);
    _hudView.layer.shadowRadius = 12;
    _hudView.layer.shadowOpacity = 0.5;
    _hudView.clipsToBounds = NO;
    _hudView.hidden = YES;
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, 150, 18)];
    titleLabel.text = @"📡 MQTT 抓包";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [_hudView addSubview:titleLabel];
    
    // 状态标签
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 28, 150, 40)];
    _statusLabel.text = @"等待抓包...";
    _statusLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
    _statusLabel.font = [UIFont fontWithName:@"Menlo" size:10];
    _statusLabel.numberOfLines = 3;
    [_hudView addSubview:_statusLabel];
    
    // 手势
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [_hudView addGestureRecognizer:tap];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [_hudView addGestureRecognizer:pan];
    
    [self.view addSubview:_hudView];
}

- (void)show {
    if (_isShowing) return;
    _isShowing = YES;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_hudView.hidden = NO;
        self->_hudView.alpha = 0;
        [UIView animateWithDuration:0.3 animations:^{
            self->_hudView.alpha = 1.0;
        }];
    });
}

- (void)hide {
    if (!_isShowing) return;
    _isShowing = NO;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 animations:^{
            self->_hudView.alpha = 0;
        } completion:^(BOOL finished) {
            self->_hudView.hidden = YES;
        }];
    });
}

- (void)updateStatus:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_statusLabel.text = status;
    });
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    MqttLogViewController *vc = [[MqttLogViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    nav.navigationBar.tintColor = [UIColor whiteColor];
    
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    [rootVC presentViewController:nav animated:YES completion:nil];
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self.view];
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        _dragOffset = CGPointMake(location.x - _hudView.frame.origin.x,
                                  location.y - _hudView.frame.origin.y);
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat newX = location.x - _dragOffset.x;
        CGFloat newY = location.y - _dragOffset.y;
        
        // 边界限制
        CGRect screen = [UIScreen mainScreen].bounds;
        newX = MAX(0, MIN(newX, screen.size.width - _hudView.frame.size.width));
        newY = MAX(40, MIN(newY, screen.size.height - _hudView.frame.size.height - 40));
        
        _hudView.frame = CGRectMake(newX, newY, _hudView.frame.size.width, _hudView.frame.size.height);
    }
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
        MqttHUDViewController *hud = [MqttHUDViewController shared];
        [hud show];
        [hud updateStatus:@"已启动，等待抓包..."];
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
    [[MqttHUDViewController shared] updateStatus:@"正在获取 MQTT 凭据..."];
    
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
    
    // 更新 HUD 状态
    [[MqttHUDViewController shared] updateStatus:[NSString stringWithFormat:@"已连接\nUser: %@\nPass: %@", 
        [username substringToIndex:MIN(8, username.length)], 
        [password substringToIndex:MIN(8, password.length)]]];
    
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
// MARK: - Hook UIApplication（参考 baojun_ble_hud）
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
// MARK: - Hook UIViewController（参考 baojun_ble_hud）
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
// MARK: - 构造函数（参考 baojun_ble_hud）
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
