// Tests for the click conversion logic. Run by build.sh.
#include <stdio.h>
#include "../src/click.h"

static int failures;

#define EXPECT(expr) do { \
    if (!(expr)) { failures++; fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #expr); } \
} while (0)

static void threeFingerClickBecomesMiddleClick(void) {
    CGEventType press = kCGEventNull;
    EXPECT(middleClickType(kCGEventLeftMouseDown, 3, &press) == kCGEventOtherMouseDown);
    EXPECT(middleClickType(kCGEventLeftMouseDragged, 3, &press) == kCGEventOtherMouseDragged);
    EXPECT(middleClickType(kCGEventLeftMouseUp, 3, &press) == kCGEventOtherMouseUp);
}

// macOS can take three fingers for a two-finger click, e.g. when they stand in a triangle.
static void threeFingerRightClickBecomesMiddleClick(void) {
    CGEventType press = kCGEventNull;
    EXPECT(middleClickType(kCGEventRightMouseDown, 3, &press) == kCGEventOtherMouseDown);
    EXPECT(middleClickType(kCGEventRightMouseDragged, 3, &press) == kCGEventOtherMouseDragged);
    EXPECT(middleClickType(kCGEventRightMouseUp, 3, &press) == kCGEventOtherMouseUp);
}

static void otherFingerCountsStayNormalClicks(void) {
    int counts[] = {0, 1, 2, 4, 5};
    for (unsigned i = 0; i < sizeof counts / sizeof *counts; i++) {
        CGEventType press = kCGEventNull;
        EXPECT(middleClickType(kCGEventLeftMouseDown, counts[i], &press) == kCGEventLeftMouseDown);
        EXPECT(middleClickType(kCGEventLeftMouseDragged, counts[i], &press) == kCGEventLeftMouseDragged);
        EXPECT(middleClickType(kCGEventLeftMouseUp, counts[i], &press) == kCGEventLeftMouseUp);
        EXPECT(middleClickType(kCGEventRightMouseDown, counts[i], &press) == kCGEventRightMouseDown);
        EXPECT(middleClickType(kCGEventRightMouseDragged, counts[i], &press) == kCGEventRightMouseDragged);
        EXPECT(middleClickType(kCGEventRightMouseUp, counts[i], &press) == kCGEventRightMouseUp);
    }
}

static void releaseFollowsThePressWhenFingersLift(void) {
    CGEventType press = kCGEventNull;
    middleClickType(kCGEventLeftMouseDown, 3, &press);
    EXPECT(middleClickType(kCGEventLeftMouseDragged, 1, &press) == kCGEventOtherMouseDragged);
    EXPECT(middleClickType(kCGEventLeftMouseUp, 0, &press) == kCGEventOtherMouseUp);
}

static void clickAfterMiddleClickIsNormal(void) {
    CGEventType press = kCGEventNull;
    middleClickType(kCGEventRightMouseDown, 3, &press);
    middleClickType(kCGEventRightMouseUp, 3, &press);
    EXPECT(middleClickType(kCGEventRightMouseDown, 2, &press) == kCGEventRightMouseDown);
    EXPECT(middleClickType(kCGEventRightMouseUp, 2, &press) == kCGEventRightMouseUp);
    EXPECT(middleClickType(kCGEventLeftMouseDown, 1, &press) == kCGEventLeftMouseDown);
    EXPECT(middleClickType(kCGEventLeftMouseUp, 1, &press) == kCGEventLeftMouseUp);
}

// If a release was missed (e.g. the tap was briefly disabled), the next normal
// click must not be turned into a middle release.
static void normalPressClearsAMissedRelease(void) {
    CGEventType press = kCGEventNull;
    middleClickType(kCGEventLeftMouseDown, 3, &press);
    EXPECT(middleClickType(kCGEventLeftMouseDown, 1, &press) == kCGEventLeftMouseDown);
    EXPECT(middleClickType(kCGEventLeftMouseUp, 1, &press) == kCGEventLeftMouseUp);
}

static void pressStaysLeftWhenAThirdFingerLands(void) {
    CGEventType press = kCGEventNull;
    middleClickType(kCGEventLeftMouseDown, 2, &press);
    EXPECT(middleClickType(kCGEventLeftMouseDragged, 3, &press) == kCGEventLeftMouseDragged);
    EXPECT(middleClickType(kCGEventLeftMouseUp, 3, &press) == kCGEventLeftMouseUp);
}

// Only the button pressed with three fingers becomes the middle one; a button
// already held on a mouse keeps its drags and release.
static void otherButtonIsLeftAlone(void) {
    CGEventType press = kCGEventNull;
    middleClickType(kCGEventRightMouseDown, 3, &press);
    EXPECT(middleClickType(kCGEventLeftMouseDragged, 3, &press) == kCGEventLeftMouseDragged);
    EXPECT(middleClickType(kCGEventLeftMouseUp, 3, &press) == kCGEventLeftMouseUp);
    EXPECT(middleClickType(kCGEventRightMouseUp, 3, &press) == kCGEventOtherMouseUp);

    middleClickType(kCGEventLeftMouseDown, 3, &press);
    EXPECT(middleClickType(kCGEventRightMouseDragged, 3, &press) == kCGEventRightMouseDragged);
    EXPECT(middleClickType(kCGEventRightMouseUp, 3, &press) == kCGEventRightMouseUp);
    EXPECT(middleClickType(kCGEventLeftMouseUp, 3, &press) == kCGEventOtherMouseUp);
}

static void otherEventsPassThrough(void) {
    CGEventType press = kCGEventNull;
    middleClickType(kCGEventLeftMouseDown, 3, &press);
    EXPECT(middleClickType(kCGEventMouseMoved, 3, &press) == kCGEventMouseMoved);
    EXPECT(middleClickType(kCGEventOtherMouseDown, 3, &press) == kCGEventOtherMouseDown);
    EXPECT(middleClickType(kCGEventLeftMouseUp, 3, &press) == kCGEventOtherMouseUp);
}

static void convertedEventsUseTheMiddleButton(void) {
    CGEventType types[] = {kCGEventLeftMouseDown, kCGEventRightMouseDown};
    CGMouseButton buttons[] = {kCGMouseButtonLeft, kCGMouseButtonRight};
    for (int i = 0; i < 2; i++) {
        CGEventType press = kCGEventNull;
        CGEventRef event = CGEventCreateMouseEvent(NULL, types[i], CGPointZero, buttons[i]);
        convertClick(event, 3, &press);
        EXPECT(CGEventGetType(event) == kCGEventOtherMouseDown);
        EXPECT(CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber) == kCGMouseButtonCenter);
        CFRelease(event);
    }
}

static void unconvertedEventsAreLeftAlone(void) {
    CGEventType types[] = {kCGEventLeftMouseDown, kCGEventRightMouseDown};
    CGMouseButton buttons[] = {kCGMouseButtonLeft, kCGMouseButtonRight};
    int fingers[] = {1, 2};
    for (int i = 0; i < 2; i++) {
        CGEventType press = kCGEventNull;
        CGEventRef event = CGEventCreateMouseEvent(NULL, types[i], CGPointZero, buttons[i]);
        convertClick(event, fingers[i], &press);
        EXPECT(CGEventGetType(event) == types[i]);
        EXPECT(CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber) == buttons[i]);
        CFRelease(event);
    }
}

int main(void) {
    threeFingerClickBecomesMiddleClick();
    threeFingerRightClickBecomesMiddleClick();
    otherFingerCountsStayNormalClicks();
    releaseFollowsThePressWhenFingersLift();
    clickAfterMiddleClickIsNormal();
    normalPressClearsAMissedRelease();
    pressStaysLeftWhenAThirdFingerLands();
    otherButtonIsLeftAlone();
    otherEventsPassThrough();
    convertedEventsUseTheMiddleButton();
    unconvertedEventsAreLeftAlone();
    if (failures) {
        fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    puts("click tests passed");
    return 0;
}
