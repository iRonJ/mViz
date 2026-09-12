#import "PrivateAudioTap.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <unistd.h>
#import <sys/sysctl.h>

@interface NSObject (MVProcessTapSignatures)
- (id)initWithPID:(int)pid refreshRate:(id)refreshRate delegate:(id)delegate;
- (id)initWithRefreshRate:(id)refreshRate delegate:(id)delegate;
- (id)initWithPID:(int)pid refreshRate:(id)refreshRate numberOfChannels:(unsigned int)channels delegate:(id)delegate;
- (void)start;
- (void)stop;
- (unsigned int)numberOfFrames;
- (void)setNumberOfFrames:(unsigned int)numberOfFrames;
- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)enabled;
- (id)delegate;
- (void)setDelegate:(id)delegate;
@end

static void logTapDebug(NSString *message) {
  NSLog(@"[MVPrivateAudioTap] %@", message);
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  if (paths.count > 0) {
    NSString *logPath = [paths[0] stringByAppendingPathComponent:@"audio-tap-debug.log"];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:logPath]) {
      NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
      [fh seekToEndOfFile];
      [fh writeData:data];
      [fh closeFile];
    } else {
      [data writeToFile:logPath atomically:YES];
    }
  }
}

static pid_t findProcessByName(const char *name) {
  int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
  size_t size = 0;
  if (sysctl(mib, 4, NULL, &size, NULL, 0) < 0) {
    logTapDebug([NSString stringWithFormat:@"sysctl KERN_PROC_ALL size failed: errno %d (%s)", errno, strerror(errno)]);
    return 0;
  }
  struct kinfo_proc *procs = malloc(size);
  if (!procs) return 0;
  if (sysctl(mib, 4, procs, &size, NULL, 0) < 0) {
    logTapDebug([NSString stringWithFormat:@"sysctl KERN_PROC_ALL buffer failed: errno %d (%s)", errno, strerror(errno)]);
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
  int _currentStrategyIndex;
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
  _currentStrategyIndex = 0;
  logTapDebug(@"[startDefault] Starting tap strategy rotation from Strategy 0...");
  return [self tryStrategyAtIndex:0 handler:handler];
}

- (BOOL)switchToNextStrategyWithHandler:(void (^)(const float *, uint32_t))handler {
  _currentStrategyIndex++;
  logTapDebug([NSString stringWithFormat:@"[switchToNextStrategy] Advancing to Strategy %d...", _currentStrategyIndex]);
  return [self tryStrategyAtIndex:_currentStrategyIndex handler:handler];
}

static pid_t getMusicPlayerServerPID(void) {
  @try {
    dlopen("/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer", RTLD_LAZY | RTLD_LOCAL);
    Class mpCls = NSClassFromString(@"MPMusicPlayerController");
    if (!mpCls) {
      logTapDebug(@"MPMusicPlayerController class not found");
      return 0;
    }

    SEL appPlayerSel = sel_registerName("applicationMusicPlayer");
    SEL sysPlayerSel = sel_registerName("systemMusicPlayer");

    id appPlayer = [mpCls respondsToSelector:appPlayerSel] ? ((id (*)(id, SEL))objc_msgSend)(mpCls, appPlayerSel) : nil;
    id sysPlayer = [mpCls respondsToSelector:sysPlayerSel] ? ((id (*)(id, SEL))objc_msgSend)(mpCls, sysPlayerSel) : nil;

    NSArray *players = @[appPlayer ?: [NSNull null], sysPlayer ?: [NSNull null]];
    for (id player in players) {
      if (player == [NSNull null]) continue;
      SEL establishSel = sel_registerName("_establishConnectionIfNeeded");
      if ([player respondsToSelector:establishSel]) {
        ((void (*)(id, SEL))objc_msgSend)(player, establishSel);
      }
      Ivar connIvar = class_getInstanceVariable([player class], "_connection");
      if (connIvar) {
        id conn = object_getIvar(player, connIvar);
        if (conn && [conn respondsToSelector:@selector(processIdentifier)]) {
          pid_t pid = (pid_t)((pid_t (*)(id, SEL))objc_msgSend)(conn, @selector(processIdentifier));
          if (pid > 0) {
            logTapDebug([NSString stringWithFormat:@"Discovered media server PID %d from MPMusicPlayerController._connection", pid]);
            return pid;
          }
        }
      }
    }
  } @catch (NSException *e) {
    logTapDebug([NSString stringWithFormat:@"getMusicPlayerServerPID exception: %@", e.reason]);
  }
  return 0;
}

- (BOOL)tryStrategyAtIndex:(int)index handler:(void (^)(const float *, uint32_t))handler {
  _currentStrategyIndex = index;
  _handler = [handler copy];
  switch (index) {
    case 0: {
      // Strategy 0: App process tap via MPCProcessAudioTap (initWithRefreshRate:delegate:)
      logTapDebug([NSString stringWithFormat:@"[Strategy 0] Trying MPCProcessAudioTap default tap for PID %d...", getpid()]);
      if ([self startForPID:getpid() targetName:@"mViz App" handler:handler]) {
        return YES;
      }
      return [self tryStrategyAtIndex:index + 1 handler:handler];
    }
    case 1: {
      // Strategy 1: App process stereo tap (initWithPID:refreshRate:numberOfChannels:delegate:)
      logTapDebug([NSString stringWithFormat:@"[Strategy 1] Trying MPCProcessAudioTap stereo tap for PID %d...", getpid()]);
      if ([self startForPID:getpid() channels:2 targetName:@"mViz App (Stereo)" handler:handler]) {
        return YES;
      }
      return [self tryStrategyAtIndex:index + 1 handler:handler];
    }
    case 2: {
      // Strategy 2: Media server discovered via MPMusicPlayerController._connection (mediaplaybackd)
      pid_t serverPID = getMusicPlayerServerPID();
      if (serverPID > 0) {
        logTapDebug([NSString stringWithFormat:@"[Strategy 2] Trying discovered Media Server (PID %d)...", serverPID]);
        if ([self startForPID:serverPID targetName:[NSString stringWithFormat:@"Media Server (PID %d)", serverPID] handler:handler]) {
          return YES;
        }
      }
      return [self tryStrategyAtIndex:index + 1 handler:handler];
    }
    case 3: {
      // Strategy 3: Music.app
      pid_t musicPID = findProcessByName("Music");
      if (musicPID > 0) {
        logTapDebug([NSString stringWithFormat:@"[Strategy 3] Trying Music.app (PID %d)...", musicPID]);
        if ([self startForPID:musicPID targetName:@"Music.app" handler:handler]) {
          return YES;
        }
      }
      return [self tryStrategyAtIndex:index + 1 handler:handler];
    }
    case 4: {
      // Strategy 4: mediaplaybackd daemon
      pid_t mediaPlaybackPID = findProcessByName("mediaplaybackd");
      if (mediaPlaybackPID > 0) {
        logTapDebug([NSString stringWithFormat:@"[Strategy 4] Trying mediaplaybackd (PID %d)...", mediaPlaybackPID]);
        if ([self startForPID:mediaPlaybackPID targetName:@"mediaplaybackd" handler:handler]) {
          return YES;
        }
      }
      return [self tryStrategyAtIndex:index + 1 handler:handler];
    }
    case 5: {
      // Strategy 5: audiomxd mixer daemon
      pid_t audioMixerPID = findProcessByName("audiomxd");
      if (audioMixerPID > 0) {
        logTapDebug([NSString stringWithFormat:@"[Strategy 5] Trying audiomxd (PID %d)...", audioMixerPID]);
        if ([self startForPID:audioMixerPID targetName:@"audiomxd" handler:handler]) {
          return YES;
        }
      }
      break;
    }
    default:
      break;
  }
  logTapDebug(@"[MVPrivateAudioTap] All candidate tap strategies exhausted.");
  return NO;
}

- (BOOL)startForPID:(int)pid handler:(void (^)(const float *, uint32_t))handler {
  return [self startForPID:pid channels:1 targetName:[NSString stringWithFormat:@"PID %d", pid] handler:handler];
}

- (BOOL)startForPID:(int)pid targetName:(NSString *)targetName handler:(void (^)(const float *, uint32_t))handler {
  return [self startForPID:pid channels:1 targetName:targetName handler:handler];
}

- (BOOL)startForPID:(int)pid channels:(uint32_t)channels targetName:(NSString *)targetName handler:(void (^)(const float *, uint32_t))handler {
  [self stop];
#if DEBUG
  dlopen("/System/Library/PrivateFrameworks/MediaPlaybackCore.framework/MediaPlaybackCore", RTLD_LAZY | RTLD_LOCAL);
  Class cls = NSClassFromString(@"MPCProcessAudioTap");
  if (!cls) {
    _diagnostic = @"MPCProcessAudioTap class not found in MediaPlaybackCore";
    logTapDebug(_diagnostic);
    return NO;
  }

  @try {
    _handler = [handler copy];
    _samplesReceivedCount = 0;
    _activePID = pid;
    _activeTargetName = targetName;

    if (pid == getpid() && channels == 1) {
      if ([cls instancesRespondToSelector:@selector(initWithRefreshRate:delegate:)]) {
        _tap = [[cls alloc] initWithRefreshRate:nil delegate:self];
      }
    }

    if (!_tap && channels > 1) {
      if ([cls instancesRespondToSelector:@selector(initWithPID:refreshRate:numberOfChannels:delegate:)]) {
        _tap = [[cls alloc] initWithPID:pid refreshRate:nil numberOfChannels:channels delegate:self];
      }
    }

    if (!_tap && [cls instancesRespondToSelector:@selector(initWithPID:refreshRate:delegate:)]) {
      _tap = [[cls alloc] initWithPID:pid refreshRate:nil delegate:self];
    }

    if (!_tap) {
      _diagnostic = [NSString stringWithFormat:@"Private tap initializer returned nil for %@ (%d)", targetName, pid];
      logTapDebug(_diagnostic);
      return NO;
    }

    if ([_tap respondsToSelector:@selector(setNumberOfFrames:)]) {
      [_tap setNumberOfFrames:1024];
    }
    if ([_tap respondsToSelector:@selector(setEnabled:)]) {
      [_tap setEnabled:YES];
    }
    [_tap start];

    BOOL enabled = YES;
    if ([_tap respondsToSelector:@selector(isEnabled)]) {
      enabled = [_tap isEnabled];
      logTapDebug([NSString stringWithFormat:@"[_tap isEnabled] for %@ (PID %d): %d", targetName, pid, enabled]);
    }
    if (!enabled) {
      _diagnostic = [NSString stringWithFormat:@"Tap failed to enable for %@ (PID %d)", targetName, pid];
      logTapDebug(_diagnostic);
      [self stop];
      return NO;
    }

    SEL srSel = sel_registerName("sampleRate");
    _sampleRate = [_tap respondsToSelector:srSel] ? ((unsigned int (*)(id, SEL))objc_msgSend)(_tap, srSel) : 48000;
    SEL chSel = sel_registerName("numberOfChannels");
    _numberOfChannels = [_tap respondsToSelector:chSel] ? ((unsigned int (*)(id, SEL))objc_msgSend)(_tap, chSel) : channels;
    _isRunning = YES;
    _diagnostic = [NSString stringWithFormat:@"Tap active for %@ (PID %d, %u Hz, %u ch); awaiting samples",
                   targetName, pid, _sampleRate, _numberOfChannels];
    logTapDebug(_diagnostic);
    return YES;
  } @catch (NSException *exception) {
    _diagnostic = [NSString stringWithFormat:@"Private tap exception for %@ (%d): %@", targetName, pid, exception.reason];
    logTapDebug(_diagnostic);
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
    logTapDebug([NSString stringWithFormat:@">>> First audio buffer received! count: %u, target: %@ <<<",
                 count, _activeTargetName]);
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
  Class tapCls = NSClassFromString(@"MPCProcessAudioTap");
  [out appendFormat:@"MPCProcessAudioTap available: %@\n", tapCls ? @"YES" : @"NO"];

  return out;
}

@end
