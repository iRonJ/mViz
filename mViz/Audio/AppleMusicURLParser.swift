import Foundation
import MusicKit

public enum AppleMusicItemType: Equatable {
  case song(id: String)
  case album(id: String, selectedSongID: String?)
  case playlist(id: String)
}

public struct ParsedAppleMusicURL: Equatable {
  public let storefront: String?
  public let itemType: AppleMusicItemType
  public let slugTitle: String?
  public let rawURL: URL

  public var primarySongID: String? {
    switch itemType {
    case .song(let id):
      return id
    case .album(_, let selectedSongID):
      return selectedSongID
    case .playlist:
      return nil
    }
  }

  public var albumID: String? {
    switch itemType {
    case .album(let id, _):
      return id
    default:
      return nil
    }
  }
}

public enum AppleMusicURLParser {
  /// Parse an Apple Music web URL without network requests.
  public static func parse(url: URL) -> ParsedAppleMusicURL? {
    guard let host = url.host?.lowercased(),
      host.contains("music.apple.com") || host.contains("itunes.apple.com")
    else {
      return nil
    }

    let pathComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
    guard !pathComponents.isEmpty else { return nil }

    // Storefront is usually the first component, e.g. "us", "gb", "jp"
    var storefront: String? = nil
    var typeIndex = 0
    if pathComponents[0].count == 2 || pathComponents[0].contains("-") {
      storefront = pathComponents[0]
      typeIndex = 1
    }

    guard typeIndex < pathComponents.count else { return nil }
    let typeStr = pathComponents[typeIndex].lowercased()

    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let selectedSongID = components?.queryItems?.first(where: { $0.name.lowercased() == "i" })?.value

    let slug: String? = {
      if typeIndex + 1 < pathComponents.count {
        let rawSlug = pathComponents[typeIndex + 1]
        // If the next component is an ID (all digits or pl.*), it's not a title slug
        if rawSlug.range(of: #"^\d+$"#, options: .regularExpression) == nil
          && !rawSlug.lowercased().hasPrefix("pl.")
        {
          return cleanSlug(rawSlug)
        }
      }
      return nil
    }()

    if typeStr == "song" {
      // Format: /song/{slug}/{id} or /song/{id}
      let id = pathComponents.last ?? ""
      guard !id.isEmpty else { return nil }
      return ParsedAppleMusicURL(
        storefront: storefront,
        itemType: .song(id: id),
        slugTitle: slug,
        rawURL: url
      )
    } else if typeStr == "album" {
      // Format: /album/{slug}/{albumId} or /album/{albumId}
      let albumId = pathComponents.last ?? ""
      guard !albumId.isEmpty else { return nil }
      return ParsedAppleMusicURL(
        storefront: storefront,
        itemType: .album(id: albumId, selectedSongID: selectedSongID),
        slugTitle: slug,
        rawURL: url
      )
    } else if typeStr == "playlist" {
      // Format: /playlist/{slug}/{playlistId} or /playlist/{playlistId}
      let playlistId = pathComponents.last ?? ""
      guard !playlistId.isEmpty else { return nil }
      return ParsedAppleMusicURL(
        storefront: storefront,
        itemType: .playlist(id: playlistId),
        slugTitle: slug,
        rawURL: url
      )
    }

    // Fallback: if query item 'i' is present, treat as song
    if let songID = selectedSongID {
      return ParsedAppleMusicURL(
        storefront: storefront,
        itemType: .song(id: songID),
        slugTitle: slug,
        rawURL: url
      )
    }

    return nil
  }

  private static func cleanSlug(_ slug: String) -> String {
    slug
      .replacingOccurrences(of: "-", with: " ")
      .capitalized
  }

  /// Resolves an Apple Music URL into one or more QueuedTrack models using MusicKit when authorized.
  public static func resolveTracks(url: URL) async -> [QueuedTrack] {
    guard let parsed = parse(url: url) else {
      // If not an Apple Music URL, create a generic item from the URL
      return [
        QueuedTrack(
          title: url.lastPathComponent.isEmpty ? "Shared Audio" : url.lastPathComponent,
          artistName: url.host ?? "Web Link",
          webURL: url
        )
      ]
    }

    let defaultTitle = parsed.slugTitle ?? "Apple Music Track"

    // If we have a specific song ID (either a direct song URL or ?i= in album URL)
    if let songID = parsed.primarySongID {
      do {
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(songID))
        let response = try await request.response()
        if let song = response.items.first {
          let artworkURL = song.artwork?.url(width: 300, height: 300)
          return [
            QueuedTrack(
              appleMusicID: song.id.rawValue,
              title: song.title,
              artistName: song.artistName,
              albumTitle: song.albumTitle,
              artworkURL: artworkURL,
              duration: song.duration,
              webURL: url
            )
          ]
        }
      } catch {
        // Fallback to parsed metadata if catalog lookup fails (e.g. offline)
      }
      return [
        QueuedTrack(
          appleMusicID: songID,
          title: defaultTitle,
          artistName: "Apple Music",
          webURL: url
        )
      ]
    }

    // If an album URL without specific song ID
    if let albumID = parsed.albumID {
      do {
        var request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(albumID))
        request.properties = [.tracks]
        let response = try await request.response()
        if let album = response.items.first, let tracks = album.tracks {
          let albumArtworkURL = album.artwork?.url(width: 300, height: 300)
          return tracks.compactMap { track -> QueuedTrack? in
            guard let song = track.asSong else { return nil }
            return QueuedTrack(
              appleMusicID: song.id.rawValue,
              title: song.title,
              artistName: song.artistName,
              albumTitle: album.title,
              artworkURL: song.artwork?.url(width: 300, height: 300) ?? albumArtworkURL,
              duration: song.duration,
              webURL: song.url ?? url
            )
          }
        }
      } catch {}
    }

    // If a playlist URL
    if case .playlist(let playlistID) = parsed.itemType {
      do {
        var request = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: MusicItemID(playlistID))
        request.properties = [.tracks]
        let response = try await request.response()
        if let playlist = response.items.first, let tracks = playlist.tracks {
          let playlistArtwork = playlist.artwork?.url(width: 300, height: 300)
          return tracks.compactMap { track -> QueuedTrack? in
            guard let song = track.asSong else { return nil }
            return QueuedTrack(
              appleMusicID: song.id.rawValue,
              title: song.title,
              artistName: song.artistName,
              albumTitle: song.albumTitle,
              artworkURL: song.artwork?.url(width: 300, height: 300) ?? playlistArtwork,
              duration: song.duration,
              webURL: song.url ?? url
            )
          }
        }
      } catch {}
    }

    return [
      QueuedTrack(
        appleMusicID: parsed.primarySongID,
        title: defaultTitle,
        artistName: "Apple Music",
        webURL: url
      )
    ]
  }
}

private extension Track {
  var asSong: Song? {
    if case .song(let song) = self { return song }
    return nil
  }
}
