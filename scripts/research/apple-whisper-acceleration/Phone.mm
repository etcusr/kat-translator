#import <UIKit/UIKit.h>
#ifdef BENCH_MLX
#import "WhisperProbe-Swift.h"
#endif
int runWhisperBench(NSString *, NSString *, NSString *, int);

@interface Delegate : UIResponder <UIApplicationDelegate, UIWindowSceneDelegate>
@property(strong) UIWindow *window;
@end
@implementation Delegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    setenv("GGML_METAL_NO_RESIDENCY", "1", 1); // Same policy as current Kat iOS.
    return YES;
}
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session
        options:(UISceneConnectionOptions *)options {
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.blackColor;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(self.window.bounds, 24, 100)];
    label.textColor = UIColor.whiteColor; label.numberOfLines = 0;
    label.text = @"Whisper research\nSeparate benchmark app";
    [vc.view addSubview:label]; self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *env = NSProcessInfo.processInfo.environment;
        NSString *docs = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
            inDomains:NSUserDomainMask].firstObject.path;
        NSString *model = env[@"BENCH_MODEL"] ?: @"f16.bin";
        NSString *run = env[@"BENCH_RUN"] ?: @"default";
        if ([env[@"BENCH_SHARED_ENCODER"] isEqualToString:@"1"])
            setenv("BENCH_COREML_ENCODER", [docs stringByAppendingPathComponent:@"f16-encoder.mlmodelc"].fileSystemRepresentation, 1);
        double coolingStart = NSProcessInfo.processInfo.systemUptime;
        while ([env[@"BENCH_COOL"] isEqualToString:@"1"] &&
               NSProcessInfo.processInfo.thermalState != NSProcessInfoThermalStateNominal) {
            if (NSProcessInfo.processInfo.systemUptime - coolingStart > 300) {
                NSDictionary *error = @{@"error": @"Thermal state did not become nominal within 300 seconds"};
                [[NSJSONSerialization dataWithJSONObject:error options:0 error:nil]
                    writeToFile:[docs stringByAppendingPathComponent:[run stringByAppendingString:@".json"]] atomically:YES];
                return;
            }
            [NSThread sleepForTimeInterval:5];
        }
#ifdef BENCH_MLX
        if ([env[@"BENCH_MODE"] isEqualToString:@"mlx"]) {
            [MLXRunner runWithDirectory:docs run:run];
            return;
        }
#endif
        int rc = runWhisperBench([docs stringByAppendingPathComponent:model],
            [docs stringByAppendingPathComponent:@"manifest.json"],
            [docs stringByAppendingPathComponent:[run stringByAppendingString:@".json"]], 3);
        dispatch_async(dispatch_get_main_queue(), ^{
            label.text = [NSString stringWithFormat:@"Whisper research\n%@\nFinished: %d", run, rc];
        });
    });
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(Delegate.class)); }
}
