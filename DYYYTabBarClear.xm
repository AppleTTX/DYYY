#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DYYYSettingsHelper.h"

// 底栏按钮隐藏：默认不渲染，点击底部再显形
// 关键点：用 CALayer.opacity 而不是 alpha/hidden，
// 这样按钮仍然参与 hitTest，功能不会失效。

static BOOL gRevealed = NO;
static NSTimer *gHideTimer = nil;
static __weak UIView *gBarView = nil;
static __weak UIView *gGestureBar = nil;

static BOOL DYYYBoolValue(NSString *key, BOOL fallback) {
    NSNumber *n = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return n ? [n boolValue] : fallback;
}

static void DYYYSetLabelsOpacity(UIView *view, CGFloat opacity) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UILabel class]]) {
            sub.layer.opacity = opacity;
        } else {
            DYYYSetLabelsOpacity(sub, opacity);
        }
    }
}

static void DYYYApplyTabBar(UIView *bar);

@interface DYYYTabBarTapTarget : NSObject
+ (instancetype)shared;
- (void)onTap:(UITapGestureRecognizer *)gesture;
- (void)onHideTimer:(NSTimer *)timer;
@end

@implementation DYYYTabBarTapTarget

+ (instancetype)shared {
    static id instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      instance = [self new];
    });
    return instance;
}

- (void)onTap:(UITapGestureRecognizer *)gesture {
    if (!DYYYBoolValue(@"DYYYTabBarClearEnabled", NO)) {
        return;
    }
    if (!gRevealed) {
        gRevealed = YES;
        DYYYApplyTabBar(gBarView);
    }
    [gHideTimer invalidate];
    gHideTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                  target:self
                                                selector:@selector(onHideTimer:)
                                                userInfo:nil
                                                 repeats:NO];
}

- (void)onHideTimer:(NSTimer *)timer {
    gHideTimer = nil;
    gRevealed = NO;
    DYYYApplyTabBar(gBarView);
}

@end

static void DYYYApplyTabBar(UIView *bar) {
    if (!bar) {
        return;
    }
    gBarView = bar;

    BOOL enabled = DYYYBoolValue(@"DYYYTabBarClearEnabled", NO);
    BOOL tapToShow = DYYYBoolValue(@"DYYYTabBarClearTapShow", YES);
    BOOL textOnly = DYYYBoolValue(@"DYYYTabBarClearTextOnly", NO);

    // 未开启点击显示时，底栏始终不渲染
    BOOL visible = !enabled || (tapToShow && gRevealed);

    Class buttonClass = NSClassFromString(@"AWENormalModeTabBarGeneralButton");
    for (UIView *subview in bar.subviews) {
        if (buttonClass && ![subview isKindOfClass:buttonClass]) {
            continue;
        }
        if (subview.hidden) {
            continue;
        }
        if (textOnly) {
            subview.layer.opacity = 1.0f;
            subview.userInteractionEnabled = YES;
            DYYYSetLabelsOpacity(subview, visible ? 1.0f : 0.0f);
        } else {
            subview.layer.opacity = visible ? 1.0f : 0.0f;
            if (enabled && tapToShow) {
                subview.userInteractionEnabled = visible;
            } else {
                subview.userInteractionEnabled = YES;
            }
        }
    }

    if (bar != gGestureBar && enabled) {
        UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:[DYYYTabBarTapTarget shared]
                                                                                action:@selector(onTap:)];
        gesture.cancelsTouchesInView = NO;
        [bar addGestureRecognizer:gesture];
        gGestureBar = bar;
    }
}

%hook AWENormalModeTabBar

- (void)layoutSubviews {
    %orig;
    __weak UIView *weakBar = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      DYYYApplyTabBar(weakBar);
    });
}

- (void)didAddSubview:(UIView *)subview {
    %orig;
    __weak UIView *weakBar = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      DYYYApplyTabBar(weakBar);
    });
}

%end

%hook AWENormalModeTabBarGeneralButton

- (void)setStatus:(long long)status {
    %orig;
    if (gRevealed && status == 2) {
        [gHideTimer invalidate];
        gHideTimer = [NSTimer scheduledTimerWithTimeInterval:1.2
                                                      target:[DYYYTabBarTapTarget shared]
                                                    selector:@selector(onHideTimer:)
                                                    userInfo:nil
                                                     repeats:NO];
    }
}

%end

%ctor {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    // 移除已裁剪功能的开关，避免旧配置让它们继续生效
    NSArray *removedKeys = @[
        @"DYYYEnableAutoPlay", @"DYYYEnableBackgroundListen", @"DYYYDisableCastVPNCheck",
        @"DYYYDefaultSpeed", @"DYYYLongPressSpeed", @"DYYYEnableLongPressSpeedGesture",
        @"DYYYEnableDanmuColor", @"DYYYDanmuColor", @"DYYYDanmuRainbowRotating",
        @"DYYYEnableRandomGradient", @"DYYYEnableFloatSpeedButton", @"DYYYEnableFloatClearButton"
    ];
    for (NSString *key in removedKeys) {
        [defaults removeObjectForKey:key];
    }
    [defaults synchronize];
}
