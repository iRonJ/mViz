import AVFoundation
import Observation
import SwiftUI
import os

final class AudioBandStorage: @unchecked Sendable {
  private var lock = os_unfair_lock_s()
  private var _bands = SIMD3<Float>.zero
  private var _bands10 = SIMD16<Float>.zero

  var bands: SIMD3<Float> {
    get {
      os_unfair_lock_lock(&lock)
      defer { os_unfair_lock_unlock(&lock) }
      return _bands
    }
    set {
      os_unfair_lock_lock(&lock)
      _bands = newValue
      os_unfair_lock_unlock(&lock)
    }
  }

  var bands10: SIMD16<Float> {
    get {
      os_unfair_lock_lock(&lock)
      defer { os_unfair_lock_unlock(&lock) }
      return _bands10
    }
    set {
      os_unfair_lock_lock(&lock)
      _bands10 = newValue
      os_unfair_lock_unlock(&lock)
    }
  }
}

@MainActor @Observable
final class VisualizerModel {
  var library = LocalMusicPlayer()
  var immersionStyle: ImmersionStyle = .mixed
  var passthrough: Bool {
    get { immersionStyle is MixedImmersionStyle }
    set { immersionStyle = newValue ? .mixed : .full }
  }
  var motion: MotionMode = .orbit
  var automaticModes = true
  var roomEnabled = true
  var beatLighting: BeatLightingStyle = .evolving
  var lightingIntensity: Float = 0.15
  var reduceMotion = false
  var needsRoomGeometry: Bool { roomEnabled || (beatLighting != .off && passthrough) }
  var roomReady = false
  var roomStatus = "Room bounce enabled • detecting nearby surfaces."
  var shape: EmitterForm = .evolving
  var particleStyle: ParticleStyle = .evolving
  var recenterStage = 0
  var motionSpeed: Float = 2.6
  var activeMotion: MotionMode = .orbit
  let bandStorage = AudioBandStorage()
  var bands: SIMD3<Float> {
    get { bandStorage.bands }
    set { bandStorage.bands = newValue }
  }
  var bands10: SIMD16<Float> {
    get { bandStorage.bands10 }
    set { bandStorage.bands10 = newValue }
  }
  var audioDelay: Double = 0.25 {
    didSet {
      library.setAudioDelay(audioDelay)
    }
  }
  var sensitivity: Float = 3
  var logarithmicLevels = true
  var intensity: Float = 0.7
  var particleSize: Float = 0.7
  var demo = false
  var isImmersed = false
  var transitioning = false
  var listening = false
  var geqLevels: SIMD3<Float> = .zero
  var geq10Levels: SIMD16<Float> = .zero

  var status = "Ready • select music or start microphone"
  private var engine: AVAudioEngine?
  private var tapInstalled = false
  private var generation = 0
  private var observers: [NSObjectProtocol] = []

  init() {
    for name in [
      AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
      AVAudioSession.mediaServicesWereResetNotification,
    ] {
      observers.append(
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
          [weak self] notification in
          // Our own microphone/file category changes are not input loss.
          if notification.name == AVAudioSession.routeChangeNotification,
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            reason == AVAudioSession.RouteChangeReason.categoryChange.rawValue
          {
            return
          }
          if notification.name == AVAudioSession.interruptionNotification,
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            type != AVAudioSession.InterruptionType.began.rawValue
          {
            return
          }
          Task { @MainActor in
            guard let self, self.listening || self.library.isPlaying || self.library.isPaused else {
              return
            }
            if self.library.appleMusicActive { return }
            self.stop()
            self.status = "Audio changed or was interrupted. Restart your microphone or playlist."
          }
        })
    }
  }

  func start() async {
    stop(preserveMusic: library.appleMusicActive || library.isPlaying)
    library.userStoppedMicrophone = false
    demo = false
    let request = generation
    if !library.appleMusicActive && !library.isPlaying {
      status = "Requesting microphone access…"
    }
    let allowed = await AVAudioApplication.requestRecordPermission()
    guard request == generation else { return }
    guard allowed else {
      status = "Microphone access denied. Enable it in Settings → Apps → mViz."
      return
    }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers])
      try session.setActive(true)
      let capture = AVAudioEngine()
      engine = capture
      let input = capture.inputNode
      let format = input.outputFormat(forBus: 0)
      guard format.sampleRate > 0, format.channelCount > 0 else {
        throw NSError(
          domain: "mViz", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "No microphone input is available."])
      }
      var analyzer = BandAnalyzer()
      input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
        guard let samples = buffer.floatChannelData?[0] else { return }
        let (macro, geq10) = analyzer.processDetailed(
          samples, count: Int(buffer.frameLength), sampleRate: buffer.format.sampleRate)
        self?.bandStorage.bands = macro
        self?.bandStorage.bands10 = geq10
      }
      tapInstalled = true
      capture.prepare()
      try capture.start()
      listening = true
      if !library.appleMusicActive && !library.isPlaying {
        status = "Listening • \(session.currentRoute.inputs.first?.portName ?? "Microphone")"
      }
    } catch {
      stop(preserveMusic: library.appleMusicActive || library.isPlaying)
      status = "Couldn’t start microphone: \(error.localizedDescription)"
    }
  }

  /// Stops only the microphone capture without interrupting music playback or deactivating the audio session.
  func stopListening() {
    generation += 1
    library.userStoppedMicrophone = true
    if let engine {
      engine.stop()
      if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
    }
    tapInstalled = false
    engine = nil
    listening = false

    if library.appleMusicActive || library.isPlaying {
      let session = AVAudioSession.sharedInstance()
      try? session.setCategory(.playback, mode: .default)
      try? session.setActive(true)
      if !library.appleMusicActive {
        status =
          "Playing • \(library.tracks.first(where: { $0.id == library.currentID })?.title ?? "Playlist")"
      }
    } else {
      bandStorage.bands = .zero
      bandStorage.bands10 = .zero
      geqLevels = .zero
      geq10Levels = .zero
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      status = "Microphone stopped"
    }
  }

  func stop(preserveMusic: Bool = false) {
    generation += 1
    if !preserveMusic { library.stop() }
    if let engine {
      engine.stop()
      if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
    }
    tapInstalled = false
    engine = nil
    listening = false
    if !preserveMusic {
      bandStorage.bands = .zero
      bandStorage.bands10 = .zero
      geqLevels = .zero
      geq10Levels = .zero
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      status = demo ? "Demo mode • no microphone needed" : "Audio stopped"
    } else {
      let session = AVAudioSession.sharedInstance()
      try? session.setCategory(.playback, mode: .default)
      try? session.setActive(true)
    }
  }
}
