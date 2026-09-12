# Private audio investigation

Inspected September 12, 2026. Static inspection used the installed visionOS 26.5 SDK and locally cached device symbols for **visionOS 27.0 (24M5355a), RealityDevice14,1**. A subsequent real-headset diagnostic confirmed that exact running OS build, loaded the frameworks, and read Objective-C method type encodings. This is not a successful audio-capture experiment; no tap was started.

## Follow-up hardware results

The [matched control](audio-tap-control-visionOS27.txt) now establishes a concrete failure on visionOS 27.0 (24M5355a). With microphone permission granted and a recording-capable session, ordinary `AudioQueueNewInput` succeeds (`0`), while the processing-queue call used by `MPCProcessAudioTap` (flags `0x800`, observed in its disassembly) returns **`kAudioQueueErr_Permissions` (`-66676`)**. No queue is created by that call. The private wrapper nevertheless reports enabled; it receives zero frames while an independently running mViz engine renders an unprotected 440 Hz tone. This rules out Apple Music DRM or the wrong PID as necessary explanations for this particular failure. The exact additional service permission/entitlement remains unidentified; no access-control changes were attempted.

The app now checks this failure before starting the expensive PID rotation, and terminates exhausted retries. A longer buffer timeout cannot fix this queue-creation error.

The [cloud-analysis control](cloud-analysis-control-visionOS27.txt) compared an ordinary catalog request against the same song with `include=audio-analysis,flexml-analysis`, using the relationship names observed in MusicKit. **Both fail to obtain a developer token**, before relationship authorization can be evaluated. This is not evidence that these relationships are allowed or denied. Check MusicKit App Service registration for `TechronicApps.mViz`, then repeat the paired control. Apple documents [automatic token generation and App Service setup](https://developer.apple.com/documentation/musickit/using-automatic-token-generation-for-apple-music-api). Account configuration has not been inspected, so missing configuration versus another token-service failure remains unresolved.

The remainder records the earlier symbol investigation and hypotheses, not successful PCM access.

## Most useful new lead: Apple's internal spectrum observer and process tap

The cached device's `MediaPlaybackCore.framework` exports these Objective-C classes. Local `nm` method symbols identify the following selectors:

| Class | Relevant selectors |
| --- | --- |
| `MPCProcessAudioTap` | `initWithPID:refreshRate:delegate:`, `initWithPID:refreshRate:numberOfChannels:delegate:`, `start`, `stop`, `sampleRate`, `numberOfFrames` |
| `MPCAudioSpectrumAnalyzer` | `initWithPlaybackEngine:refreshRate:`, `registerObserver:`, `configurePlayerItem:`, `processAudioTapDidReceiveAudioSamples:numberOfSamples:` |
| `MPCAudioSpectrumObserver` | `defaultObserver`, `addFrequencyBand:`, `averagePowerOfFrequencyBandAtIndex:frequencyBand:`, `setOnUpdate:`, `powerLevel` |

The same binary imports `ATAudioTap` and `ATAudioTapDescription`. Its diagnostic strings describe creating an audio queue, installing a processing tap, receiving samples, and FFT frequency/time resolution. **This is concrete evidence of an internal analysis implementation**, rather than just a guessed private API name.

`AudioToolbox.framework` exports `ATAudioTap` and `ATAudioTapDescription` in both the installed 26.5 SDK link stub and the cached 27.0 runtime. Cached method symbols include:

- `ATAudioTap.initWithTapDescription:`
- `ATAudioTapDescription.initProcessTapWithFormat:PID:`
- `ATAudioTapDescription.initPreSpatialProcessTapWithFormat:PID:`
- `ATAudioTapDescription.initPreSpatialAudioSessionTapWithFormat:sessionID:`
- `ATAudioTapDescription.initSystemTapWithFormat:`
- `ATAudioTapDescription.initScreenSharingTapWithFormat:`

One separate initializer with a `deviceUID:` argument logs that it is not implemented. Do not assume every selector works.

Unknowns remain decisive: argument and callback ABI, sandbox/service authorization, whether the process being tapped actually renders MusicKit audio, and whether protected content is excluded. `ApplicationMusicPlayer` being named “application” does not establish that its PCM is rendered in our PID. A visible class or successful initializer does not prove accessible samples. No entitlement name was established. The string `com.apple.mediaplaybackcore.audiotap` occurs in diagnostic context; it must not be promoted to a guessed entitlement.

**Real-device diagnostic completed:** the Debug-only `--inspect-audio-api` launch loaded both frameworks and confirmed all five classes above. The [runtime report](audio-api-runtime-visionOS27.txt) records the selectors and actual type encodings. For example:

```text
initWithPID:refreshRate:delegate: :: @36@0:8i16@20@28
processAudioTapDidReceiveAudioSamples:numberOfSamples: :: v28@0:8^v16I24
addFrequencyBand: :: q24@0:8{MPCAudioFrequencyBand=ff}16
```

The refresh-rate parameter is an **object**, not a floating-point argument. Static inspection of `initWithPID:refreshRate:numberOfChannels:delegate:` explicitly shows a nil/default path; a nonnil argument receives a method call yielding an integer rate. NSNumber is plausible but not established, so nil is the evidence-backed default for any later experiment. The initializer initializes sample rate to 48,000 and computes a power-of-two frame count. The callback has a raw pointer and an unsigned 32-bit count; its encoding alone does not establish buffer sample format or lifetime. The `.audiotap` string is passed to queue creation, confirming that it is a dispatch queue label rather than evidence of an entitlement.

**Next bounded experiment:** after establishing buffer format and lifetime, a short tap of mViz's own PID while it plays a known unprotected test tone would establish whether an ordinary development-signed process can receive its own samples. Test MusicKit separately only after that control succeeds; report silence/error honestly. No access-control modification is part of this experiment. The normal app was relaunched after the signature inspection.

## Core Audio's desktop process-tap shortcut is a dead end on the inspected build

[Apple's Core Audio process-tap sample](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps) is the familiar macOS route. In the visionOS 26.5 SDK, `CATapDescription` appears in the CoreAudio link stub but `AudioHardwareCreateProcessTap` does not.

The cached 27.0 CoreAudio binary does contain `AudioHardwareCreateProcessTap` and `AudioHardwareDestroyProcessTap`, but disassembly shows that **both unconditionally return `0x77686174`**, the Core Audio `kAudioHardwareUnspecifiedError` (`'what'`):

```asm
mov  w0, #0x6174
movk w0, #0x7768, lsl #16
ret
```

Resolving these two symbols with `dlsym` would therefore not turn them into working taps on that build. The private AudioToolbox/MediaPlaybackCore path above is different.

## MusicKit contains derived analysis data models

Demangling the installed `MusicKit.framework/MusicKit.tbd` reveals `Song._audioAnalyses`, `Song._flexAnalyses`, `CloudAudioAnalysis`, and `CloudFlexAnalysis`. They are absent from its public Swift interface.

Concrete getters include:

- `CloudAudioAnalysis.Attributes.beats`, with `beatsInMilliseconds` and `barsInMilliseconds`.
- `bpm`, `energy`, `loudness`, `loudnessCurve`, `key`, `vocalActivity`, and `phrases`.
- `LoudnessCurve.samplingFrequency` and `value: [Double]?`.
- `CloudFlexAnalysis.Attributes.visualTempo`, `arousal`, and `valence`, using sampled values.

These fields could support synchronized beat/loudness animation **if our authorized account/app can obtain them**. They do not establish ten-band spectrum or waveform samples. No documented endpoint, accessible Swift SPI declaration, successful service response, or partner authorization requirement was established. This is a useful specific addition to the Apple inquiry, not a working fallback. We did not request private endpoints or extract credentials.

## Hidden Safari or web-player approach

Putting [MusicKit JS](https://js-cdn.music.apple.com/musickit/v1/index.html) in a `WKWebView` supplies another playback implementation, not automatic access to Safari's or Music.app's audio graph. A page we own could attach Web Audio's `AnalyserNode` to an accessible media element only if the underlying player supports supplying that audio. Access to the DOM or a song URL is not evidence that decrypted samples are exposed.

The [Web Audio standard](https://www.w3.org/TR/webaudio-1.0/#MediaElementAudioSourceOptions-security) requires silence for a media element whose fetched resource is CORS-cross-origin. This is conditional: correctly CORS-authorized unprotected media can work; it does not prove every Apple Music URL is blocked. WebKit's [AVFoundation player implementation](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/graphics/avfoundation/objc/MediaPlayerPrivateAVFoundationObjC.mm) creates an `AudioSourceProviderAVFObjC` from its AVPlayerItem, so the web route still depends on the media backend exposing audio. There is no verified Apple Music subscription-track analyzer result here.

Scraping displayed song/time metadata could synchronize preexisting analysis; it would not itself produce frequency data. A hidden web view also cannot inspect another app's DOM or obtain its private playback session by ordinary JavaScript. No hidden Safari implementation was added, and no claim is made that web playback bypasses the native restriction.

## Public taps and djay

`MTAudioProcessingTap` is available on visionOS and attaches to an AVAudioMix track we control ([Apple Q&A](https://developer.apple.com/library/archive/qa/qa1783/_index.html)). MusicKit exposes neither an AVPlayerItem nor that mix for its managed playback. Our existing AVAudioEngine mixer tap is already the appropriate direct path for imported files.

Algoriddim explicitly describes its streaming integrations as [partnerships](https://www.algoriddim.com/streaming). Its behavior does not identify which of the internal mechanisms above it uses. The static evidence now justifies a targeted native diagnostic, while partner access remains a separate unresolved question. A local development build changes distribution concerns; it does not grant OS-service or content authorization.

## Reproducible local inspection locations

SDK root:
`/Applications/Xcode.app/Contents/Developer/Platforms/XROS.platform/Developer/SDKs/XROS.sdk`

Cached runtime root:
`/Users/ronj/Library/Developer/Xcode/visionOS DeviceSupport/RealityDevice14,1 27.0 (24M5355a)/Symbols/System/Library`

Static tools used: read-only `rg`, `nm`, `strings`, `otool -tvV`, and `xcrun swift-demangle`. The real-device diagnostic additionally loaded frameworks and queried runtime class/method metadata. No private tap initializer or capture method was invoked. No recording, DRM decryption, code injection, entitlement changes, or messages to Apple were performed by this investigation.
