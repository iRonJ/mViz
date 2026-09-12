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
    if ([_tap respondsToSelector:@selector(_createProcessTapWithNumberOfFrames:sampleRate:)]) {
      typedef void (*CreateTapFn)(id, SEL, unsigned int, double);
      CreateTapFn fn = (CreateTapFn)[_tap methodForSelector:@selector(_createProcessTapWithNumberOfFrames:sampleRate:)];
      fn(_tap, @selector(_createProcessTapWithNumberOfFrames:sampleRate:), 1024, 48000.0);
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

// Intercept any variant of delegate messages
- (BOOL)respondsToSelector:(SEL)aSelector {
  NSString *selStr = NSStringFromSelector(aSelector);
  if ([selStr containsString:@"Tap"] || [selStr containsString:@"Audio"] || [selStr containsString:@"Sample"]) {
    NSLog(@"[MVPrivateAudioTap query] respondsToSelector: %@", selStr);
    return YES;
  }
  return [super respondsToSelector:aSelector];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
  NSMethodSignature *sig = [super methodSignatureForSelector:aSelector];
  if (!sig) {
    sig = [NSMethodSignature signatureWithObjCTypes:"v@:@@@@@@@@"];
  }
  return sig;
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
  NSLog(@"[MVPrivateAudioTap intercepted invocation]: %@", NSStringFromSelector(anInvocation.selector));
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

  // Probe 1: initWithRefreshRate:nil delegate:
  if (tapCls && [tapCls instancesRespondToSelector:@selector(initWithRefreshRate:delegate:)]) {
    @try {
      MVPrivateAudioTap *probe = [[MVPrivateAudioTap alloc] init];
      id rawTap = [[tapCls alloc] initWithRefreshRate:nil delegate:probe];
      [out appendFormat:@"Probe 1 (initWithRefreshRate:): %@\n", rawTap ? @"Allocated" : @"nil"];
      if (rawTap) {
        probe->_tap = rawTap;
        if ([rawTap respondsToSelector:@selector(setNumberOfFrames:)]) [rawTap setNumberOfFrames:1024];
        if ([rawTap respondsToSelector:@selector(_createProcessTapWithNumberOfFrames:sampleRate:)]) {
          typedef void (*CreateTapFn)(id, SEL, unsigned int, double);
          CreateTapFn fn = (CreateTapFn)[rawTap methodForSelector:@selector(_createProcessTapWithNumberOfFrames:sampleRate:)];
          fn(rawTap, @selector(_createProcessTapWithNumberOfFrames:sampleRate:), 1024, 48000.0);
          [out appendString:@"  Called _createProcessTapWithNumberOfFrames:1024 sampleRate:48000.0\n"];
        }
        [out appendString:[probe tapIvarsSummary]];
        if ([rawTap respondsToSelector:@selector(setEnabled:)]) [rawTap setEnabled:YES];
        [rawTap start];
        [out appendFormat:@"  Start succeeded. isEnabled: %d\n", [rawTap respondsToSelector:@selector(isEnabled)] ? [rawTap isEnabled] : -1];
        [rawTap stop];
      }
    } @catch (NSException *e) {
      [out appendFormat:@"Probe 1 exception: %@\n", e.reason];
    }
  }

  // Probe 2: initWithPID:0
  if (tapCls && [tapCls instancesRespondToSelector:@selector(initWithPID:refreshRate:delegate:)]) {
    @try {
      MVPrivateAudioTap *probe = [[MVPrivateAudioTap alloc] init];
      id rawTap = [[tapCls alloc] initWithPID:0 refreshRate:nil delegate:probe];
      [out appendFormat:@"Probe 2 (initWithPID:0): %@\n", rawTap ? @"Allocated" : @"nil"];
      if (rawTap) {
        probe->_tap = rawTap;
        if ([rawTap respondsToSelector:@selector(setNumberOfFrames:)]) [rawTap setNumberOfFrames:1024];
        if ([rawTap respondsToSelector:@selector(_createProcessTapWithNumberOfFrames:sampleRate:)]) {
          typedef void (*CreateTapFn)(id, SEL, unsigned int, double);
          CreateTapFn fn = (CreateTapFn)[rawTap methodForSelector:@selector(_createProcessTapWithNumberOfFrames:sampleRate:)];
          fn(rawTap, @selector(_createProcessTapWithNumberOfFrames:sampleRate:), 1024, 48000.0);
        }
        [out appendString:[probe tapIvarsSummary]];
        if ([rawTap respondsToSelector:@selector(setEnabled:)]) [rawTap setEnabled:YES];
        [rawTap start];
        [out appendFormat:@"  Start succeeded. isEnabled: %d\n", [rawTap respondsToSelector:@selector(isEnabled)] ? [rawTap isEnabled] : -1];
        [rawTap stop];
      }
    } @catch (NSException *e) {
      [out appendFormat:@"Probe 2 exception: %@\n", e.reason];
    }
  }

  // Probe 3: initWithPID:getpid()
  if (tapCls && [tapCls instancesRespondToSelector:@selector(initWithPID:refreshRate:delegate:)]) {
    @try {
      MVPrivateAudioTap *probe = [[MVPrivateAudioTap alloc] init];
      id rawTap = [[tapCls alloc] initWithPID:getpid() refreshRate:nil delegate:probe];
      [out appendFormat:@"Probe 3 (initWithPID:getpid()=%d): %@\n", getpid(), rawTap ? @"Allocated" : @"nil"];
      if (rawTap) {
        probe->_tap = rawTap;
        if ([rawTap respondsToSelector:@selector(setNumberOfFrames:)]) [rawTap setNumberOfFrames:1024];
        if ([rawTap respondsToSelector:@selector(_createProcessTapWithNumberOfFrames:sampleRate:)]) {
          typedef void (*CreateTapFn)(id, SEL, unsigned int, double);
          CreateTapFn fn = (CreateTapFn)[rawTap methodForSelector:@selector(_createProcessTapWithNumberOfFrames:sampleRate:)];
          fn(rawTap, @selector(_createProcessTapWithNumberOfFrames:sampleRate:), 1024, 48000.0);
        }
        [out appendString:[probe tapIvarsSummary]];
        if ([rawTap respondsToSelector:@selector(setEnabled:)]) [rawTap setEnabled:YES];
        [rawTap start];
        [out appendFormat:@"  Start succeeded. isEnabled: %d\n", [rawTap respondsToSelector:@selector(isEnabled)] ? [rawTap isEnabled] : -1];
        [rawTap stop];
      }
    } @catch (NSException *e) {
      [out appendFormat:@"Probe 3 exception: %@\n", e.reason];
    }
  }

  // Probe 4: ATAudioTapDescription & ATAudioTap
  Class descCls = NSClassFromString(@"ATAudioTapDescription");
  Class ataTapCls = NSClassFromString(@"ATAudioTap");
  [out appendFormat:@"ATAudioTapDescription: %@, ATAudioTap: %@\n", descCls ? @"YES" : @"NO", ataTapCls ? @"YES" : @"NO"];
  if (descCls && ataTapCls) {
    @try {
      if ([descCls instancesRespondToSelector:@selector(initSystemTapWithFormat:)]) {
        id desc = [[descCls alloc] performSelector:@selector(initSystemTapWithFormat:) withObject:nil];
        [out appendFormat:@"Probe 4a (initSystemTapWithFormat:nil): %@\n", desc ? @"Allocated" : @"nil"];
        if (desc && [ataTapCls instancesRespondToSelector:@selector(initWithTapDescription:)]) {
          id tapObj = [[ataTapCls alloc] performSelector:@selector(initWithTapDescription:) withObject:desc];
          [out appendFormat:@"  ATAudioTap initWithTapDescription: %@\n", tapObj ? @"Success" : @"nil"];
        }
      }
      if ([descCls instancesRespondToSelector:@selector(initProcessTapWithFormat:PID:)]) {
        typedef id (*InitPIDFn)(id, SEL, id, int);
        InitPIDFn fn = (InitPIDFn)[descCls instanceMethodForSelector:@selector(initProcessTapWithFormat:PID:)];
        id desc = fn([descCls alloc], @selector(initProcessTapWithFormat:PID:), nil, getpid());
        [out appendFormat:@"Probe 4b (initProcessTapWithFormat:PID:%d): %@\n", getpid(), desc ? @"Allocated" : @"nil"];
        if (desc && [ataTapCls instancesRespondToSelector:@selector(initWithTapDescription:)]) {
          id tapObj = [[ataTapCls alloc] performSelector:@selector(initWithTapDescription:) withObject:desc];
          [out appendFormat:@"  ATAudioTap initWithTapDescription: %@\n", tapObj ? @"Success" : @"nil"];
        }
      }
    } @catch (NSException *e) {
      [out appendFormat:@"Probe 4 exception: %@\n", e.reason];
    }
  }

  return out;
}

@end
