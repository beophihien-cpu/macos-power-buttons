#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <Security/Security.h>
#import <dlfcn.h>
#import <math.h>
#import <string.h>

@interface HoverButton : NSButton
@property(nonatomic, weak) NSView *hoverOverlay;
@property(nonatomic, weak) NSView *cardView;
@property(nonatomic, weak) NSView *hoverBorder;
@property(nonatomic, weak) NSView *shineView;
@property(nonatomic) CGFloat baseOverlayAlpha;
@property(nonatomic) SEL rightClickAction;
@property(nonatomic, strong) NSTrackingArea *hoverTrackingArea;
@end

@implementation HoverButton

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.hoverTrackingArea != nil) {
        [self removeTrackingArea:self.hoverTrackingArea];
    }
    self.hoverTrackingArea = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
        owner:self
        userInfo:nil];
    [self addTrackingArea:self.hoverTrackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
    self.cardView.wantsLayer = YES;
    self.cardView.layer.shadowColor = NSColor.blackColor.CGColor;
    self.cardView.layer.shadowRadius = 10.0;
    self.cardView.layer.shadowOffset = NSMakeSize(0, -2);
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.16;
        self.cardView.layer.shadowOpacity = 0.14;
        self.hoverOverlay.animator.alphaValue = self.baseOverlayAlpha > 0.0 ? self.baseOverlayAlpha + 0.10 : 0.22;
        self.hoverBorder.animator.alphaValue = 0.68;
    } completionHandler:nil];

    NSRect shineStart = self.shineView.frame;
    shineStart.origin.x = -shineStart.size.width;
    self.shineView.frame = shineStart;
    self.shineView.alphaValue = 0.24;
    NSRect shineEnd = shineStart;
    shineEnd.origin.x = self.bounds.size.width;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.48;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        self.shineView.animator.frame = shineEnd;
    } completionHandler:^{
        self.shineView.alphaValue = 0.0;
    }];
}

- (void)mouseExited:(NSEvent *)event {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.20;
        self.cardView.layer.shadowOpacity = 0.0;
        self.hoverOverlay.animator.alphaValue = self.baseOverlayAlpha;
        self.hoverBorder.animator.alphaValue = 0.20;
    } completionHandler:nil];
}

- (void)mouseDown:(NSEvent *)event {
    NSView *card = self.cardView;
    NSRect restingFrame = card.frame;
    card.frame = NSInsetRect(restingFrame, 4.0, 3.0);
    self.hoverOverlay.alphaValue = MIN(self.baseOverlayAlpha + 0.20, 0.34);
    [card.superview displayIfNeeded];

    NSEvent *mouseUp = [self.window nextEventMatchingMask:NSEventMaskLeftMouseUp];
    NSPoint releasePoint = [self convertPoint:mouseUp.locationInWindow fromView:nil];
    BOOL releasedInside = NSPointInRect(releasePoint, self.bounds);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.14;
            card.animator.frame = restingFrame;
            self.hoverOverlay.animator.alphaValue = self.baseOverlayAlpha;
        } completionHandler:nil];
        if (releasedInside) {
            [NSApp sendAction:self.action to:self.target from:self];
        }
    });
}

- (void)rightMouseDown:(NSEvent *)event {
    if (self.rightClickAction != NULL) {
        [NSApp sendAction:self.rightClickAction to:self.target from:self];
        return;
    }
    [super rightMouseDown:event];
}

@end

@interface TrafficLightButton : NSButton
@property(nonatomic, copy) NSString *hoverSymbol;
@property(nonatomic, strong) NSTrackingArea *hoverTrackingArea;
@end

@implementation TrafficLightButton

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.hoverTrackingArea != nil) {
        [self removeTrackingArea:self.hoverTrackingArea];
    }
    self.hoverTrackingArea = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
        owner:self
        userInfo:nil];
    [self addTrackingArea:self.hoverTrackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
    self.title = self.hoverSymbol ?: @"";
}

- (void)mouseExited:(NSEvent *)event {
    self.title = @"";
}

@end

@interface PowerButtonsDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSGlassEffectView *outerGlass;
@property(nonatomic, strong) NSView *primaryGlass;
@property(nonatomic, strong) NSView *lockGlass;
@property(nonatomic, strong) NSView *sleepGlass;
@property(nonatomic, strong) NSView *restartGlass;
@property(nonatomic, strong) NSView *shutdownGlass;
@property(nonatomic, strong) NSImageView *headerIcon;
@property(nonatomic, strong) NSTextField *shutdownCountdownLabel;
@property(nonatomic, strong) NSTimer *shutdownCountdownTimer;
@property(nonatomic, strong) NSDate *scheduledShutdownDate;
@end


@implementation PowerButtonsDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self buildWindow];
    [self restoreShutdownCountdown];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 600, 680);
    self.window = [[NSWindow alloc]
        initWithContentRect:frame
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskFullSizeContentView
        backing:NSBackingStoreBuffered
        defer:NO];
    self.window.title = @"电源快捷按钮";
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.titlebarAppearsTransparent = YES;
    self.window.movableByWindowBackground = YES;
    self.window.releasedWhenClosed = NO;
    self.window.opaque = NO;
    self.window.backgroundColor = NSColor.clearColor;
    [self.window standardWindowButton:NSWindowCloseButton].hidden = YES;
    [self.window standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
    [self.window standardWindowButton:NSWindowZoomButton].hidden = YES;
    [self.window center];

    NSView *root = [[NSView alloc] initWithFrame:frame];
    self.window.contentView = root;

    NSRect outerFrame = NSInsetRect(root.bounds, 14, 14);
    NSView *outerContent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, outerFrame.size.width, outerFrame.size.height)];
    outerContent.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.outerGlass = [[NSGlassEffectView alloc] initWithFrame:outerFrame];
    self.outerGlass.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.outerGlass.style = NSGlassEffectViewStyleClear;
    self.outerGlass.cornerRadius = 30;
    self.outerGlass.tintColor = nil;
    self.outerGlass.wantsLayer = YES;
    self.outerGlass.layer.borderWidth = 1.0;
    self.outerGlass.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.46].CGColor;
    self.outerGlass.layer.cornerRadius = 30;
    self.outerGlass.contentView = outerContent;
    [root addSubview:self.outerGlass];

    [self buildTrafficLightsInView:outerContent];
    [self buildHeaderInView:outerContent];
    [self buildControlsInView:outerContent];
    [self.window makeKeyAndOrderFront:nil];
}

- (NSButton *)trafficLightWithFrame:(NSRect)frame color:(NSColor *)color symbol:(NSString *)symbol action:(SEL)action {
    TrafficLightButton *button = [[TrafficLightButton alloc] initWithFrame:frame];
    button.title = @"";
    button.hoverSymbol = symbol;
    button.bordered = NO;
    button.font = [NSFont systemFontOfSize:10 weight:NSFontWeightBold];
    button.contentTintColor = [NSColor colorWithWhite:0.22 alpha:0.9];
    button.wantsLayer = YES;
    button.layer.cornerRadius = frame.size.width / 2.0;
    button.layer.backgroundColor = color.CGColor;
    button.layer.borderWidth = 0.5;
    button.layer.borderColor = [color colorWithAlphaComponent:0.55].CGColor;
    if (action != NULL) {
        button.target = self;
        button.action = action;
    }
    return button;
}

- (void)buildTrafficLightsInView:(NSView *)parent {
    NSButton *close = [self trafficLightWithFrame:NSMakeRect(22, 616, 14, 14)
        color:[NSColor colorWithSRGBRed:1.0 green:0.37 blue:0.34 alpha:1.0]
        symbol:@"×"
        action:@selector(closeWindow:)];
    NSButton *minimize = [self trafficLightWithFrame:NSMakeRect(44, 616, 14, 14)
        color:[NSColor colorWithSRGBRed:1.0 green:0.75 blue:0.08 alpha:1.0]
        symbol:@"−"
        action:@selector(minimizeWindow:)];
    NSButton *zoom = [self trafficLightWithFrame:NSMakeRect(66, 616, 14, 14)
        color:[NSColor colorWithWhite:0.76 alpha:1.0]
        symbol:@"+"
        action:NULL];
    [parent addSubview:close];
    [parent addSubview:minimize];
    [parent addSubview:zoom];
}

- (void)closeWindow:(id)sender {
    [self.window close];
}

- (void)minimizeWindow:(id)sender {
    [self.window miniaturize:sender];
}

- (void)buildHeaderInView:(NSView *)parent {
    NSImage *powerImage = [NSImage imageWithSystemSymbolName:@"power" accessibilityDescription:@"电源"];
    self.headerIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(16, 16, 24, 24)];
    self.headerIcon.image = [powerImage imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:23 weight:NSFontWeightSemibold]];
    self.headerIcon.contentTintColor = NSColor.labelColor;

    NSView *iconContent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 56, 56)];
    [iconContent addSubview:self.headerIcon];
    NSGlassEffectView *iconGlass = [[NSGlassEffectView alloc] initWithFrame:NSMakeRect(42, 512, 56, 56)];
    iconGlass.style = NSGlassEffectViewStyleClear;
    iconGlass.cornerRadius = 18;
    iconGlass.tintColor = nil;
    iconGlass.contentView = iconContent;

    NSTextField *title = [NSTextField labelWithString:@"电源快捷按钮"];
    title.font = [NSFont systemFontOfSize:27 weight:NSFontWeightBold];
    title.textColor = NSColor.labelColor;
    title.frame = NSMakeRect(113, 536, 400, 34);

    NSTextField *subtitle = [NSTextField labelWithString:@"轻触一下，控制这台 Mac"];
    subtitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
    subtitle.textColor = NSColor.secondaryLabelColor;
    subtitle.frame = NSMakeRect(113, 512, 400, 22);

    [parent addSubview:iconGlass];
    [parent addSubview:title];
    [parent addSubview:subtitle];
}

- (void)buildControlsInView:(NSView *)parent {
    self.primaryGlass = [self glassCard:@"一键黑屏" symbol:@"display" action:@selector(turnOffDisplay:) size:NSMakeSize(516, 92) primary:YES iconColor:nil];
    self.lockGlass = [self glassCard:@"锁定屏幕" symbol:@"lock.fill" action:@selector(lockScreen:) size:NSMakeSize(252, 104) primary:NO iconColor:nil];
    self.sleepGlass = [self glassCard:@"进入睡眠" symbol:@"moon.zzz.fill" action:@selector(sleepMac:) size:NSMakeSize(252, 104) primary:NO iconColor:nil];
    self.restartGlass = [self glassCard:@"重新启动" symbol:@"arrow.clockwise" action:@selector(restartMac:) size:NSMakeSize(252, 104) primary:NO iconColor:nil];
    self.shutdownGlass = [self glassCard:@"关机" symbol:@"power" action:@selector(shutdownMac:) size:NSMakeSize(252, 104) primary:NO iconColor:nil];

    NSView *controls = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 516, 326)];
    self.primaryGlass.frame = NSMakeRect(0, 234, 516, 92);
    self.lockGlass.frame = NSMakeRect(0, 118, 252, 104);
    self.sleepGlass.frame = NSMakeRect(264, 118, 252, 104);
    self.restartGlass.frame = NSMakeRect(0, 0, 252, 104);
    self.shutdownGlass.frame = NSMakeRect(264, 0, 252, 104);
    [controls addSubview:self.primaryGlass];
    [controls addSubview:self.lockGlass];
    [controls addSubview:self.sleepGlass];
    [controls addSubview:self.restartGlass];
    [controls addSubview:self.shutdownGlass];

    NSGlassEffectContainerView *container = [[NSGlassEffectContainerView alloc] initWithFrame:NSMakeRect(28, 120, 516, 326)];
    container.spacing = 12;
    container.contentView = controls;
    [parent addSubview:container];
}

- (NSView *)glassCard:(NSString *)title symbol:(NSString *)symbol action:(SEL)action size:(NSSize)size primary:(BOOL)primary iconColor:(NSColor *)iconColor {
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];

    NSImage *symbolImage = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
    NSImageView *icon = [[NSImageView alloc] init];
    icon.image = [symbolImage imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:primary ? 21 : 20 weight:NSFontWeightSemibold]];
    icon.contentTintColor = iconColor ?: NSColor.labelColor;

    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold];
    label.textColor = NSColor.labelColor;
    NSTextField *countdownLabel = nil;

    if (primary) {
        icon.frame = NSMakeRect(22, 32, 28, 28);
        label.frame = NSMakeRect(67, 34, 240, 25);
    } else {
        icon.frame = NSMakeRect(20, size.height - 48, 28, 28);
        label.frame = NSMakeRect(20, 16, size.width - 40, 25);
        if ([title isEqualToString:@"关机"]) {
            label.frame = NSMakeRect(20, 16, 62, 25);
            countdownLabel = [NSTextField labelWithString:@""];
            countdownLabel.frame = NSMakeRect(82, 17, size.width - 102, 22);
            countdownLabel.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightMedium];
            countdownLabel.textColor = NSColor.secondaryLabelColor;
            countdownLabel.alignment = NSTextAlignmentRight;
            countdownLabel.hidden = YES;
            self.shutdownCountdownLabel = countdownLabel;
        }
    }
    NSView *hoverOverlay = [[NSView alloc] initWithFrame:content.bounds];
    hoverOverlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    hoverOverlay.wantsLayer = YES;
    NSColor *hoverColor = [NSColor colorWithWhite:1.0 alpha:1.0];
    CGFloat baseOverlayAlpha = 0.0;
    if ([title isEqualToString:@"一键黑屏"]) {
        hoverColor = [NSColor colorWithSRGBRed:1.0 green:0.78 blue:0.87 alpha:1.0];
        baseOverlayAlpha = 0.18;
    } else if ([title isEqualToString:@"锁定屏幕"]) {
        hoverColor = [NSColor colorWithWhite:0.12 alpha:1.0];
        baseOverlayAlpha = 0.05;
    } else if ([title isEqualToString:@"进入睡眠"]) {
        hoverColor = [NSColor colorWithSRGBRed:0.52 green:0.55 blue:1.0 alpha:1.0];
        baseOverlayAlpha = 0.16;
    } else if ([title isEqualToString:@"重新启动"]) {
        hoverColor = [NSColor colorWithSRGBRed:1.0 green:0.58 blue:0.20 alpha:1.0];
        baseOverlayAlpha = 0.16;
    } else if ([title isEqualToString:@"关机"]) {
        hoverColor = [NSColor colorWithSRGBRed:1.0 green:0.30 blue:0.34 alpha:1.0];
        baseOverlayAlpha = 0.16;
    }
    hoverOverlay.layer.backgroundColor = hoverColor.CGColor;
    hoverOverlay.layer.cornerRadius = primary ? 24 : 22;
    hoverOverlay.alphaValue = baseOverlayAlpha;
    [content addSubview:hoverOverlay];

    content.wantsLayer = YES;
    content.layer.masksToBounds = YES;
    content.layer.cornerRadius = primary ? 24 : 22;

    NSView *shineView = [[NSView alloc] initWithFrame:NSMakeRect(-size.width * 0.30, 0, size.width * 0.30, size.height)];
    shineView.wantsLayer = YES;
    CAGradientLayer *shineGradient = [CAGradientLayer layer];
    shineGradient.frame = shineView.bounds;
    shineGradient.colors = @[
        (__bridge id)[NSColor colorWithWhite:1.0 alpha:0.0].CGColor,
        (__bridge id)[NSColor colorWithWhite:1.0 alpha:0.72].CGColor,
        (__bridge id)[NSColor colorWithWhite:1.0 alpha:0.0].CGColor
    ];
    shineGradient.locations = @[@0.0, @0.5, @1.0];
    shineGradient.startPoint = CGPointMake(0.0, 0.0);
    shineGradient.endPoint = CGPointMake(1.0, 1.0);
    shineView.layer = shineGradient;
    shineView.alphaValue = 0.0;
    [content addSubview:shineView];

    NSView *borderOverlay = [[NSView alloc] initWithFrame:content.bounds];
    borderOverlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    borderOverlay.wantsLayer = YES;
    borderOverlay.layer.borderWidth = 1.0;
    borderOverlay.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.95].CGColor;
    borderOverlay.layer.cornerRadius = primary ? 24 : 22;
    borderOverlay.alphaValue = 0.20;
    [content addSubview:borderOverlay];

    [content addSubview:icon];
    [content addSubview:label];
    if (countdownLabel != nil) {
        [content addSubview:countdownLabel];
    }

    HoverButton *hitArea = [[HoverButton alloc] initWithFrame:content.bounds];
    hitArea.title = @"";
    hitArea.bordered = NO;
    hitArea.hoverOverlay = hoverOverlay;
    hitArea.hoverBorder = borderOverlay;
    hitArea.shineView = shineView;
    hitArea.baseOverlayAlpha = baseOverlayAlpha;
    hitArea.target = self;
    hitArea.action = action;
    hitArea.toolTip = title;
    hitArea.accessibilityLabel = title;
    if ([title isEqualToString:@"关机"]) {
        hitArea.rightClickAction = @selector(showShutdownTimerMenu:);
        hitArea.toolTip = @"左键关机 · 右键定时";
    }
    hitArea.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:hitArea];

    NSGlassEffectView *glass = [[NSGlassEffectView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    glass.style = NSGlassEffectViewStyleClear;
    glass.cornerRadius = primary ? 24 : 22;
    if ([title isEqualToString:@"重新启动"]) {
        glass.tintColor = [NSColor colorWithSRGBRed:1.0 green:0.58 blue:0.20 alpha:0.20];
    } else if ([title isEqualToString:@"关机"]) {
        glass.tintColor = [NSColor colorWithSRGBRed:1.0 green:0.30 blue:0.34 alpha:0.20];
    } else {
        glass.tintColor = nil;
    }
    glass.contentView = content;
    glass.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSView *cardWrapper = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    [cardWrapper addSubview:glass];
    hitArea.cardView = cardWrapper;
    return cardWrapper;
}

- (void)turnOffDisplay:(id)sender {
    [self run:@"/usr/bin/pmset" arguments:@[@"displaysleepnow"]];
}

- (void)lockScreen:(id)sender {
    void *loginFramework = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY);
    if (loginFramework != NULL) {
        void (*lockNow)(void) = (void (*)(void))dlsym(loginFramework, "SACLockScreenImmediate");
        if (lockNow != NULL) {
            lockNow();
            dlclose(loginFramework);
            return;
        }
        dlclose(loginFramework);
    }
    [self runAppleScript:@"tell application \"System Events\" to keystroke \"q\" using {control down, command down}"];
}

- (void)sleepMac:(id)sender {
    [self run:@"/usr/bin/pmset" arguments:@[@"sleepnow"]];
}

- (void)restartMac:(id)sender {
    if ([self confirm:@"确定要重新启动吗？" detail:@"未保存的内容可能会丢失。" button:@"重新启动"]) {
        [self runAppleScript:@"tell application \"System Events\" to restart"];
    }
}

- (void)shutdownMac:(id)sender {
    if ([self confirm:@"确定要关机吗？" detail:@"未保存的内容可能会丢失。" button:@"关机"]) {
        [self runAppleScript:@"tell application \"System Events\" to shut down"];
    }
}

- (void)showShutdownTimerMenu:(id)sender {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"定时关机"];
    NSArray<NSDictionary *> *options = @[
        @{@"title": @"15 分钟后", @"minutes": @15},
        @{@"title": @"30 分钟后", @"minutes": @30},
        @{@"title": @"1 小时后", @"minutes": @60},
        @{@"title": @"2 小时后", @"minutes": @120}
    ];
    for (NSDictionary *option in options) {
        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:option[@"title"]
            action:@selector(scheduleShutdown:)
            keyEquivalent:@""];
        item.target = self;
        item.representedObject = option[@"minutes"];
        [menu addItem:item];
    }
    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *custom = [[NSMenuItem alloc]
        initWithTitle:@"自定义时间…"
        action:@selector(scheduleCustomShutdown:)
        keyEquivalent:@""];
    custom.target = self;
    [menu addItem:custom];

    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *cancel = [[NSMenuItem alloc]
        initWithTitle:@"取消定时关机"
        action:@selector(cancelScheduledShutdown:)
        keyEquivalent:@""];
    cancel.target = self;
    [menu addItem:cancel];

    [NSMenu popUpContextMenu:menu withEvent:NSApp.currentEvent forView:sender];
}

- (void)scheduleShutdown:(NSMenuItem *)sender {
    [self scheduleShutdownAfterMinutes:[sender.representedObject integerValue]];
}

- (void)scheduleCustomShutdown:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"自定义定时关机";
    alert.informativeText = @"输入多少分钟后关机（1–1440）。";
    [alert addButtonWithTitle:@"继续"];
    [alert addButtonWithTitle:@"取消"];

    NSTextField *minutesField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 220, 28)];
    minutesField.placeholderString = @"例如：45";
    minutesField.stringValue = @"45";
    alert.accessoryView = minutesField;
    [alert.window setInitialFirstResponder:minutesField];

    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }
    NSInteger minutes = minutesField.integerValue;
    if (minutes < 1 || minutes > 1440) {
        NSAlert *error = [[NSAlert alloc] init];
        error.messageText = @"时间无效";
        error.informativeText = @"请输入 1 到 1440 之间的分钟数。";
        error.alertStyle = NSAlertStyleWarning;
        [error runModal];
        return;
    }
    [self scheduleShutdownAfterMinutes:minutes];
}

- (void)scheduleShutdownAfterMinutes:(NSInteger)minutes {
    NSDate *shutdownDate = [NSDate dateWithTimeIntervalSinceNow:minutes * 60.0];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm";
    NSString *timeText = [formatter stringFromDate:shutdownDate];
    NSString *detail = [NSString stringWithFormat:@"这台 Mac 将在 %@（约 %ld 分钟后）关机。", timeText, (long)minutes];
    if (![self confirm:@"设置定时关机？" detail:detail button:@"设置"]) {
        return;
    }

    NSString *command = [NSString stringWithFormat:
        @"/usr/bin/pkill -TERM -x shutdown 2>/dev/null || true; "
         "/bin/rm -f /var/run/nologin; "
         "/usr/bin/nohup /sbin/shutdown -h +%ld '定时关机' "
         "</dev/null >/dev/null 2>&1 &",
        (long)minutes];
    if ([self runPrivilegedShellCommand:command]) {
        shutdownDate = [NSDate dateWithTimeIntervalSinceNow:minutes * 60.0];
        [self startShutdownCountdownUntil:shutdownDate];
        timeText = [formatter stringFromDate:shutdownDate];
        NSAlert *success = [[NSAlert alloc] init];
        success.messageText = @"定时关机已设置";
        success.informativeText = [NSString stringWithFormat:@"预计关机时间：%@", timeText];
        [success runModal];
    }
}

- (void)cancelScheduledShutdown:(id)sender {
    if (![self confirm:@"取消定时关机？" detail:@"已安排的系统关机任务将被取消。" button:@"取消定时"]) {
        return;
    }
    NSString *command =
        @"/usr/bin/pkill -TERM -x shutdown 2>/dev/null || true; "
         "/bin/rm -f /var/run/nologin";
    if ([self runPrivilegedShellCommand:command]) {
        [self clearShutdownCountdown];
        NSAlert *success = [[NSAlert alloc] init];
        success.messageText = @"定时关机已取消";
        [success runModal];
    }
}

- (void)restoreShutdownCountdown {
    NSDate *savedDate = [NSUserDefaults.standardUserDefaults objectForKey:@"ScheduledShutdownDate"];
    if ([savedDate isKindOfClass:NSDate.class] && [savedDate timeIntervalSinceNow] > 0) {
        [self startShutdownCountdownUntil:savedDate];
    } else {
        [self clearShutdownCountdown];
    }
}

- (void)startShutdownCountdownUntil:(NSDate *)date {
    self.scheduledShutdownDate = date;
    [NSUserDefaults.standardUserDefaults setObject:date forKey:@"ScheduledShutdownDate"];
    [self.shutdownCountdownTimer invalidate];
    self.shutdownCountdownTimer = [NSTimer
        scheduledTimerWithTimeInterval:1.0
        target:self
        selector:@selector(updateShutdownCountdown:)
        userInfo:nil
        repeats:YES];
    [self updateShutdownCountdown:nil];
}

- (void)updateShutdownCountdown:(NSTimer *)timer {
    NSTimeInterval remaining = [self.scheduledShutdownDate timeIntervalSinceNow];
    if (remaining <= 0) {
        [self clearShutdownCountdown];
        return;
    }

    NSInteger totalSeconds = (NSInteger)ceil(remaining);
    NSInteger hours = totalSeconds / 3600;
    NSInteger minutes = (totalSeconds % 3600) / 60;
    NSInteger seconds = totalSeconds % 60;
    if (hours > 0) {
        self.shutdownCountdownLabel.stringValue =
            [NSString stringWithFormat:@"剩余 %ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
    } else {
        self.shutdownCountdownLabel.stringValue =
            [NSString stringWithFormat:@"剩余 %ld:%02ld", (long)minutes, (long)seconds];
    }
    self.shutdownCountdownLabel.hidden = NO;
}

- (void)clearShutdownCountdown {
    [self.shutdownCountdownTimer invalidate];
    self.shutdownCountdownTimer = nil;
    self.scheduledShutdownDate = nil;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"ScheduledShutdownDate"];
    self.shutdownCountdownLabel.stringValue = @"";
    self.shutdownCountdownLabel.hidden = YES;
}

- (BOOL)runPrivilegedShellCommand:(NSString *)command {
    AuthorizationRef authorization = NULL;
    OSStatus status = AuthorizationCreate(
        NULL,
        kAuthorizationEmptyEnvironment,
        kAuthorizationFlagDefaults,
        &authorization);
    if (status == errAuthorizationSuccess) {
        const char *toolPath = "/bin/sh";
        AuthorizationItem item = {
            kAuthorizationRightExecute,
            (UInt32)strlen(toolPath),
            (void *)toolPath,
            0
        };
        AuthorizationRights rights = {1, &item};
        AuthorizationFlags flags =
            kAuthorizationFlagInteractionAllowed |
            kAuthorizationFlagPreAuthorize |
            kAuthorizationFlagExtendRights;
        status = AuthorizationCopyRights(authorization, &rights, NULL, flags, NULL);
        if (status == errAuthorizationSuccess) {
            const char *commandText = command.UTF8String;
            char *arguments[] = {"-c", (char *)commandText, NULL};
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            status = AuthorizationExecuteWithPrivileges(
                authorization,
                toolPath,
                kAuthorizationFlagDefaults,
                arguments,
                NULL);
#pragma clang diagnostic pop
        }
        AuthorizationFree(authorization, kAuthorizationFlagDefaults);
    }

    if (status == errAuthorizationSuccess) {
        return YES;
    }
    if (status == errAuthorizationCanceled) {
        return NO;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"定时操作未能执行";
    alert.informativeText = [NSString stringWithFormat:@"系统授权失败（错误 %d）。", (int)status];
    alert.alertStyle = NSAlertStyleCritical;
    [alert runModal];
    return NO;
}

- (BOOL)confirm:(NSString *)title detail:(NSString *)detail button:(NSString *)button {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = detail;
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:button];
    [alert addButtonWithTitle:@"取消"];
    return [alert runModal] == NSAlertFirstButtonReturn;
}

- (void)runAppleScript:(NSString *)source {
    [self run:@"/usr/bin/osascript" arguments:@[@"-e", source]];
}

- (void)run:(NSString *)executable arguments:(NSArray<NSString *> *)arguments {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = arguments;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"操作未能执行";
        alert.informativeText = error.localizedDescription;
        alert.alertStyle = NSAlertStyleCritical;
        [alert runModal];
    }
}

@end


int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        PowerButtonsDelegate *delegate = [[PowerButtonsDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
