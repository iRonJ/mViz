import Foundation

struct LocalTrack: Codable, Identifiable {
  var id: UUID
  var title: String
  var filename: String
  var playCount: Int
  var lastPlayed: Date?
  var rating: Int?
  var isFavorite: Bool?
  var persistentID: UInt64?

  init(
    id: UUID,
    title: String,
    filename: String,
    playCount: Int = 0,
    lastPlayed: Date? = nil,
    rating: Int? = nil,
    isFavorite: Bool? = nil,
    persistentID: UInt64? = nil
  ) {
    self.id = id
    self.title = title
    self.filename = filename
    self.playCount = playCount
    self.lastPlayed = lastPlayed
    self.rating = rating
    self.isFavorite = isFavorite
    self.persistentID = persistentID
  }

  enum CodingKeys: String, CodingKey {
    case id, title, filename, playCount, lastPlayed, rating, isFavorite, persistentID
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    filename = try container.decode(String.self, forKey: .filename)
    playCount = try container.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
    lastPlayed = try container.decodeIfPresent(Date.self, forKey: .lastPlayed)
    rating = try container.decodeIfPresent(Int.self, forKey: .rating)
    isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite)
    persistentID = try container.decodeIfPresent(UInt64.self, forKey: .persistentID)
  }

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
