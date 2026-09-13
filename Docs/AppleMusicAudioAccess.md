# Apple Music audio analysis investigation

Checked September 12, 2026 against the installed Xcode 26.6 / visionOS 26.5 SDK.

## Finding

djay really supports mixing Apple Music on Vision Pro. Algoriddim's [announcement](https://www.algoriddim.com/news/449-apple-music-integration-is) includes Vision Pro, and Apple's [DJ with Apple Music page](https://music.apple.com/us/curator/dj-with-apple-music/1798261090) lists djay alongside other DJ platforms. Algoriddim describes its streaming integrations as [partnerships](https://www.algoriddim.com/streaming).

The public [MusicKit API](https://developer.apple.com/musickit/) and the installed MusicKit Swift interface expose library/catalog access, playback, queues, time, and state. I found no public PCM callback, waveform/spectral analysis API, or way to attach ApplicationMusicPlayer to our AVAudioEngine. Our mixer tap receives only audio rendered through our engine. Starting MusicKit playback does not route its output into that mixer. Downloading a subscription track does not make it an importable unprotected file.

**Inference:** DJ partner access is the most plausible route to investigate. The available primary sources do not identify djay's internal API, entitlement, SDK, or admission requirements. I did not find a public application form for equivalent access. Do not treat a guessed private entitlement or undocumented selector as an implementation plan.

MusicKit's ordinary App ID service configuration is separate: Apple DTS explicitly explains that MusicKit is [not gated by a MusicKit entitlement](https://developer.apple.com/forums/thread/784114). Adding a made-up `com.apple.developer.musickit` entitlement will not expose audio samples.

Also, waveform access should not be confused with unrestricted audio extraction: Algoriddim's [manual](https://help.algoriddim.com/user-manual/djay-pro-mac/music-library/streaming-services) says Neural Mix is unavailable for Apple Music and recording streaming mixes is disabled.

## What works in mViz

| Source | Playback | Frequency data |
| --- | --- | --- |
| Imported unprotected file | Our AVAudioEngine | Direct analysis from the mixer before the audio delay |
| Importable device-library file | Copy into our library, then AVAudioEngine | Direct analysis |
| Apple Music subscription song | ApplicationMusicPlayer | No public direct analysis hook found; microphone can analyze audible speaker output |

Microphone analysis measures room sound, including speech/noise; headphones do not provide a useful acoustic feed. It is not a digital loopback. No private visionOS system-audio tap has been established in this investigation.

The newer [Music Understanding framework](https://developer.apple.com/documentation/musicunderstanding) analyzes supplied media; its [asset initializer](https://developer.apple.com/documentation/musicunderstanding/musicunderstandingsession/init(asset:)) requires an accessible asset. It does not establish access to MusicKit's protected playback and is absent from the installed SDK.

## Concrete next step: draft inquiry (not sent)

Submit via [Apple Developer code-level support](https://developer.apple.com/support/technical/) to ask for a supported API or referral to the relevant Apple Music partnership team. This is an inquiry about access for our app, not a request to disclose another app's implementation.

**Subject:** Supported Apple Music spectrum/beat analysis for a visionOS visualizer

We develop mViz (TechronicApps.mViz), an immersive music visualizer for Apple Vision Pro, using Xcode 26.6 and the visionOS 26.5 SDK. Users authorize their own Apple Music library and playback through ApplicationMusicPlayer. Our AVAudioEngine analyzer already supports unprotected files and microphone input.

We need synchronized frequency-band energy, beat events, or waveform information for the currently playing Apple Music song. Derived analysis would suffice; raw PCM is not essential. We do not need to save, export, record, or transmit song audio.

Does Apple offer a supported API for this on visionOS? If this requires participation in an Apple Music partner program such as DJ with Apple Music, could you refer us to its onboarding contact and clarify whether visualizer apps qualify? Please identify the required framework/service, eligibility requirements, platform availability, and restrictions on transient analysis. The public MusicKit interface we examined provides playback state and time but no audio-analysis callback.

## Playback corrections made during this investigation

- MusicKit owns automatic Apple Music queue advancement. Removed the competing stopped-state handler that selected the song after the *originally selected* song, even after MusicKit had advanced several entries.
- The autoplay toggle trims/restores the frozen queue continuation while preserving existing entry identities. Explicit repeat/shuffle settings prevent inherited state from changing the intended order. The queue is the currently loaded library page(s), not an Apple Music playlist fetched by the unused URL parser.
- Imported playback invalidates old completion handlers before stopping the old player. Completion waits for the configured delay tail even when autoplay is off, is cancellable on stop/skip, and waits during pause before advancing. Current autoplay/favorites preferences are evaluated after the tail.
- Favorites mix no longer silently falls back to low-rated tracks when no songs qualify. Ten-band levels clear along with the macro bands when audio stops.

## Verification and limits

`sh Tests/run-playback-checks.sh` compiles the production queue-selection functions. `sh Tests/run-audio-checks.sh` checks the production analyzer. These do not simulate MusicKit streaming or AVAudioPlayerNode completion timing.

Hardware acceptance checks: play at least three Apple Music songs across two natural transitions; disable/re-enable autoplay mid-song; verify last-song stop; test imported files with zero and nonzero delay, pause near the end, and stop/skip during the delayed tail. Verify favorites with no eligible songs. Real-device playback remains to be checked while the paired Vision Pro is unavailable.
