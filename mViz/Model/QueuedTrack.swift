import Foundation

/// A track added to the continuous shared playback queue from Apple Music, Share Sheet, Drag & Drop, or link paste.
public struct QueuedTrack: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let appleMusicID: String?
  public var title: String
  public var artistName: String
  public var albumTitle: String?
  public var artworkURL: URL?
  public var duration: TimeInterval?
  public var webURL: URL?
  public let addedAt: Date

  public init(
    id: UUID = UUID(),
    appleMusicID: String? = nil,
    title: String,
    artistName: String = "Apple Music",
    albumTitle: String? = nil,
    artworkURL: URL? = nil,
    duration: TimeInterval? = nil,
    webURL: URL? = nil,
    addedAt: Date = Date()
  ) {
    self.id = id
    self.appleMusicID = appleMusicID
    self.title = title
    self.artistName = artistName
    self.albumTitle = albumTitle
    self.artworkURL = artworkURL
    self.duration = duration
    self.webURL = webURL
    self.addedAt = addedAt
  }
}
