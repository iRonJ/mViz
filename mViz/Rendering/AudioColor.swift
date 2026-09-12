import Foundation

/// Spectral balance sets hue; bass warms it, treble brightens/desaturates it.
func reactiveColor(bands: SIMD3<Float>, offset: Float) -> SIMD3<Float> {
  let total = max(0.001, bands.x + bands.y + bands.z)
  let hue = (0.02 + (bands.y * 0.38 + bands.z * 0.68) / total + offset).truncatingRemainder(
    dividingBy: 1)
  return [
    hue, max(0.25, 0.85 - bands.z * 0.5), min(1, 0.35 + max(bands.x, max(bands.y, bands.z)) * 0.65),
  ]
}
