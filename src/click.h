#pragma once
#include <CoreGraphics/CoreGraphics.h>

// Returns the type a button event should have. A press made while exactly three
// fingers are on the trackpad becomes a middle-button press, and the drags and
// release of the same button follow it. macOS reports such a press as a left one,
// or as a right one when it takes the fingers for a two-finger click, e.g. when
// they stand in a triangle. *press carries the converted press between events
// (kCGEventLeftMouseDown or kCGEventRightMouseDown), or kCGEventNull.
static inline CGEventType middleClickType(CGEventType type, int fingers, CGEventType *press) {
    switch (type) {
    case kCGEventLeftMouseDown:
    case kCGEventRightMouseDown:
        *press = fingers == 3 ? type : kCGEventNull;
        return *press ? kCGEventOtherMouseDown : type;
    case kCGEventLeftMouseDragged:
        return *press == kCGEventLeftMouseDown ? kCGEventOtherMouseDragged : type;
    case kCGEventRightMouseDragged:
        return *press == kCGEventRightMouseDown ? kCGEventOtherMouseDragged : type;
    case kCGEventLeftMouseUp:
        if (*press != kCGEventLeftMouseDown) return type;
        *press = kCGEventNull;
        return kCGEventOtherMouseUp;
    case kCGEventRightMouseUp:
        if (*press != kCGEventRightMouseDown) return type;
        *press = kCGEventNull;
        return kCGEventOtherMouseUp;
    default:
        return type;
    }
}

// Rewrites a button event in place when it belongs to a middle click.
static inline void convertClick(CGEventRef event, int fingers, CGEventType *press) {
    CGEventType type = CGEventGetType(event);
    CGEventType newType = middleClickType(type, fingers, press);
    if (newType == type) return;
    CGEventSetType(event, newType);
    CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, kCGMouseButtonCenter);
}
