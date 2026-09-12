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

static pid_t findProcessByName(const char *name) {
  int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
  size_t size = 0;
  if (sysctl(mib, 4, NULL, &size, NULL, 0) < 0) return 0;
  struct kinfo_proc *procs = malloc(size);
  if (!procs) return 0;
  if (sysctl(mib, 4, procs, &size, NULL, 0) < 0) {
    free(procs);
    return 0;
  }
  size_t count = size / sizeof(struct kinfo_proc);
  pid_t result = 0;
  for (size_t i = 0; i < count; i++) {
    if (strstr(procs[i].kp_proc.p_comm, name) != NULL) {
      result = procs[i].kp_proc.p_pid;
      break;
    }
  }
  free(procs);
  return result;
}

@implementation MVPrivateAudioTap {
  id _tap;
  void (^_handler)(const float *, uint32_t);
  NSString *_diagnostic;
  uint64_t _samplesReceivedCount;
  uint32_t _sampleRate;
  uint32_t _numberOfChannels;
  int _activePID;
  NSString *_activeTargetName;
  BOOL _isRunning;
}

- (NSString *)diagnostic { return _diagnostic ?: @"Not started"; }
- (BOOL)isRunning { return _isRunning; }
- (uint64_t)samplesReceivedCount { return _samplesReceivedCount; }
- (uint32_t)sampleRate { return _sampleRate; }
- (uint32_t)numberOfChannels { return _numberOfChannels; }
- (int)activePID { return _activePID; }
- (NSString *)activeTargetName { return _activeTargetName ?: @"unknown"; }

- (BOOL)startDefaultWithHandler:(void (^)(const float *, uint32_t))handler {
  // Strategy 1: Check daemon PIDs if accessible
  pid_t audioMixerPID = findProcessByName("audiomxd");
  if (audioMixerPID > 0) {
    NSLog(@"[MVPrivateAudioTap] Discovered audiomxd at PID %d, attempting tap...", audioMixerPID);
    if ([self startForPID:audioMixerPID targetName:@"audiomxd" handler:handler]) {
      return YES;
    }
  }

  pid_t mediaPlaybackPID = findProcessByName("mediaplaybackd");
  if (mediaPlaybackPID > 0) {
    NSLog(@"[MVPrivateAudioTap] Discovered mediaplaybackd at PID %d, attempting tap...", mediaPlaybackPID);
    if ([self startForPID:mediaPlaybackPID targetName:@"mediaplaybackd" handler:handler]) {
      return YES;
    }
  }

  // Strategy 2: System audio tap (PID 0)
  NSLog(@"[MVPrivateAudioTap] Attempting system tap (PID 0)...");
  if ([self startForPID:0 targetName:@"System (PID 0)" handler:handler]) {
    return YES;
  }

  // Strategy 3: App process tap (getpid())
  NSLog(@"[MVPrivateAudioTap] Falling back to app process tap (PID %d)...", getpid());
  return [self startForPID:getpid() targetName:@"mViz App" handler:handler];
}

- (BOOL)startForPID:(int)pid handler:(void (^)(const float *, uint32_t))handler {
  return [self startForPID:pid targetName:[NSString stringWithFormat:@"PID %d", pid] handler:handler];
}

- (BOOL)startForPID:(int)pid targetName:(NSString *)targetName handler:(void (^)(const float *, uint32_t))handler {
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
    _activePID = pid;
    _activeTargetName = targetName;

    if (pid == 0) {
      if ([cls instancesRespondToSelector:@selector(initWithPID:refreshRate:delegate:)]) {
        _tap = [[cls alloc] initWithPID:0 refreshRate:nil delegate:self];
      }
    } else if (pid > 0) {
      if ([cls instancesRespondToSelector:@selector(initWithPID:refreshRate:delegate:)]) {
        _tap = [[cls alloc] initWithPID:pid refreshRate:nil delegate:self];
      } else if ([cls instancesRespondToSelector:@selector(initWithPID:refreshRate:numberOfChannels:delegate:)]) {
        _tap = [[cls alloc] initWithPID:pid refreshRate:nil numberOfChannels:2 delegate:self];
      }
    }

    if (!_tap && [cls instancesRespondToSelector:@selector(initWithRefreshRate:delegate:)]) {
      _tap = [[cls alloc] initWithRefreshRate:nil delegate:self];
    }

    if (!_tap) {
      _diagnostic = [NSString stringWithFormat:@"Private tap initializer returned nil for %@ (%d)", targetName, pid];
      NSLog(@"[MVPrivateAudioTap] %@", _diagnostic);
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
    _diagnostic = [NSString stringWithFormat:@"Tap active for %@ (PID %d, %u Hz, %u ch); awaiting samples",
                   targetName, pid, _sampleRate, _numberOfChannels];
    NSLog(@"[MVPrivateAudioTap] %@", _diagnostic);
    return YES;
  } @catch (NSException *exception) {
    _diagnostic = [NSString stringWithFormat:@"Private tap exception for %@ (%d): %@", targetName, pid, exception.reason];
    NSLog(@"[MVPrivateAudioTap] %@", _diagnostic);
    _tap = nil;
    _isRunning = NO;
    return NO;
  }
#else
  _diagnostic = @"Private tap is Debug-only";
  return NO;
#endif
}

- (void)handleReceivedSamples:(void *)samples count:(unsigned int)count sampleRate:(uint32_t)rate channels:(uint32_t)channels {
  if (_samplesReceivedCount == 0 && count > 0) {
    NSLog(@"[MVPrivateAudioTap] >>> First audio sample buffer received! count: %u, rate: %u, target: %@ <<<",
          count, rate ?: _sampleRate, _activeTargetName);
    if (_onFirstSampleReceived) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_onFirstSampleReceived) {
          self->_onFirstSampleReceived();
        }
      });
    }
  }
  _samplesReceivedCount += count;
  if (rate > 0) _sampleRate = rate;
  if (channels > 0) _numberOfChannels = channels;
  if (samples && count && _handler) {
    _handler((const float *)samples, count);
  }
}

- (void)processAudioTapDidReceiveAudioSamples:(void *)samples numberOfSamples:(unsigned int)count {
  [self handleReceivedSamples:samples count:count sampleRate:0 channels:0];
}

- (void)processAudioTapDidReceiveAudioSamples:(void *)samples numberOfSamples:(unsigned int)count sampleRate:(double)rate {
  [self handleReceivedSamples:samples count:count sampleRate:(uint32_t)rate channels:0];
}

- (void)processAudioTapDidReceiveAudioSamples:(void *)samples numberOfSamples:(unsigned int)count sampleRate:(double)rate numberOfChannels:(unsigned int)channels {
  [self handleReceivedSamples:samples count:count sampleRate:(uint32_t)rate channels:channels];
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
