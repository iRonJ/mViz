import Foundation

struct LocalTrack: Codable, Identifiable {
  var id: UUID
  var title: String
  var filename: String
  var playCount = 0
  var lastPlayed: Date?
  var rating: Int?
  var isFavorite: Bool?
  var qualifiesForMix: Bool { (rating ?? 0) >= 3 || isFavorite == true }
}

/// Random favorites/3+ stars, excluding the current track when alternatives exist.
/// An empty eligible set stays empty; never silently play low-rated tracks.
func nextTrack(in tracks: [LocalTrack], after current: UUID?, smart: Bool) -> LocalTrack? {
  let eligible = smart ? tracks.filter(\.qualifiesForMix) : tracks
  guard !eligible.isEmpty else { return nil }
  if !smart, let index = eligible.firstIndex(where: { $0.id == current }) {
    return eligible[(index + 1) % eligible.count]
  }
  let candidates = eligible.count > 1 ? eligible.filter { $0.id != current } : eligible
  return smart ? candidates.randomElement() : candidates.first
}

/// Keep the current entry's identity and history; only trim its continuation.
func playbackQueue<Entry: Identifiable>(
  _ entries: [Entry], through current: Entry.ID, autoplay: Bool
) -> [Entry] {
  guard !autoplay, let index = entries.firstIndex(where: { $0.id == current }) else {
    return entries
  }
  return Array(entries.prefix(through: index))
}
