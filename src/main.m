// MiddleClick: a click with three fingers on the trackpad becomes a middle click.
//
// The private MultitouchSupport framework reports how many fingers touch the
// trackpad; an event tap rewrites clicks made while three are down.

#import <Cocoa/Cocoa.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
#import <os/log.h>
#import <stdatomic.h>
#import "click.h"

#pragma mark - MultitouchSupport

typedef void *MTDeviceRef;
typedef int (*MTFrameCallback)(MTDeviceRef device, void *touches, int count, double timestamp, int frame);

static CFMutableArrayRef (*MTDeviceCreateList)(void);
static void (*MTRegisterContactFrameCallback)(MTDeviceRef, MTFrameCallback);
static void (*MTUnregisterContactFrameCallback)(MTDeviceRef, MTFrameCallback);
static int (*MTDeviceStart)(MTDeviceRef, int);
static int (*MTDeviceStop)(MTDeviceRef);
static int (*MTDeviceGetFamilyID)(MTDeviceRef, int *);

static bool loadMultitouch(void) {
    void *lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY);
    if (!lib) return false;
    MTDeviceCreateList = dlsym(lib, "MTDeviceCreateList");
    MTRegisterContactFrameCallback = dlsym(lib, "MTRegisterContactFrameCallback");
    MTUnregisterContactFrameCallback = dlsym(lib, "MTUnregisterContactFrameCallback");
    MTDeviceStart = dlsym(lib, "MTDeviceStart");
    MTDeviceStop = dlsym(lib, "MTDeviceStop");
    MTDeviceGetFamilyID = dlsym(lib, "MTDeviceGetFamilyID");
    return MTDeviceCreateList && MTRegisterContactFrameCallback && MTUnregisterContactFrameCallback
        && MTDeviceStart && MTDeviceStop && MTDeviceGetFamilyID;
}

// Magic Mouse reports touches too; fingers resting on it must not change its clicks.
static bool isMagicMouse(MTDeviceRef device) {
    int family = 0;
    MTDeviceGetFamilyID(device, &family);
    return family == 112 || family == 113;
}

#pragma mark - Clicks

static os_log_t logger;
static _Atomic int fingerCount; // written on the multitouch thread
static CGEventType middlePress;  // main thread only
static CFMachPortRef eventTap;

static int touchFrame(MTDeviceRef device, void *touches, int count, double timestamp, int frame) {
    atomic_store_explicit(&fingerCount, count, memory_order_relaxed);
    return 0;
}

static CGEventRef tapEvent(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        CGEventTapEnable(eventTap, true);
        return event;
    }
    int fingers = atomic_load_explicit(&fingerCount, memory_order_relaxed);
    if (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown) {
        os_log_debug(logger, "%{public}s click with %d finger(s)", type == kCGEventLeftMouseDown ? "left" : "right", fingers);
    }
    convertClick(event, fingers, &middlePress);
    return event;
}

#pragma mark - App

// Three fingertips on the trackpad, the middle finger a bit higher.
static NSImage *menuBarIcon(void) {
    NSImage *image = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        CGFloat d = 4.6;
        NSPoint tips[] = {{3, 8}, {9, 10.2}, {15, 8}};
        [NSColor.blackColor set];
        for (int i = 0; i < 3; i++) {
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(tips[i].x - d / 2, tips[i].y - d / 2, d, d)] fill];
        }
        return YES;
    }];
    image.template = YES;
    image.accessibilityDescription = @"MiddleClick";
    return image;
}

@interface AppDelegate : NSObject <NSApplicationDelegate>
- (void)scheduleTouchRestart;
@end

static void drain(io_iterator_t iterator) {
    io_object_t service;
    while ((service = IOIteratorNext(iterator))) IOObjectRelease(service);
}

static void devicesAdded(void *delegate, io_iterator_t iterator) {
    drain(iterator);
    [(__bridge AppDelegate *)delegate scheduleTouchRestart];
}

static void displaysChanged(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *delegate) {
    if (flags & kCGDisplayBeginConfigurationFlag) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [(__bridge AppDelegate *)delegate scheduleTouchRestart]; });
}

@implementation AppDelegate {
    NSStatusItem *_statusItem;
    NSMenuItem *_statusLine;
    NSMenuItem *_accessItem;
    int _shownActive;
    CFMutableArrayRef _devices;
    CFRunLoopSourceRef _tapSource;
    id<NSObject> _activity;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    // App Nap would delay the event tap, and with it every click on the system.
    _activity = [NSProcessInfo.processInfo beginActivityWithOptions:NSActivityUserInitiatedAllowingIdleSystemSleep
                                                              reason:@"Handles trackpad clicks"];
    [self setUpStatusItem];
    if (!loadMultitouch()) {
        os_log_error(logger, "MultitouchSupport.framework is unavailable");
        _statusLine.title = @"Can't read the trackpad on this Mac";
        _accessItem.hidden = YES;
        return;
    }
    [self startTouchDevices];
    [self watchForDeviceChanges];

    // Prompts for Accessibility access; the timer notices when it is granted or revoked.
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge id)kAXTrustedCheckOptionPrompt: @YES});
    [self checkAccess];
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(checkAccess)
                                                    userInfo:nil repeats:YES];
    timer.tolerance = 1;
}

#pragma mark Menu bar

- (void)setUpStatusItem {
    _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    _statusItem.button.image = menuBarIcon();
    _statusItem.button.appearsDisabled = YES;

    NSMenu *menu = [NSMenu new];
    _statusLine = [menu addItemWithTitle:@"Starting…" action:nil keyEquivalent:@""];
    _accessItem = [menu addItemWithTitle:@"Open Accessibility Settings…" action:@selector(openAccessibilitySettings)
                           keyEquivalent:@""];
    _accessItem.target = self;
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Quit MiddleClick" action:@selector(terminate:) keyEquivalent:@"q"];
    _statusItem.menu = menu;
    _shownActive = -1;
}

- (void)showActive:(BOOL)active {
    if (active == _shownActive) return;
    _shownActive = active;
    _statusItem.button.appearsDisabled = !active;
    _statusLine.title = active ? @"Three-finger click → middle click" : @"Waiting for Accessibility access";
    _accessItem.hidden = active;
}

- (void)openAccessibilitySettings {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    [NSWorkspace.sharedWorkspace openURL:url];
}

#pragma mark Event tap

- (void)checkAccess {
    BOOL trusted = AXIsProcessTrusted();
    if (trusted && !eventTap) [self startEventTap];
    if (!trusted && eventTap) [self stopEventTap];
    [self showActive:eventTap && CGEventTapIsEnabled(eventTap)];
}

- (void)startEventTap {
    // Right-button events too: macOS can report a three-finger click as a two-finger one.
    CGEventMask mask = CGEventMaskBit(kCGEventLeftMouseDown) | CGEventMaskBit(kCGEventLeftMouseDragged)
                     | CGEventMaskBit(kCGEventLeftMouseUp) | CGEventMaskBit(kCGEventRightMouseDown)
                     | CGEventMaskBit(kCGEventRightMouseDragged) | CGEventMaskBit(kCGEventRightMouseUp);
    eventTap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, mask, tapEvent, NULL);
    if (!eventTap) return; // access not in effect yet; the timer retries
    _tapSource = CFMachPortCreateRunLoopSource(NULL, eventTap, 0);
    // Common modes keep clicks flowing while our own menu is open.
    CFRunLoopAddSource(CFRunLoopGetMain(), _tapSource, kCFRunLoopCommonModes);
    os_log(logger, "event tap started");
}

- (void)stopEventTap {
    CFRunLoopRemoveSource(CFRunLoopGetMain(), _tapSource, kCFRunLoopCommonModes);
    CFRelease(_tapSource);
    _tapSource = NULL;
    CFMachPortInvalidate(eventTap);
    CFRelease(eventTap);
    eventTap = NULL;
    middlePress = kCGEventNull;
    os_log(logger, "event tap stopped: Accessibility access revoked");
}

#pragma mark Trackpads

- (void)startTouchDevices {
    [self stopTouchDevices];
    _devices = MTDeviceCreateList();
    if (!_devices) return;
    int count = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(_devices); i++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(_devices, i);
        if (isMagicMouse(device)) continue;
        MTRegisterContactFrameCallback(device, touchFrame);
        if (MTDeviceStart(device, 0) == 0) count++;
    }
    os_log(logger, "listening to %d trackpad(s)", count);
}

- (void)stopTouchDevices {
    if (!_devices) return;
    for (CFIndex i = 0; i < CFArrayGetCount(_devices); i++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(_devices, i);
        if (isMagicMouse(device)) continue;
        MTUnregisterContactFrameCallback(device, touchFrame);
        MTDeviceStop(device);
    }
    CFRelease(_devices);
    _devices = NULL;
    atomic_store_explicit(&fingerCount, 0, memory_order_relaxed);
}

// Sleep, reconnecting a trackpad and display changes (clamshell mode) can leave
// the opened devices silent, so reopen them after any of these.
- (void)watchForDeviceChanges {
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidWakeNotification object:nil
                                                                  queue:nil usingBlock:^(NSNotification *n) {
        [self scheduleTouchRestart];
    }];
    CGDisplayRegisterReconfigurationCallback(displaysChanged, (__bridge void *)self);

    IONotificationPortRef port = IONotificationPortCreate(MACH_PORT_NULL);
    CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port), kCFRunLoopDefaultMode);
    // The service classes MultitouchSupport opens devices from.
    for (NSString *name in @[@"AppleMultitouchDevice", @"AppleUSBMultitouchDriver", @"AppleMultitouchSPI"]) {
        io_iterator_t iterator;
        if (IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching(name.UTF8String),
                                             devicesAdded, (__bridge void *)self, &iterator) == KERN_SUCCESS) {
            drain(iterator); // arms the notification; these devices are already open
        }
    }
}

// Wake and reconnect events come in bursts; restart once they settle.
- (void)scheduleTouchRestart {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(startTouchDevices) object:nil];
    [self performSelector:@selector(startTouchDevices) withObject:nil afterDelay:1];
}

@end

int main(void) {
    @autoreleasepool {
        logger = os_log_create("io.github.dimamingtrick.middleclick", "app");
        NSApplication *app = NSApplication.sharedApplication;
        app.activationPolicy = NSApplicationActivationPolicyAccessory;
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
