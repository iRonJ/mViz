import AVFoundation
import MediaPlayer
import MusicKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
final class LocalMusicPlayer {
  var tracks: [LocalTrack] = []
  var currentID: UUID?
  var isPlaying = false
  var isPaused = false
  var importing = false
  var deviceTracks: [MPMediaItem] = []
  var loadingLibrary = false
  var librarySongs: [Song] = []
  var libraryMessage = ""
  var libraryHasMore = false
  var appleMusicActive = false
  var musicStarting = false
  var audioTapSource = "Direct file audio analysis (zero mic)"
  var userStoppedMicrophone = false
  private var libraryRequestID = 0
  private var libraryOffset = 0
  private var musicMonitor: Task<Void, Never>?
  private var completionTask: Task<Void, Never>?
  private var appleQueueSnapshot: [MusicKit.MusicPlayer.Queue.Entry] = []
  var autoplay = true {
    didSet { updateAppleMusicAutoplay() }
  }
  var smartOrder = false
  var message = "Import audio files to make a playlist."
  private var engine: AVAudioEngine?
  private var node: AVAudioPlayerNode?
  private var tapMixer: AVAudioMixerNode?
  private var delayNode: AVAudioUnitDelay?
  private var generation = 0
  private var tapInstalled = false
#if DEBUG
  private var privateTap: MVPrivateAudioTap?
#endif

  func setAudioDelay(_ delay: Double) {
    delayNode?.delayTime = TimeInterval(max(0, min(2, delay)))
  }

  private static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("mVizMusic", isDirectory: true)
  }

  init() {
    do {
      let url = Self.directory.appendingPathComponent("playlist.json")
      if FileManager.default.fileExists(atPath: url.path) {
        tracks = try JSONDecoder().decode([LocalTrack].self, from: Data(contentsOf: url))
        message = "Playlist restored • \(tracks.count) tracks"
      }
    } catch { message = "Couldn’t restore playlist: \(error.localizedDescription)" }
  }

  private func save() {
    do {
      try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
      try JSONEncoder().encode(tracks).write(
        to: Self.directory.appendingPathComponent("playlist.json"), options: .atomic)
    } catch { message = "Couldn’t save playlist: \(error.localizedDescription)" }
  }

  func importFiles(_ urls: [URL]) async {
    guard !importing else { return }
    importing = true
    defer { importing = false }
    let directory = Self.directory
    var failures = 0
    for url in urls {
      do {
        let track = try await Task.detached(priority: .userInitiated) {
          let scoped = url.startAccessingSecurityScopedResource()
          defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          // Validate before retaining a private copy; DRM/unsupported files fail here.
          let file = try AVAudioFile(forReading: url)
          guard file.length > 0, file.processingFormat.channelCount > 0 else {
            throw CocoaError(.fileReadCorruptFile)
          }
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          let id = UUID()
          let filename = id.uuidString + "." + url.pathExtension
          try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(filename))
          return LocalTrack(
            id: id, title: url.deletingPathExtension().lastPathComponent, filename: filename)
        }.value
        tracks.append(track)
      } catch { failures += 1 }
    }
    message =
      failures == 0
      ? "\(tracks.count) tracks • ready to play"
      : "Imported \(urls.count - failures) files; \(failures) unreadable or unsupported."
    save()
  }

  func rate(_ id: UUID, stars: Int) {
    guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
    tracks[index].rating = min(5, max(0, stars))
    save()
  }

  func toggleFavorite(_ id: UUID) {
    guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
    tracks[index].isFavorite = !(tracks[index].isFavorite ?? false)
    save()
  }

  func cancelLibraryRequest() {
    libraryRequestID += 1
    loadingLibrary = false
  }

  func loadMusicLibrary(reset: Bool = true) async {
    cancelLibraryRequest()
    let requestID = libraryRequestID
    loadingLibrary = true
    if reset {
      librarySongs = []
      libraryOffset = 0
      libraryHasMore = false
    }
    libraryMessage = "Requesting Music Library access…"
    // Permission and library services must never leave the sheet stuck loading.
    let timeout = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(20))
      guard !Task.isCancelled, let self, self.libraryRequestID == requestID, self.loadingLibrary
      else { return }
      self.cancelLibraryRequest()
      self.libraryMessage =
        "Music Library did not respond. Check Music access in Settings and try again. File import is still available."
    }
    defer {
      timeout.cancel()
      if requestID == libraryRequestID { loadingLibrary = false }
    }
    let authorization = await MusicAuthorization.request()
    guard requestID == libraryRequestID, !Task.isCancelled else { return }
    guard authorization == .authorized else {
      libraryMessage =
        authorization == .restricted
        ? "Music access is restricted on this device."
        : "Music access is not allowed. Enable mViz in Settings → Privacy & Security → Media & Apple Music."
      return
    }
    libraryMessage = "Loading your music library…"
    if deviceTracks.isEmpty {
      Task { [weak self] in
        let items = await Task.detached { MPMediaQuery.songs().items }.value
        guard let self, self.libraryRequestID == requestID, let items else { return }
        self.deviceTracks = items.filter { !$0.hasProtectedAsset && !$0.isCloudItem && $0.assetURL != nil }
      }
    }
    do {
      var request = MusicLibraryRequest<Song>()
      request.limit = 100
      request.offset = libraryOffset
      request.sort(by: \.title, ascending: true)
      let response = try await request.response()
      guard requestID == libraryRequestID, !Task.isCancelled else { return }
      let songs = Array(response.items)
      libraryOffset += songs.count
      libraryHasMore = songs.count == 100
      let existing = Set(librarySongs.map(\.id))
      librarySongs.append(contentsOf: songs.filter { !existing.contains($0.id) })
      libraryMessage =
        librarySongs.isEmpty
        ? "Your music library returned no songs. Check that Music is signed in and your library is synced on this Vision Pro, or import audio from Files."
        : "\(librarySongs.count) songs • Select a song to play. Microphone supplies reactive audio when a direct source is unavailable."
    } catch {
      guard requestID == libraryRequestID else { return }
      libraryMessage =
        "Couldn’t load Music Library: \(error.localizedDescription). Try again or import from Files."
    }
  }

  func nonDRMItem(for song: Song) -> MPMediaItem? {
    let cleanSongTitle = song.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let cleanArtist = song.artistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return deviceTracks.first { item in
      guard let itemTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            !item.hasProtectedAsset,
            item.assetURL != nil
      else { return false }
      if itemTitle == cleanSongTitle {
        if cleanArtist.isEmpty { return true }
        if let itemArtist = item.artist?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
          return itemArtist == cleanArtist || itemArtist.contains(cleanArtist) || cleanArtist.contains(itemArtist)
        }
        return true
      }
      return false
    }
  }

  func loadDeviceMusic() async {
    cancelLibraryRequest()
    let requestID = libraryRequestID
    loadingLibrary = true
    libraryMessage = "Looking for importable device files…"
    let timeout = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(20))
      guard !Task.isCancelled, let self, self.libraryRequestID == requestID, self.loadingLibrary
      else { return }
      self.cancelLibraryRequest()
      self.libraryMessage =
        "Device-file access did not respond. Try Music Library or import from Files."
    }
    defer {
      timeout.cancel()
      if requestID == libraryRequestID { loadingLibrary = false }
    }
    guard await MusicAuthorization.request() == .authorized else {
      libraryMessage = "Music access is not allowed. You can still import from Files."
      return
    }
    // The legacy query is only used for exportable assets, not library browsing.
    let items = await Task.detached { MPMediaQuery.songs().items }.value
    guard requestID == libraryRequestID, !Task.isCancelled else { return }
    guard let items else {
      libraryMessage =
        "Device-file access is unavailable. Use the Music Library tab or import from Files."
      return
    }
    deviceTracks = items.filter { !$0.hasProtectedAsset && !$0.isCloudItem && $0.assetURL != nil }
    libraryMessage =
      deviceTracks.isEmpty
      ? "No exportable device files found among \(items.count) songs. Apple Music downloads are often protected; use the Music Library tab for playback or import from Files."
      : "\(deviceTracks.count) importable device files. Star ratings are copied when available."
  }

  func playAppleMusic(_ song: Song, model: VisualizerModel) async {
    guard !musicStarting else { return }
    // Smart Hybrid check: if this song is non-DRM in the user's media library, play in-process with zero-mic direct analysis!
    if let nonDRM = nonDRMItem(for: song) {
      await playDeviceTrack(nonDRM, model: model)
      return
    }
    model.stop()
    let request = generation
    musicStarting = true
    appleMusicActive = true
    model.status = "Starting Apple Music…"
    defer { musicStarting = false }
    do {
      let session = AVAudioSession.sharedInstance()
      try? session.setCategory(.playback, mode: .default)
      try? session.setActive(true)
      let music = ApplicationMusicPlayer.shared
      // Freeze the loaded library order. MusicKit alone advances this queue.
      let songs = librarySongs.contains(where: { $0.id == song.id }) ? librarySongs : [song]
      let queue = ApplicationMusicPlayer.Queue(for: songs, startingAt: song)
      appleQueueSnapshot = Array(queue.entries)
      music.queue = queue
      music.state.repeatMode = MusicKit.MusicPlayer.RepeatMode.none
      music.state.shuffleMode = MusicKit.MusicPlayer.ShuffleMode.off
      updateAppleMusicAutoplay()
      try await music.play()
      guard request == generation else {
        if !appleMusicActive { music.stop() }
        return
      }
      isPlaying = true
      model.status = "Apple Music • \(song.title)"
#if DEBUG
      let tap = MVPrivateAudioTap()
      var tapAnalyzers = [BandAnalyzer(), BandAnalyzer()]
      let tapHandler: @convention(block) (UnsafePointer<Float>?, UInt32) -> Void = { [weak model, weak tap] samples, count in
        guard let model, let tap, let samples, count > 0 else { return }
        let channels = Int(tap.numberOfChannels)
        guard (1...2).contains(channels), tap.sampleRate > 0 else { return }
        var macro = SIMD3<Float>.zero
        var geq10 = SIMD16<Float>.zero
        for channel in 0..<channels {
          let measured = tapAnalyzers[channel].processDetailed(
            samples.advanced(by: channel), count: Int(count), sampleRate: Double(tap.sampleRate), stride: channels)
          for band in 0..<3 { macro[band] = max(macro[band], measured.macro[band]) }
          for band in 0..<10 { geq10[band] = max(geq10[band], measured.geq10[band]) }
        }
        model.bandStorage.bands = macro
        model.bandStorage.bands10 = geq10
      }
      let tapStarted = tap.startDefault(handler: tapHandler)
      if tapStarted {
        tap.onFirstSampleReceived = { [weak self, weak model] in
          guard let self, let model else { return }
          self.audioTapSource = "Direct Tap (Active)"
          if model.listening {
            model.stopListening()
          }
        }
        self.privateTap = tap
        let target = tap.activeTargetName
        self.audioTapSource = "Direct Tap • \(target) (buffering…)"
        NSLog("MVPrivateAudioTap active for Apple Music: %@", tap.diagnostic)
      } else {
        self.audioTapSource = "Microphone fallback • direct tap unavailable"
        NSLog("MVPrivateAudioTap unavailable: %@", tap.diagnostic)
      }
#endif
      var monitorTicks = 0
      var strategyRotationTicks = 0
      var strategiesExhausted = false
      musicMonitor = Task { @MainActor [weak self, weak model] in
        while !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(300))
          guard !Task.isCancelled, let self, self.appleMusicActive, self.generation == request
          else { return }
          monitorTicks += 1
          let state = music.state.playbackStatus
          self.isPlaying = state == .playing
          self.isPaused = state == .paused || state == .interrupted
          if let currentTitle = music.queue.currentEntry?.title {
            let displayStatus = "Apple Music • \(currentTitle)"
            if model?.status != displayStatus && self.isPlaying {
              model?.status = displayStatus
            }
          }
#if DEBUG
          let count = self.privateTap?.samplesReceivedCount ?? 0
          if count > 0 {
            let target = self.privateTap?.activeTargetName ?? "Direct"
            self.audioTapSource = "Direct Tap • \(target) (\(count) frames)"
            if model?.listening == true {
              model?.stopListening()
            }
          } else if self.isPlaying && !self.userStoppedMicrophone && !strategiesExhausted {
            let elapsed = Double(monitorTicks) * 0.3
            let playbackTime = music.playbackTime
            if playbackTime < 0.25 {
              let target = self.privateTap?.activeTargetName ?? "Direct"
              self.audioTapSource = String(format: "Direct Tap • %@ (buffering… %.1fs)", target, elapsed)
            } else {
              strategyRotationTicks += 1
              let target = self.privateTap?.activeTargetName ?? "Direct"
              let currentStrategyElapsed = Double(strategyRotationTicks) * 0.3
              self.audioTapSource = String(format: "Direct Tap • %@ (probing… %.1fs)", target, currentStrategyElapsed)
              let rotationThreshold = (target.contains("mViz App")) ? 14 : 8
              if strategyRotationTicks >= rotationThreshold {
                strategyRotationTicks = 0
                let switched = self.privateTap?.switchToNextStrategy(handler: tapHandler) ?? false
                if !switched {
                  strategiesExhausted = true
                  self.privateTap?.stop()
                  self.audioTapSource = "Microphone fallback • direct tap unavailable"
                  if model?.listening != true && !self.userStoppedMicrophone {
                    self.audioTapSource = "Acoustic Tap (Microphone Fallback)"
                    await model?.start()
                  }
                }
              }
            }
          }
#else
          if monitorTicks >= 25 && self.isPlaying && !self.userStoppedMicrophone && model?.listening != true {
            self.audioTapSource = "Acoustic Tap (Microphone Fallback)"
            await model?.start()
          }
#endif
          if state == .stopped {
            self.appleMusicActive = false
            model?.stop(preserveMusic: false)
            model?.status = "Apple Music stopped"
            model?.bandStorage.bands = .zero
            model?.geqLevels = .zero
            model?.bandStorage.bands10 = .zero
            model?.geq10Levels = .zero
            return
          }
        }
      }
    } catch {
      guard request == generation else { return }
      model.stop()
      libraryMessage = "Couldn’t play \(song.title): \(error.localizedDescription)"
      model.status = libraryMessage
    }
  }

  private func updateAppleMusicAutoplay() {
    guard appleMusicActive else { return }
    let queue = ApplicationMusicPlayer.shared.queue
    guard let current = queue.currentEntry else { return }
    queue.entries = .init(
      playbackQueue(appleQueueSnapshot, through: current.id, autoplay: autoplay))
  }

  func isTrackCached(_ item: MPMediaItem) -> LocalTrack? {
    tracks.first { track in
      if let pid = track.persistentID, pid == item.persistentID {
        return FileManager.default.fileExists(atPath: Self.directory.appendingPathComponent(track.filename).path)
      }
      if track.title == (item.title ?? "") {
        return FileManager.default.fileExists(atPath: Self.directory.appendingPathComponent(track.filename).path)
      }
      return false
    }
  }

  @discardableResult
  func importDeviceTrack(_ item: MPMediaItem) async -> LocalTrack? {
    if let cached = isTrackCached(item) {
      return cached
    }
    guard !importing, let url = item.assetURL, !item.hasProtectedAsset else { return nil }
    importing = true
    defer { importing = false }
    do {
      try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
      let id = UUID()
      let filename = id.uuidString + ".m4a"
      let destination = Self.directory.appendingPathComponent(filename)
      guard
        let exporter = AVAssetExportSession(
          asset: AVURLAsset(url: url), presetName: AVAssetExportPresetAppleM4A)
      else {
        throw CocoaError(.fileReadUnsupportedScheme)
      }
      do { try await exporter.export(to: destination, as: .m4a) } catch {
        try? FileManager.default.removeItem(at: destination)
        throw error
      }
      let track = LocalTrack(
        id: id,
        title: item.title ?? "Device song",
        filename: filename,
        rating: item.rating,
        persistentID: item.persistentID
      )
      tracks.append(track)
      message = "Imported \(item.title ?? "song") with its \(item.rating)★ rating."
      save()
      return track
    } catch {
      message = "Couldn’t import device song: \(error.localizedDescription)"
      return nil
    }
  }

  func playDeviceTrack(_ item: MPMediaItem, model: VisualizerModel) async {
    if let cached = isTrackCached(item) {
      play(cached, model: model)
      return
    }
    model.status = "Preparing direct audio for \(item.title ?? "song")…"
    if let newTrack = await importDeviceTrack(item) {
      play(newTrack, model: model)
    } else {
      model.status = "Unable to prepare \(item.title ?? "song"). Check DRM status."
    }
  }

  func importAllDeviceTracks() async {
    guard !importing else { return }
    var count = 0
    for item in deviceTracks {
      if isTrackCached(item) == nil {
        if await importDeviceTrack(item) != nil {
          count += 1
        }
      }
    }
    libraryMessage = "Imported \(count) new device tracks (\(tracks.count) total in playlist)."
  }

  func play(_ track: LocalTrack, model: VisualizerModel) {
    if model.listening {
      model.stop(preserveMusic: true)
    }
    // Invalidate completions BEFORE stopping the old player (stop can invoke them).
    stop()
    model.demo = false
    let request = generation
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default)
      try session.setActive(true)
      let file = try AVAudioFile(forReading: Self.directory.appendingPathComponent(track.filename))
      let capture = AVAudioEngine()
      let player = AVAudioPlayerNode()
      let tapMix = AVAudioMixerNode()
      let delay = AVAudioUnitDelay()

      delay.delayTime = TimeInterval(max(0, min(2, model.audioDelay)))
      delay.feedback = 0
      delay.lowPassCutoff = Float(max(20000, file.processingFormat.sampleRate / 2))
      delay.wetDryMix = 100

      engine = capture
      node = player
      tapMixer = tapMix
      delayNode = delay

      capture.attach(player)
      capture.attach(tapMix)
      capture.attach(delay)

      capture.connect(player, to: tapMix, format: file.processingFormat)
      let stereoFormat = AVAudioFormat(
        standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: 2)!
      capture.connect(tapMix, to: delay, format: stereoFormat)
      capture.connect(delay, to: capture.mainMixerNode, format: stereoFormat)

      let format = stereoFormat
      var analyzers = Array(repeating: BandAnalyzer(), count: 2)
      tapMix.installTap(onBus: 0, bufferSize: 512, format: format) {
        [weak model] buffer, _ in
        guard let channels = buffer.floatChannelData else { return }
        // Analyze every output channel so hard-panned music still drives visuals.
        var measured = SIMD3<Float>.zero
        var measured10 = SIMD16<Float>.zero
        for channel in 0..<Int(buffer.format.channelCount) {
          let (macro, geq10) = analyzers[channel].processDetailed(
            channels[channel], count: Int(buffer.frameLength), sampleRate: buffer.format.sampleRate)
          measured = SIMD3(
            max(measured.x, macro.x), max(measured.y, macro.y), max(measured.z, macro.z))
          for b in 0..<10 {
            measured10[b] = max(measured10[b], geq10[b])
          }
        }
        model?.bandStorage.bands = measured
        model?.bandStorage.bands10 = measured10
      }
      tapInstalled = true
      player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) {
        [weak self, weak model] _ in
        Task { @MainActor in
          guard let self, let model, self.generation == request else { return }
          let tailDelay = max(0, min(2, model.audioDelay))
          self.completionTask = Task { @MainActor [weak self, weak model] in
            // The delay effect can still hold audible samples after the player finishes.
            do {
              try await Task.sleep(for: .seconds(tailDelay))
              while self?.isPaused == true {
                try await Task.sleep(for: .milliseconds(100))
              }
            } catch { return }
            guard let self, let model, !Task.isCancelled, self.generation == request else { return }
            if let index = self.tracks.firstIndex(where: { $0.id == track.id }) {
              self.tracks[index].playCount += 1
              self.tracks[index].lastPlayed = .now
              self.save()
            }
            // Read current preferences after the tail, so turning autoplay off takes effect.
            if self.autoplay,
              let next = nextTrack(in: self.tracks, after: track.id, smart: self.smartOrder)
            {
              self.play(next, model: model)
            } else {
              model.stop()
              if self.autoplay && self.smartOrder {
                self.message = "No eligible tracks. Favorite a song or rate it 3★ or higher."
              }
            }
          }
        }
      }
      try capture.start()
      currentID = track.id
      isPlaying = true
      isPaused = false
      player.play()
      audioTapSource = "Direct file audio analysis (zero mic)"
      model.status = "Playing • \(track.title)"
      message = "Direct audio analysis • microphone off"
    } catch {
      stop()
      message = "Couldn’t play \(track.title): \(error.localizedDescription)"
      model.status = message
    }
  }

  func togglePause(model: VisualizerModel) {
    if appleMusicActive {
      if isPlaying {
        ApplicationMusicPlayer.shared.pause()
        isPlaying = false
        isPaused = true
        model.status = "Apple Music paused"
        model.bandStorage.bands = .zero
        model.geqLevels = .zero
      } else {
        Task { @MainActor in
          do {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)
            try await ApplicationMusicPlayer.shared.play()
            self.isPlaying = true
            self.isPaused = false
            model.status = "Apple Music • playing"
          } catch {
            message = "Couldn’t resume Apple Music: \(error.localizedDescription)"
          }
        }
      }
      return
    }
    guard let engine, let node else { return }
    if isPlaying {
      node.pause()
      isPlaying = false
      isPaused = true
      model.bands = .zero
      model.bands10 = .zero
      model.geqLevels = .zero
      model.geq10Levels = .zero
      model.status = "Playlist paused"
    } else if isPaused {
      do {
        try AVAudioSession.sharedInstance().setActive(true)
        if !engine.isRunning { try engine.start() }
        node.play()
        isPlaying = true
        isPaused = false
        model.status =
          "Playing • \(tracks.first(where: { $0.id == currentID })?.title ?? "Playlist")"
      } catch {
        model.stop()
        message = error.localizedDescription
      }
    }
  }

  func skip(model: VisualizerModel) {
    if appleMusicActive {
      Task {
        do {
          try await ApplicationMusicPlayer.shared.skipToNextEntry()
          if let title = ApplicationMusicPlayer.shared.queue.currentEntry?.title {
            model.status = "Apple Music • \(title)"
          }
        } catch {
          message = "No next track in Apple Music queue: \(error.localizedDescription)"
        }
      }
      return
    }
    if let next = nextTrack(in: tracks, after: currentID, smart: smartOrder) {
      play(next, model: model)
    } else {
      message =
        tracks.isEmpty
        ? "Import audio files to make a playlist."
        : "No eligible tracks. Favorite a song or rate it 3★ or higher, or turn off Favorites mix."
    }
  }

  func remove(_ track: LocalTrack, model: VisualizerModel) {
    if currentID == track.id {
      model.stop()
      currentID = nil
    }
    tracks.removeAll { $0.id == track.id }
    // Only deletes the app’s imported copy, never the original file.
    try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(track.filename))
    save()
  }

  func stop() {
    generation += 1
    completionTask?.cancel()
    completionTask = nil
    appleQueueSnapshot = []
    musicMonitor?.cancel()
    musicMonitor = nil
    if appleMusicActive { ApplicationMusicPlayer.shared.stop() }
    appleMusicActive = false
#if DEBUG
    privateTap?.stop()
    privateTap = nil
#endif
    node?.stop()
    engine?.stop()
    if tapInstalled { tapMixer?.removeTap(onBus: 0) }
    tapInstalled = false
    engine = nil
    node = nil
    tapMixer = nil
    delayNode = nil
    isPlaying = false
    isPaused = false
    audioTapSource = "Direct file audio analysis (zero mic)"
  }
}
