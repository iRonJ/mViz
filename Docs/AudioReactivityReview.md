# Audio/reactivity review — September 12, 2026

Reviewed commits through `ecc2f43` and preserved the additional uncommitted hybrid-library changes. This is a code and logic review with focused hardware controls, not an Instruments GPU/CPU profile.

## Corrections

- **Music Library loading:** its new background device-file lookup called `loadDeviceMusic()`, which invalidated the same request ID that the MusicKit library request was awaiting. The library discarded its own response. Background discovery now fills only the device cache, without cancelling or overwriting the browser request. Hardware check: 100 songs returned, `loading=false`.
- **Treble effects:** `applyStyle` reset noise after the new treble noise calculation. Apply audio noise after the style, and avoid applying the sizzle power curve twice when generating colors.
- **Beat detection:** replace a fixed per-frame onset difference with a time-scaled threshold. Tests cover identical bass ramps at 60/90/120 Hz. Palette normalization now subtracts the same whole rotations from current and target hue to preserve interpolation distance.
- **Density:** Fog and Supernova's 60/80 birth boosts became 61×/81× multipliers, compounded by multiplying mode weights during transitions. Use 0.6/0.8 fractional boosts and a weighted sum. Bound each emitter to approximately 1,200 particles at steady state, with a maximum birth rate of 900/s; stage/world crossfade shares that rate. Cache shared bass/mid power calculations outside the emitter loop.
- **Particle size:** shared slider spans 25–200%, defaults to 70%, and scales style/audio-reactive particles, Flurry wisps, and room geometry/collision scale. Fixed spectrum bars retain their dimensions.
- **Private tap handling:** stop retrying after candidates are exhausted; the old log reached strategy 63. Check processing-queue creation before PID rotation. Do not change buffer frame counts after private initialization. Handle reported sample rate and interleaved stereo using pointer strides, preserving per-channel energy without allocating deinterleaved buffers. Cross-thread numeric counters are atomic.

## Performance assessment

The existing SIMD filter state and accumulated power already avoid per-buffer arrays. Imported audio is analyzed directly in its callback; the new stereo path likewise uses the callback's memory synchronously. The major load problem found was emission multiplication, not PCM copying. RealityKit component updates and UIColor construction still occur in the render loop; they merit an Instruments capture if headset frame timing remains poor. No measured FPS or allocation-rate improvement is claimed here.

## Verification

- `sh Tests/run-audio-checks.sh`: tones, silence, all GEQ centers, and distinct left/right frequencies in interleaved stereo.
- `sh Tests/run-visualizer-checks.sh`: transitions, geometry, lighting, frame-rate-independent onset detection, and particle budget across modes/speeds.
- `sh Tests/run-playback-checks.sh`: production queue selection.
- Signed physical visionOS build and device installation.
- [Library control](music-library-control-visionOS27.txt), [private tap control](audio-tap-control-visionOS27.txt), and [catalog analysis control](cloud-analysis-control-visionOS27.txt).

Diagnostics are explicit Debug launch arguments: `--audio-tap-control`, `--cloud-analysis-control`, and `--music-library-control`. They do not run on a normal launch. The tap control plays a quiet generated tone briefly; the cloud control queries a fixed public catalog item and records response structure/errors, not credentials or song audio.
