// Tests for the click conversion logic. Run by build.sh.
#include <stdio.h>
#include "../src/click.h"

static int failures;

#define EXPECT(expr) do { \
    if (!(expr)) { failures++; fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #expr); } \
} while (0)

static void threeFingerClickBecomesMiddleClick(void) {
    bool middle = false;
    EXPECT(middleClickType(kCGEventLeftMouseDown, 3, &middle) == kCGEventOtherMouseDown);
    EXPECT(middleClickType(kCGEventLeftMouseDragged, 3, &middle) == kCGEventOtherMouseDragged);
    EXPECT(middleClickType(kCGEventLeftMouseUp, 3, &middle) == kCGEventOtherMouseUp);
}

static void otherFingerCountsStayLeftClicks(void) {
    int counts[] = {0, 1, 2, 4, 5};
    for (unsigned i = 0; i < sizeof counts / sizeof *counts; i++) {
        bool middle = false;
        EXPECT(middleClickType(kCGEventLeftMouseDown, counts[i], &middle) == kCGEventLeftMouseDown);
        EXPECT(middleClickType(kCGEventLeftMouseDragged, counts[i], &middle) == kCGEventLeftMouseDragged);
        EXPECT(middleClickType(kCGEventLeftMouseUp, counts[i], &middle) == kCGEventLeftMouseUp);
    }
}

static void releaseFollowsThePressWhenFingersLift(void) {
    bool middle = false;
    middleClickType(kCGEventLeftMouseDown, 3, &middle);
    EXPECT(middleClickType(kCGEventLeftMouseDragged, 1, &middle) == kCGEventOtherMouseDragged);
    EXPECT(middleClickType(kCGEventLeftMouseUp, 0, &middle) == kCGEventOtherMouseUp);
}

static void clickAfterMiddleClickIsNormal(void) {
    bool middle = false;
    middleClickType(kCGEventLeftMouseDown, 3, &middle);
    middleClickType(kCGEventLeftMouseUp, 3, &middle);
    EXPECT(middleClickType(kCGEventLeftMouseDown, 1, &middle) == kCGEventLeftMouseDown);
    EXPECT(middleClickType(kCGEventLeftMouseUp, 1, &middle) == kCGEventLeftMouseUp);
}

// If a release was missed (e.g. the tap was briefly disabled), the next normal
// click must not be turned into a middle release.
static void normalPressClearsAMissedRelease(void) {
    bool middle = false;
    middleClickType(kCGEventLeftMouseDown, 3, &middle);
    EXPECT(middleClickType(kCGEventLeftMouseDown, 1, &middle) == kCGEventLeftMouseDown);
    EXPECT(middleClickType(kCGEventLeftMouseUp, 1, &middle) == kCGEventLeftMouseUp);
}

static void pressStaysLeftWhenAThirdFingerLands(void) {
    bool middle = false;
    middleClickType(kCGEventLeftMouseDown, 2, &middle);
    EXPECT(middleClickType(kCGEventLeftMouseDragged, 3, &middle) == kCGEventLeftMouseDragged);
    EXPECT(middleClickType(kCGEventLeftMouseUp, 3, &middle) == kCGEventLeftMouseUp);
}

static void otherEventsPassThrough(void) {
    bool middle = false;
    middleClickType(kCGEventLeftMouseDown, 3, &middle);
    EXPECT(middleClickType(kCGEventRightMouseDown, 3, &middle) == kCGEventRightMouseDown);
    EXPECT(middleClickType(kCGEventMouseMoved, 3, &middle) == kCGEventMouseMoved);
    EXPECT(middleClickType(kCGEventLeftMouseUp, 3, &middle) == kCGEventOtherMouseUp);
}

static void convertedEventUsesTheMiddleButton(void) {
    bool middle = false;
    CGEventRef event = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, CGPointZero, kCGMouseButtonLeft);
    convertClick(event, 3, &middle);
    EXPECT(CGEventGetType(event) == kCGEventOtherMouseDown);
    EXPECT(CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber) == kCGMouseButtonCenter);
    CFRelease(event);
}

static void unconvertedEventIsLeftAlone(void) {
    bool middle = false;
    CGEventRef event = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, CGPointZero, kCGMouseButtonLeft);
    convertClick(event, 1, &middle);
    EXPECT(CGEventGetType(event) == kCGEventLeftMouseDown);
    EXPECT(CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber) == kCGMouseButtonLeft);
    CFRelease(event);
}

int main(void) {
    threeFingerClickBecomesMiddleClick();
    otherFingerCountsStayLeftClicks();
    releaseFollowsThePressWhenFingersLift();
    clickAfterMiddleClickIsNormal();
    normalPressClearsAMissedRelease();
    pressStaysLeftWhenAThirdFingerLands();
    otherEventsPassThrough();
    convertedEventUsesTheMiddleButton();
    unconvertedEventIsLeftAlone();
    if (failures) {
        fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    puts("click tests passed");
    return 0;
}
