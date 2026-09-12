import Foundation

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
  var definition: any MotionPattern {
    switch self {
    case .orbit: NebulaMode()
    case .helix: HelixMode()
    case .aurora: AuroraMode()
    case .vortex: VortexMode()
    case .room: RoomBounceMode()
    case .line: MirrorLineMode()
    case .grid: MirrorPlaneMode()
    case .rain: RainMode()
    case .volcano: VolcanoMode()
    case .fog: CosmicFogMode()
    case .supernova: SupernovaMode()
    case .flurry: FlurrySpectrumMode()
    }
  }
}

protocol MotionPattern {
  /// radius, height, angular offset from the common orbit
  func pose(phase: Float, time: Float) -> SIMD3<Float>
  func dynamics(bass: Float) -> ModeDynamics
  func angularVelocity(time: Float) -> Float
  var lightingStyle: BeatLightingStyle { get }
}

extension MotionPattern {
  func dynamics(bass: Float) -> ModeDynamics { ModeDynamics() }
  func angularVelocity(time: Float) -> Float { 0 }
  var lightingStyle: BeatLightingStyle { .off }
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
