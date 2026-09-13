import Foundation

// Test standalone parser logic
let testURLs: [(String, String?, String?)] = [
  (
    "https://music.apple.com/us/album/anti-hero/1649200468?i=1649200469",
    "1649200469", // Expected song ID
    "Anti Hero"   // Expected slug title
  ),
  (
    "https://music.apple.com/gb/song/cruel-summer/1468058165",
    "1468058165",
    "Cruel Summer"
  ),
  (
    "https://music.apple.com/us/album/midnights-3am-edition/1650841512",
    nil, // Album only, no ?i=
    "Midnights 3Am Edition"
  ),
  (
    "https://music.apple.com/us/playlist/today-hits/pl.f4d106fed2bd41149aaacabb233eb5eb",
    nil,
    "Today Hits"
  )
]

func parseURL(_ urlString: String) -> (songID: String?, albumID: String?, title: String?) {
  guard let url = URL(string: urlString),
        let host = url.host?.lowercased(),
        host.contains("music.apple.com") || host.contains("itunes.apple.com")
  else { return (nil, nil, nil) }

  let pathComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
  var typeIndex = 0
  if pathComponents.count > 0 && (pathComponents[0].count == 2 || pathComponents[0].contains("-")) {
    typeIndex = 1
  }
  guard typeIndex < pathComponents.count else { return (nil, nil, nil) }

  let typeStr = pathComponents[typeIndex].lowercased()
  let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
  let selectedSongID = components?.queryItems?.first(where: { $0.name.lowercased() == "i" })?.value

  var slug: String? = nil
  if typeIndex + 1 < pathComponents.count {
    let rawSlug = pathComponents[typeIndex + 1]
    if rawSlug.range(of: #"^\d+$"#, options: .regularExpression) == nil && !rawSlug.lowercased().hasPrefix("pl.") {
      slug = rawSlug.replacingOccurrences(of: "-", with: " ").capitalized
    }
  }

  if typeStr == "song" {
    return (pathComponents.last, nil, slug)
  } else if typeStr == "album" {
    return (selectedSongID, pathComponents.last, slug)
  } else if typeStr == "playlist" {
    return (nil, nil, slug)
  }
  return (selectedSongID, nil, slug)
}

for (urlStr, expectedSongID, expectedTitle) in testURLs {
  let result = parseURL(urlStr)
  if let expectedSongID = expectedSongID {
    assert(result.songID == expectedSongID, "Failed songID match for \(urlStr): expected \(expectedSongID), got \(String(describing: result.songID))")
  }
  if let expectedTitle = expectedTitle {
    assert(result.title == expectedTitle, "Failed title match for \(urlStr): expected \(expectedTitle), got \(String(describing: result.title))")
  }
}

// Test queue state logic
struct TestQueueTrack: Identifiable, Equatable {
  let id = UUID()
  let title: String
}

var queue: [TestQueueTrack] = []
var currentIndex: Int? = nil

// Enqueue
let t1 = TestQueueTrack(title: "Track 1")
let t2 = TestQueueTrack(title: "Track 2")
let t3 = TestQueueTrack(title: "Track 3")
queue.append(contentsOf: [t1, t2, t3])
assert(queue.count == 3)

// Start playback
currentIndex = 0
assert(queue[currentIndex!].title == "Track 1")

// Advance
if let cur = currentIndex, cur + 1 < queue.count {
  currentIndex = cur + 1
}
assert(queue[currentIndex!].title == "Track 2")

// Remove track 3
queue.removeAll(where: { $0.id == t3.id })
assert(queue.count == 2)

// Advance past end
if let cur = currentIndex, cur + 1 < queue.count {
  currentIndex = cur + 1
} else {
  currentIndex = nil
}
assert(currentIndex == nil)

print("PASS: Apple Music URL parser tests")
print("PASS: Shared music queue state lifecycle tests")
