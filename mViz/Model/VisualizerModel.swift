import AVFoundation
import Observation
import SwiftUI
import os

final class AudioBandStorage: @unchecked Sendable {
  private var lock = os_unfair_lock_s()
  private var _bands = SIMD3<Float>.zero
  private var _bands10 = SIMD16<Float>.zero

  func update(macro: SIMD3<Float>, geq10: SIMD16<Float>) {
    os_unfair_lock_lock(&lock)
    _bands = macro
    _bands10 = geq10
    os_unfair_lock_unlock(&lock)
  }

  func read() -> (bands: SIMD3<Float>, bands10: SIMD16<Float>) {
    os_unfair_lock_lock(&lock)
    let b = _bands
    let b10 = _bands10
    os_unfair_lock_unlock(&lock)
    return (b, b10)
  }

  var bands: SIMD3<Float> {
    get { read().bands }
    set {
      os_unfair_lock_lock(&lock)
      _bands = newValue
      os_unfair_lock_unlock(&lock)
    }
  }

  var bands10: SIMD16<Float> {
    get { read().bands10 }
    set {
      os_unfair_lock_lock(&lock)
      _bands10 = newValue
      os_unfair_lock_unlock(&lock)
    }
  }
}

@MainActor @Observable
final class VisualizerModel {
  private enum SettingsKeys {
    static let audioDelay = "mViz.audioDelay"
    static let motionSpeed = "mViz.motionSpeed"
    static let motion = "mViz.motion"
    static let automaticModes = "mViz.automaticModes"
    static let roomEnabled = "mViz.roomEnabled"
    static let shape = "mViz.shape"
    static let particleStyle = "mViz.particleStyle"
    static let particleSize = "mViz.particleSize"
    static let intensity = "mViz.intensity"
    static let sensitivity = "mViz.sensitivity"
    static let beatLighting = "mViz.beatLighting"
    static let lightingIntensity = "mViz.lightingIntensity"
    static let passthrough = "mViz.passthrough"
    static let logarithmicLevels = "mViz.logarithmicLevels"
    static let transientDynamics = "mViz.transientDynamics"
  }

  var library = LocalMusicPlayer()
  var immersionStyle: ImmersionStyle = .mixed
  var passthrough: Bool {
    get { immersionStyle is MixedImmersionStyle }
    set {
      immersionStyle = newValue ? .mixed : .full
      UserDefaults.standard.set(newValue, forKey: SettingsKeys.passthrough)
    }
  }
  var motion: MotionMode = .orbit {
    didSet { UserDefaults.standard.set(motion.rawValue, forKey: SettingsKeys.motion) }
  }
  var automaticModes = true {
    didSet { UserDefaults.standard.set(automaticModes, forKey: SettingsKeys.automaticModes) }
  }
  var roomEnabled = true {
    didSet { UserDefaults.standard.set(roomEnabled, forKey: SettingsKeys.roomEnabled) }
  }
  var beatLighting: BeatLightingStyle = .evolving {
    didSet { UserDefaults.standard.set(beatLighting.rawValue, forKey: SettingsKeys.beatLighting) }
  }
  var lightingIntensity: Float = 0.15 {
    didSet { UserDefaults.standard.set(lightingIntensity, forKey: SettingsKeys.lightingIntensity) }
  }
  var reduceMotion = false
  var needsRoomGeometry: Bool { roomEnabled || (beatLighting != .off && passthrough) }
  var roomReady = false
  var roomStatus = "Room bounce enabled • detecting nearby surfaces."
  var shape: EmitterForm = .evolving {
    didSet { UserDefaults.standard.set(shape.rawValue, forKey: SettingsKeys.shape) }
  }
  var particleStyle: ParticleStyle = .evolving {
    didSet { UserDefaults.standard.set(particleStyle.rawValue, forKey: SettingsKeys.particleStyle) }
  }
  var recenterStage = 0
  var motionSpeed: Float = 1.0 {
    didSet { UserDefaults.standard.set(motionSpeed, forKey: SettingsKeys.motionSpeed) }
  }
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
  var audioDelay: Double = 0.0 {
    didSet {
      library.setAudioDelay(audioDelay)
      UserDefaults.standard.set(audioDelay, forKey: SettingsKeys.audioDelay)
    }
  }
  var sensitivity: Float = 3 {
    didSet { UserDefaults.standard.set(sensitivity, forKey: SettingsKeys.sensitivity) }
  }
  var logarithmicLevels = true {
    didSet { UserDefaults.standard.set(logarithmicLevels, forKey: SettingsKeys.logarithmicLevels) }
  }
  var transientDynamics = true {
    didSet { UserDefaults.standard.set(transientDynamics, forKey: SettingsKeys.transientDynamics) }
  }
  var intensity: Float = 0.7 {
    didSet { UserDefaults.standard.set(intensity, forKey: SettingsKeys.intensity) }
  }
  var particleSize: Float = 0.7 {
    didSet { UserDefaults.standard.set(particleSize, forKey: SettingsKeys.particleSize) }
  }
  var demo = false
  var isImmersed = false
  var transitioning = false
  var listening = false
  var geqLevels: SIMD3<Float> = .zero
  var geq10Levels: SIMD16<Float> = .zero
  var macroFlux: SIMD3<Float> = .zero
  var geq10Flux: SIMD16<Float> = .zero

  var status = "Ready • select music or start microphone"
  private var engine: AVAudioEngine?
  private var tapInstalled = false
  private var generation = 0
  private var observers: [NSObjectProtocol] = []

  private func loadSavedSettings() {
    let defaults = UserDefaults.standard
    if let delay = defaults.object(forKey: SettingsKeys.audioDelay) as? Double {
      audioDelay = max(0, min(2, delay))
    }
    if let speed = defaults.object(forKey: SettingsKeys.motionSpeed) as? Float {
      motionSpeed = max(0.25, min(3.0, speed))
    }
    if let motionRaw = defaults.string(forKey: SettingsKeys.motion),
      let savedMotion = MotionMode(rawValue: motionRaw) {
      motion = savedMotion
    }
    if let autoModes = defaults.object(forKey: SettingsKeys.automaticModes) as? Bool {
      automaticModes = autoModes
    }
    if let room = defaults.object(forKey: SettingsKeys.roomEnabled) as? Bool {
      roomEnabled = room
    }
    if let shapeRaw = defaults.string(forKey: SettingsKeys.shape),
      let savedShape = EmitterForm(rawValue: shapeRaw) {
      shape = savedShape
    }
    if let styleRaw = defaults.string(forKey: SettingsKeys.particleStyle),
      let savedStyle = ParticleStyle(rawValue: styleRaw) {
      particleStyle = savedStyle
    }
    if let size = defaults.object(forKey: SettingsKeys.particleSize) as? Float {
      particleSize = max(0.25, min(2.0, size))
    }
    if let intens = defaults.object(forKey: SettingsKeys.intensity) as? Float {
      intensity = max(0.2, min(1.0, intens))
    }
    if let sens = defaults.object(forKey: SettingsKeys.sensitivity) as? Float {
      sensitivity = max(0.5, min(10.0, sens))
    }
    if let lightRaw = defaults.string(forKey: SettingsKeys.beatLighting),
      let savedLight = BeatLightingStyle(rawValue: lightRaw) {
      beatLighting = savedLight
    }
    if let lightIntens = defaults.object(forKey: SettingsKeys.lightingIntensity) as? Float {
      lightingIntensity = max(0.03, min(0.3, lightIntens))
    }
    if let isPassthrough = defaults.object(forKey: SettingsKeys.passthrough) as? Bool {
      immersionStyle = isPassthrough ? .mixed : .full
    }
    if let logLevels = defaults.object(forKey: SettingsKeys.logarithmicLevels) as? Bool {
      logarithmicLevels = logLevels
    }
    if let transDynamics = defaults.object(forKey: SettingsKeys.transientDynamics) as? Bool {
      transientDynamics = transDynamics
    }
  }

  init() {
    loadSavedSettings()
    library.setAudioDelay(audioDelay)
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
      var analyzer = MultiChannelAnalyzer(maxChannels: 1)
      input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
        if let (macro, geq10) = analyzer.process(buffer: buffer) {
          self?.bandStorage.update(macro: macro, geq10: geq10)
        }
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
