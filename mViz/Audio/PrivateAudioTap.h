#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Local Debug experiment for private system/process audio tapping.
/// Samples are mono Float32 and only valid in the callback.
@interface MVPrivateAudioTap : NSObject

@property(nonatomic, readonly) NSString *diagnostic;
@property(nonatomic, readonly) BOOL isRunning;
@property(nonatomic, readonly) uint64_t samplesReceivedCount;
@property(nonatomic, readonly) uint32_t sampleRate;
@property(nonatomic, readonly) uint32_t numberOfChannels;
@property(nonatomic, readonly) int activePID;
@property(nonatomic, readonly) NSString *activeTargetName;
@property(nonatomic, copy, nullable) void (^onFirstSampleReceived)(void);

- (BOOL)startForPID:(int)pid handler:(void (^)(const float *samples, uint32_t count))handler;
- (BOOL)startDefaultWithHandler:(void (^)(const float *samples, uint32_t count))handler;
- (void)stop;
- (NSString *)tapIvarsSummary;
+ (NSString *)runDiagnosticProbe;

@end

NS_ASSUME_NONNULL_END
