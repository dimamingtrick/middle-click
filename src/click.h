#pragma once
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>

// Returns the type a left-button event should have. A press made while exactly
// three fingers are on the trackpad becomes a middle-button press, and its drags
// and release follow it; *middleDown carries that state between events.
static inline CGEventType middleClickType(CGEventType type, int fingers, bool *middleDown) {
    switch (type) {
    case kCGEventLeftMouseDown:
        *middleDown = fingers == 3;
        return *middleDown ? kCGEventOtherMouseDown : type;
    case kCGEventLeftMouseDragged:
        return *middleDown ? kCGEventOtherMouseDragged : type;
    case kCGEventLeftMouseUp:
        if (!*middleDown) return type;
        *middleDown = false;
        return kCGEventOtherMouseUp;
    default:
        return type;
    }
}

// Rewrites a left-button event in place when it belongs to a middle click.
static inline void convertClick(CGEventRef event, int fingers, bool *middleDown) {
    CGEventType type = CGEventGetType(event);
    CGEventType newType = middleClickType(type, fingers, middleDown);
    if (newType == type) return;
    CGEventSetType(event, newType);
    CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, kCGMouseButtonCenter);
}
