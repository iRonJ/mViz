private let _orbit = NebulaMode()
private let _helix = HelixMode()
private let _aurora = AuroraMode()
private let _vortex = VortexMode()
private let _room = RoomBounceMode()
private let _line = MirrorLineMode()
private let _grid = MirrorPlaneMode()
private let _rain = RainMode()
private let _volcano = VolcanoMode()
private let _fog = CosmicFogMode()
private let _supernova = SupernovaMode()
private let _flurry = FlurrySpectrumMode()

enum MotionMode: String, CaseIterable, Identifiable {
  case orbit = "Nebula"
  case helix = "Double helix"
  case aurora = "Aurora"
  case vortex = "Vortex"
  case room = "Room bounce"
  case line = "Mirror line"
  case grid = "Mirror plane"
  case rain = "Rain"
  case volcano = "Volcano"
  case fog = "Cosmic fog"
  case supernova = "Supernova"
  case flurry = "Flurry spectrum"
  var id: Self { self }

  var index: Int {
    switch self {
    case .orbit: return 0
    case .helix: return 1
    case .aurora: return 2
    case .vortex: return 3
    case .room: return 4
    case .line: return 5
    case .grid: return 6
    case .rain: return 7
    case .volcano: return 8
    case .fog: return 9
    case .supernova: return 10
    case .flurry: return 11
    }
  }

  var definition: any MotionPattern {
    switch self {
    case .orbit: return _orbit
    case .helix: return _helix
    case .aurora: return _aurora
    case .vortex: return _vortex
    case .room: return _room
    case .line: return _line
    case .grid: return _grid
    case .rain: return _rain
    case .volcano: return _volcano
    case .fog: return _fog
    case .supernova: return _supernova
    case .flurry: return _flurry
    }
  }
}

#if canImport(UIKit)
  import UIKit
#endif

protocol MotionPattern {
  /// radius, height, angular offset from the common orbit
  func pose(phase: Float, time: Float) -> SIMD3<Float>
  func dynamics(bass: Float) -> ModeDynamics
  func angularVelocity(time: Float) -> Float
  var lightingStyle: BeatLightingStyle { get }
  #if canImport(UIKit)
    func customEmitterColor(
      index: Int,
      envelope: SIMD3<Float>,
      trebleSizzle: Float,
      paletteHue: Float,
      beatIntensity: Float,
      activity: Float
    ) -> (start: UIColor, end: UIColor)?
  #endif
}

protocol StagePositionable {
  func stagePosition(index: Int, time: Float, bass: Float) -> SIMD3<Float>
}

extension MotionPattern {
  func dynamics(bass: Float) -> ModeDynamics { ModeDynamics() }
  func angularVelocity(time: Float) -> Float { 0 }
  var lightingStyle: BeatLightingStyle { .off }
  #if canImport(UIKit)
    func customEmitterColor(
      index: Int,
      envelope: SIMD3<Float>,
      trebleSizzle: Float,
      paletteHue: Float,
      beatIntensity: Float,
      activity: Float
    ) -> (start: UIColor, end: UIColor)? { nil }
  #endif
}

struct ModeDynamics {
  enum Form { case plane, cone }
  var direction: SIMD3<Float>? = nil
  var speedBoost: Float = 0
  var gravity: Float = 0
  var spreadBoost: Float = 0
  var birthBoost: Float = 0
  var lifeSpan: Double? = nil
  var stretch: Float? = nil
  var sizeScale: Float = 1
  var form: Form? = nil
}

struct MotionRate {
  let multiplier: Float
  init(_ value: Float) { multiplier = min(3, max(0.25, value)) }
  func advance(_ dt: Float) -> Float { dt * multiplier }
  func velocity(_ value: Float) -> Float { value * multiplier }
}

/// Limit each emitter to approximately 1,200 living particles at steady state.
/// Orbit/stage transition weights share this budget; Flurry has its own smaller bound.
enum ParticleBudget {
  static func birthRate(requested: Float, lifeSpan: Double) -> Float {
    guard requested.isFinite, lifeSpan.isFinite else { return 0 }
    return max(0, min(requested, min(900, 1200 / Float(max(0.1, lifeSpan)))))
  }
}
