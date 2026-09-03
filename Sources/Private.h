#ifndef BOOGIE_PRIVATE_H
#define BOOGIE_PRIVATE_H
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

// Private IOHIDEventSystemClient interface exported by IOKit.framework.
// The MacBook's accelerometer ("accel", usage page 0xFF00, usage 3) only
// streams through a rate-controlled (type 3) client with an event callback;
// the ambient light sensor ("als", usage 4) answers IOHIDServiceClientCopyEvent.
// Verified on MacBook Pro M3 Pro (Mac15,6), macOS 27.

typedef void (*BoogieHIDCallback)(void *target, void *refcon, CFTypeRef service, CFTypeRef event);

extern CFTypeRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern CFTypeRef IOHIDEventSystemClientCreateWithType(CFAllocatorRef allocator, int32_t type, CFDictionaryRef attributes);
extern int IOHIDEventSystemClientSetMatching(CFTypeRef client, CFDictionaryRef match);
extern CFArrayRef IOHIDEventSystemClientCopyServices(CFTypeRef client);
extern int IOHIDServiceClientSetProperty(CFTypeRef service, CFStringRef key, CFTypeRef value);
extern CFTypeRef IOHIDServiceClientCopyEvent(CFTypeRef service, int64_t type, int32_t options, int64_t timestamp);
extern void IOHIDEventSystemClientRegisterEventCallback(CFTypeRef client, BoogieHIDCallback callback, void *target, void *refcon);
extern void IOHIDEventSystemClientScheduleWithRunLoop(CFTypeRef client, CFRunLoopRef runLoop, CFStringRef mode);
extern int IOHIDEventGetType(CFTypeRef event);
extern double IOHIDEventGetFloatValue(CFTypeRef event, int32_t field);

#endif
