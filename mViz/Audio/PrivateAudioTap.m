#import "PrivateAudioTap.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#import <unistd.h>
#import <sys/sysctl.h>

@interface NSObject (MVProcessTapSignatures)
- (id)initWithPID:(int)pid refreshRate:(id)refreshRate delegate:(id)delegate;
- (id)initWithRefreshRate:(id)refreshRate delegate:(id)delegate;
- (id)initWithPID:(int)pid refreshRate:(id)refreshRate numberOfChannels:(unsigned int)channels delegate:(id)delegate;
- (void)start;
- (void)stop;
- (unsigned int)sampleRate;
- (unsigned int)numberOfChannels;
- (unsigned int)numberOfFrames;
- (void)setNumberOfFrames:(unsigned int)numberOfFrames;
- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)enabled;
- (id)delegate;
- (void)setDelegate:(id)delegate;
@end

@implementation MVPrivateAudioTap {
  id _tap;
  void (^_handler)(const float *, uint32_t);
  NSString *_diagnostic;
  uint64_t _samplesReceivedCount;
  uint32_t _sampleRate;
  uint32_t _numberOfChannels;
  BOOL _isRunning;
}

- (NSString *)diagnostic { return _diagnostic ?: @"Not started"; }
- (BOOL)isRunning { return _isRunning; }
- (uint64_t)samplesReceivedCount { return _samplesReceivedCount; }
- (uint32_t)sampleRate { return _sampleRate; }
- (uint32_t)numberOfChannels { return _numberOfChannels; }

- (BOOL)startDefaultWithHandler:(void (^)(const float *, uint32_t))handler {
  // First attempt: system/default tap (pid = 0)
  if ([self startForPID:0 handler:handler]) {
    return YES;
  }
  // Fallback: app process tap
  return [self startForPID:getpid() handler:handler];
}

- (BOOL)startForPID:(int)pid handler:(void (^)(const float *, uint32_t))handler {
  [self stop];
#if DEBUG
  dlopen("/System/Library/PrivateFrameworks/MediaPlaybackCore.framework/MediaPlaybackCore", RTLD_LAZY | RTLD_LOCAL);
  Class cls = NSClassFromString(@"MPCProcessAudioTap");
  if (!cls) {
    _diagnostic = @"MPCProcessAudioTap class not found in MediaPlaybackCore";
    return NO;
  }

  @try {
    _handler = [handler copy];
    _samplesReceivedCount = 0;

    if (pid <= 0 && [cls instancesRespondToSelector:@selector(initWithRefreshRate:delegate:)]) {
      _tap = [[cls alloc] initWithRefreshRate:nil delegate:self];
    } else if ([cls instancesRespondToSelector:@selector(initWithPID:refreshRate:delegate:)]) {
      _tap = [[cls alloc] initWithPID:pid refreshRate:nil delegate:self];
    } else if ([cls instancesRespondToSelector:@selector(initWithPID:refreshRate:numberOfChannels:delegate:)]) {
      _tap = [[cls alloc] initWithPID:pid refreshRate:nil numberOfChannels:2 delegate:self];
    }

    if (!_tap) {
      _diagnostic = [NSString stringWithFormat:@"Private tap initializer returned nil for PID %d", pid];
      return NO;
    }

    if ([_tap respondsToSelector:@selector(setNumberOfFrames:)]) {
      [_tap setNumberOfFrames:1024];
    }
    if ([_tap respondsToSelector:@selector(setEnabled:)]) {
      [_tap setEnabled:YES];
    }
    [_tap start];

    _sampleRate = [_tap respondsToSelector:@selector(sampleRate)] ? [_tap sampleRate] : 48000;
    _numberOfChannels = [_tap respondsToSelector:@selector(numberOfChannels)] ? [_tap numberOfChannels] : 1;
    _isRunning = YES;
    _diagnostic = [NSString stringWithFormat:@"Tap active for PID %d (%u Hz, %u ch); awaiting samples",
                   pid, _sampleRate, _numberOfChannels];
    return YES;
  } @catch (NSException *exception) {
    _diagnostic = [NSString stringWithFormat:@"Private tap exception for PID %d: %@", pid, exception.reason];
    _tap = nil;
    _isRunning = NO;
    return NO;
  }
#else
  _diagnostic = @"Private tap is Debug-only";
  return NO;
#endif
}

- (void)processAudioTapDidReceiveAudioSamples:(void *)samples numberOfSamples:(unsigned int)count {
  _samplesReceivedCount += count;
  if (samples && count && _handler) {
    _handler((const float *)samples, count);
  }
}

- (void)processAudioTapDidReceiveAudioSamples:(void *)samples numberOfSamples:(unsigned int)count sampleRate:(double)rate {
  _samplesReceivedCount += count;
  if (rate > 0) {
    _sampleRate = (uint32_t)rate;
  }
  if (samples && count && _handler) {
    _handler((const float *)samples, count);
  }
}

- (void)processAudioTapDidReceiveAudioSamples:(void *)samples numberOfSamples:(unsigned int)count sampleRate:(double)rate numberOfChannels:(unsigned int)channels {
  _samplesReceivedCount += count;
  if (rate > 0) {
    _sampleRate = (uint32_t)rate;
  }
  if (channels > 0) {
    _numberOfChannels = channels;
  }
  if (samples && count && _handler) {
    _handler((const float *)samples, count);
  }
}

- (NSString *)tapIvarsSummary {
  if (!_tap) return @"No _tap instance";
  NSMutableString *s = [NSMutableString string];
  unsigned int count = 0;
  Class cls = [_tap class];
  Ivar *ivars = class_copyIvarList(cls, &count);
  for (unsigned int i = 0; i < count; i++) {
    const char *name = ivar_getName(ivars[i]);
    const char *type = ivar_getTypeEncoding(ivars[i]);
    id val = nil;
    if (type && type[0] == '@') {
      @try { val = object_getIvar(_tap, ivars[i]); } @catch (NSException *e) { val = @"<read error>"; }
    }
    [s appendFormat:@"    %s (%s): %@\n", name, type, val];
  }
  free(ivars);
  return s;
}

- (void)stop {
  _isRunning = NO;
  if (_tap) {
    @try { [_tap stop]; } @catch (NSException *exception) { }
    _tap = nil;
  }
}

- (void)dealloc {
  [self stop];
}

+ (NSString *)runDiagnosticProbe {
  NSMutableString *out = [NSMutableString string];
  [out appendString:@"=== Audio Tap Diagnostic Probe ===\n"];

  dlopen("/System/Library/PrivateFrameworks/MediaPlaybackCore.framework/MediaPlaybackCore", RTLD_LAZY | RTLD_LOCAL);
  dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox", RTLD_LAZY | RTLD_LOCAL);

  Class tapCls = NSClassFromString(@"MPCProcessAudioTap");
  [out appendFormat:@"MPCProcessAudioTap available: %@\n", tapCls ? @"YES" : @"NO"];

  Class descCls = NSClassFromString(@"ATAudioTapDescription");
  Class ataTapCls = NSClassFromString(@"ATAudioTap");
  [out appendFormat:@"ATAudioTapDescription: %@, ATAudioTap: %@\n", descCls ? @"YES" : @"NO", ataTapCls ? @"YES" : @"NO"];

  return out;
}

@end
