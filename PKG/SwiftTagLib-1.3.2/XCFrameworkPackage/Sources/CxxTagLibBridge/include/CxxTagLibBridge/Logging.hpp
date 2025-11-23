
/// only enable logging when in debug
#if DEBUG
#define TAGLIB_BRIDGE_LOG_ENABLED 1
#else
#define TAGLIB_BRIDGE_LOG_ENABLED 0
#endif

#import <stdint.h>
enum TagLibBridgeLogLevel: uint8_t {
    Default = 0x00,
    Info = 0x01,
    Debug = 0x02,
    Error = 0x10,
    Fault = 0x11,
};

#if TAGLIB_BRIDGE_LOG_ENABLED
#pragma message("CxxTagLibBridge logging is enabled in DEBUG")
#import <os/log.h>
#import <dispatch/dispatch.h>

/// it could have been `__attribute__ ((constructor));` but Swift C++ interop ignores it.
static os_log_t TagLibBridgeLog = [] {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        TagLibBridgeLog = os_log_create("org.SwiftTagLib", "CxxTagLibBridge");
    });
    return TagLibBridgeLog;
}();

#define taglib_bridge_log(level, format, ...) \
    os_log_with_type(TagLibBridgeLog, (os_log_type_t)(level), format, ##__VA_ARGS__)
#else
#define taglib_bridge_log(level, format, ...) { }
//#pragma message("CxxTagLibBridge logging is disabled when not in DEBUG")
#endif
