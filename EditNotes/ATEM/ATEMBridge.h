#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_UI_ACTOR
@protocol ATEMBridgeDelegate <NSObject>
- (void)atemBridgeDidDisconnect;
/// `uptime` is the `NSProcessInfo.systemUptime` at which the switcher reported this timecode.
- (void)atemBridgeDidReceiveTimecodeWithHours:(NSInteger)hours
                                      minutes:(NSInteger)minutes
                                      seconds:(NSInteger)seconds
                                       frames:(NSInteger)frames
                                    dropFrame:(BOOL)dropFrame
                                       uptime:(NSTimeInterval)uptime;
/// The switcher's recording filename, which ATEM Software Control presents as the project name.
- (void)atemBridgeProjectNameDidChange:(nullable NSString *)name;
- (void)atemBridgeVideoModeDidChangeWithTimebase:(NSInteger)timebase ntsc:(BOOL)ntsc;
@end

/// Objective-C++ wrapper around the Blackmagic ATEM Switchers SDK. Call from the main thread;
/// delegate methods and completion handlers are delivered on the main thread.
@interface ATEMBridge : NSObject

/// Whether the SDK runtime (installed with ATEM Software Control) is present.
@property (class, readonly) BOOL sdkInstalled;
@property (nonatomic, weak, nullable) id<ATEMBridgeDelegate> delegate;

- (void)connectToAddress:(NSString *)address
              completion:(void (^)(NSString *_Nullable productName, NSString *_Nullable error))completion;
- (void)disconnect;
/// Asks the switcher for its current timecode; the reply arrives through the delegate.
- (void)requestTimecode;

@end

NS_ASSUME_NONNULL_END
