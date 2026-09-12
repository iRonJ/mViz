import Foundation

let a = LocalTrack(id: UUID(), title: "A", filename: "a.wav", rating: 1)
let b = LocalTrack(id: UUID(), title: "B", filename: "b.wav", rating: 3)
let c = LocalTrack(id: UUID(), title: "C", filename: "c.wav", isFavorite: true)
let tracks = [a, b, c]

// Test the actual queue policy used by the MusicKit player, including changes
// after native playback has moved beyond the initially selected song.
assert(playbackQueue(tracks, through: a.id, autoplay: false).map(\.id) == [a.id])
assert(playbackQueue(tracks, through: b.id, autoplay: false).map(\.id) == [a.id, b.id])
assert(playbackQueue(tracks, through: c.id, autoplay: false).map(\.id) == tracks.map(\.id))
assert(playbackQueue(tracks, through: b.id, autoplay: true).map(\.id) == tracks.map(\.id))
assert(playbackQueue([LocalTrack](), through: a.id, autoplay: false).isEmpty)

assert(nextTrack(in: tracks, after: a.id, smart: false)?.id == b.id)
assert(nextTrack(in: tracks, after: c.id, smart: false)?.id == a.id)
assert(nextTrack(in: [], after: nil, smart: false) == nil)
assert(nextTrack(in: [a], after: nil, smart: true) == nil)
assert(nextTrack(in: [b], after: b.id, smart: true)?.id == b.id)
for _ in 0..<100 {
  assert(nextTrack(in: tracks, after: b.id, smart: true)?.id == c.id)
  assert(nextTrack(in: tracks, after: c.id, smart: true)?.id == b.id)
}
print("PASS: production autoplay queue policy and imported favorites/sequential selection")
