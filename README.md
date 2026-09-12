# mViz

A visionOS 26 music visualizer built with SwiftUI, RealityKit, and AVAudioEngine. Built with Xcode 26.6 / visionOS 26.5 SDK. The original Reality Composer assets remain in Packages for reference; the app generates its scene in code.

## Run on Vision Pro

Open `mViz.xcodeproj`, choose the `mViz` scheme and your paired Vision Pro, then Run. The project retains its existing development team and bundle identifier.

Choose **Enter visualizer**. **Show surroundings** switches live between passthrough and full immersion. The floating **Settings** panel exposes movement, shape, speed, intensity, sensitivity, and room interaction. **Leave** exits; the system immersion controls also work.

## Visual modes

- **Flurry spectrum:** ten stationary spectrum columns five meters in front of the viewer, ordered from 31 Hz to 16 kHz to match the GEQ. Colored, wispy light trails curl upward from each column's audio-reactive tip, inspired by the classic macOS Flurry screensaver. The display stays fixed after entry; Recenter brings it in front of you again. Works with passthrough or full immersion and joins automatic transitions. Use imported audio or microphone input for real spectrum data.
- **Nebula:** an orbiting spherical constellation of color with 3D inclined orbital planes that sweep directly above the user (zenith) and beneath the user (nadir) with oscillating rotational direction.
- **Double helix:** braided vertical double-helix strands that spiral upward from directly below your feet, expand around you at eye level, and twist together directly above your head.
- **Aurora:** draped celestial ribbons culminating in a luminous overhead crown / corona dancing directly above the user's head.
- **Vortex:** a 3D cyclone with spiraling height and radius changes, narrowing into a funnel tip directly below the user and spiraling into a vortex spout directly above.
- **Mirror line:** 12 emitters arranged symmetrically in a horizontal line in front of the user perspective, reacting with mirrored wave dynamics and paired colors. Tap **Center stage in front of me** to align the line with your current head orientation.
- **Mirror plane:** a 4×3 planar grid of emitters positioned in front of the user with symmetrical undulating wave motion and mirrored color coordination.
- **Rain:** gentle downward precipitation distributed across the entire overhead sky disk—including directly above the user's head—with stretched particle trails, gravity simulation, and lateral drift.
- **Volcano:** explosive upward eruption from caldera vents spanning the ground plane directly below the user with bass-reactive velocity and spread, warm fiery colors, and gravity pulling particles back down.
- **Room bounce:** a pool of up to 96 audio-reactive physics particles colliding with detected room surfaces, launched from emitters traversing ceiling to floor. Colors dynamically shift across the spectrum based on real-time audio frequency balance. Enable **Include Room bounce**, grant World Sensing access, and look around to scan. The mode joins the automatic journey once sensing is available, or select it manually. If permission or surfaces are unavailable, ambient particles continue and the panel explains the state.

All 360° modes maintain a 1.35m spherical clearance around the user at eye level so emitters never clip into your personal space, while allowing complete freedom to pass directly overhead and underfoot.

## Particle Styles and Forms

- **Particle Styles:** Choose between **Glow** (soft radial bloom), **Sparks** (sharp directional bursts with fast decay), **Halo rings** (expanding rings), **Snowflakes** (intricate 6-point crystals with rotational noise), or **Evolving** (cycles automatically through styles every 12 seconds).
- **Emitter Shapes:** Choose between **Spheres**, **Rings** (torus), **Ribbons** (plane), **Cones**, **Cubes** (box), or **Evolving** (cycles through shapes every 8 seconds, contracting the emission surface before smoothly morphing).
- **Motion Speed:** Adjustable slider spanning 0.25× to 3.00× controlling angular velocity, emitter displacement, and particle flight dynamics.

## Beat Lighting & Audio Sync

- **Styles:** **Evolving** (default — transitions automatically with particle modes, smoothly fading between pulse, strobe, and off phases), **Off** (forced off), **Pulse** (smooth exponential decay), or **Strobe** (crisp onset flash).
- **Mode-Driven Lighting Transitions & Smooth Fading:** Each movement pattern carries its own preferred lighting profile:
  - **No Pulse/Strobe (Off Phase):** Nebula, Mirror plane, and Rain provide calm, peaceful rest periods with zero lighting flashes.
  - **Smooth Pulse:** Double helix, Aurora, and Room bounce feature breathing beat pulses.
  - **Dynamic Strobe:** Volcano, Vortex, and Mirror line feature explosive, energetic beat strobes.
  - As the visualizer transitions between movement modes (either automatically every 18 seconds or upon manual selection), the lighting intensities smoothly **fade in and fade out** according to continuous motion blend weights.
- **Surface & Background Illumination:** Flashes light onto detected room surface meshes (in passthrough) or the surrounding celestial sphere (in full immersion) synchronized to bass beats.
- **Safety & Accessibility:** Flashes are strictly rate-limited to a maximum of 2 Hz (at least 0.5s refractory period). When system **Reduce Motion** is active, strobe automatically downgrades to a gentle pulse.
- **Audio Sync Delay (Latency Compensation):** A slider ranging from `0.00s` to `0.60s` (default `0.25s`). During playlist playback, an `AVAudioUnitDelay` in the audio engine holds the sound output by 0.25 seconds while the visual analyzer taps the audio ahead of time. This compensates for graphics pipeline and beat detection latency, ensuring the visual strobe and beat hit at the exact same instant.

## Performance Optimizations

- **VSYNC-Driven Render Loop:** Replaced the legacy 33ms `Task.sleep` pump with a native RealityKit `SceneEvents.Update` subscription (`content.subscribe(to: SceneEvents.Update.self)`), eliminating the 30 FPS hard cap and allowing the scene to render at native headset refresh rate (90 FPS).
- **Lock-Free / Unfair-Lock Band Storage:** Audio analysis runs on CoreAudio threads and writes frequency bands into `AudioBandStorage` using `os_unfair_lock`, eliminating ~45 `Task { @MainActor }` allocations and queue hops per second.
- **Material Caching & Component Batching:** Room physics particles share 8 pre-generated `UnlitMaterial` buckets updated only when spectral energy shifts, eliminating up to 96 material allocations per frame. Mesh illumination in `RoomEnvironment` reuses a single shared material and short-circuits when light is off.
- **Emitters & Dynamics Optimization:** Blended mode dynamics are computed once per frame rather than inside each emitter loop (from 108 down to 9 calls). Emitters are selectively paused based on mode (e.g. stage emitters are muted when in 360° orbit modes).

## Code Organization

- `mViz/Modes/`: Individual pattern definitions (`AuroraMode`, `HelixMode`, `MirrorLineMode`, `MirrorPlaneMode`, `NebulaMode`, `RainMode`, `RoomBounceMode`, `VolcanoMode`, `VortexMode`) conforming to `MotionPattern`.
- `mViz/Rendering/`: Core RealityKit rendering, `ParticleField`, `MotionBlend`, `ParticleAppearance`, `RoomEnvironment`, `RoomPhysics`, `BeatPulse`, and `AudioColor`.
- `mViz/Audio/`: Audio engine, multi-channel `BandAnalyzer`, `LocalTrack`, and `LocalMusicPlayer`.
- `mViz/Model/`: Observable app state (`VisualizerModel`).
- `mViz/Views/`: SwiftUI views for controls, playlist, and the rebuilt music browser.

## Audio and playlists

**Demo choreography** animates without audio. For surrounding music, choose **Start microphone** or **Use microphone**, grant access, and play music on nearby speakers. Bass drives size/emission, mids drive motion, and treble adds emission accents, with attack/release smoothing.

**Your playlist → Import audio** accepts multiple unprotected audio files from Files. mViz validates them and keeps private copies in its Application Support folder. Tap a track or **Play playlist**. Audio plays through AVAudioEngine and its mixer feeds the band analyzer directly, with independent analysis per output channel. Microphone capture is stopped during file playback. Pause/resume and Next are available in the immersive panel.

The imported track list, star ratings, favorites, and completed-play counts survive relaunches. By default, tracks play in sequential playlist order with **Autoplay next track** enabled. Turning on **Favorites mix** randomly selects tracks rated at least 3 stars OR marked favorite, excluding the current track when other eligible tracks exist. If Favorites mix is on but no tracks qualify, playback stops and explains how to mark eligible songs. Tap a rating menu or heart to edit mViz preferences. Removing a track deletes only the app’s copy. Playlist creation does not modify Apple Music.

**Browse music** provides a unified modal sheet with two tabs:
1. **Music Library:** Uses modern MusicKit APIs (`MusicLibraryRequest<Song>`) to browse your songs with real-time text filtering and pagination. Plays through Apple Music's player; enable microphone input for audio-reactive visuals. Autoplay uses the currently loaded library songs in their displayed library order. Favorites mix applies only to imported tracks.
2. **Importable device files:** Uses MediaPlayer query (`MPMediaQuery.songs()`) to discover locally stored DRM-free songs, with one-tap import into mViz preserving star ratings.

Capture/playback stops on immersive exit, audio interruptions, route changes, and when the control window backgrounds without an active immersive space. Restart audio explicitly after an interruption. No microphone recordings are saved or uploaded.

## Validation

- `sh Tests/run-audio-checks.sh`: silence and low/mid/high tones at 44.1 and 48 kHz.
- `sh Tests/run-visualizer-checks.sh`: all nine movement modes, smooth bounded transitions, stage symmetry, speed scaling, reversing motion, spectral audio colors, strobe rate limits, favorites shuffle, and playlist migration.
- Signed Debug build and live deployment on Apple Vision Pro hardware.

For Apple Music waveform-access findings and a draft inquiry to Apple, see [Apple Music audio access](Docs/AppleMusicAudioAccess.md). Run `sh Tests/run-playback-checks.sh` for production queue-policy regression checks.
