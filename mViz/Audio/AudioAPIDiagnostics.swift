#if DEBUG
  import Darwin
  import Foundation
  import ObjectiveC
  import AVFoundation
  import MusicKit

  private final class TapControlStats: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: UInt64 = 0
    private var peak: Float = 0
    func receive(_ samples: UnsafePointer<Float>, count: Int) {
      var maximum: Float = 0
      for index in 0..<count { maximum = max(maximum, abs(samples[index])) }
      lock.lock()
      frames += UInt64(count)
      peak = max(peak, maximum)
      lock.unlock()
    }
    func report() -> String {
      lock.lock()
      defer { lock.unlock() }
      return "frames=\(frames), peak=\(peak)"
    }
  }

  /// Read-only runtime inspection. Does not instantiate taps or capture any audio.
  enum AudioAPIDiagnostics {
    @MainActor static func runCloudAnalysisIfRequested() async {
      guard ProcessInfo.processInfo.arguments.contains("--cloud-analysis-control") else { return }
      var lines = ["MusicKit analysis relationship access control (no playback)"]
      // Relationship names come from the installed framework, not guessed credentials.
      // A fixed public catalog item keeps this diagnostic independent of the user's library.
      for suffix in ["", "?include=audio-analysis,flexml-analysis"] {
        do {
          let url = URL(
            string: "https://api.music.apple.com/v1/catalog/us/songs/1649200469" + suffix)!
          let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
          let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any]
          let items = json?["data"] as? [[String: Any]] ?? []
          lines.append(
            "\(suffix.isEmpty ? "baseline" : "analysis"): HTTP \(response.urlResponse.statusCode), items=\(items.count)"
          )
          for item in items {
            let relationships = item["relationships"] as? [String: Any] ?? [:]
            lines.append("relationships: \(relationships.keys.sorted())")
            for key in ["audio-analysis", "flexml-analysis"] {
              if let relationship = relationships[key] as? [String: Any] {
                let data = relationship["data"] as? [[String: Any]] ?? []
                lines.append("\(key): entries=\(data.count), keys=\(relationship.keys.sorted())")
                for entry in data.prefix(1) {
                  let attributes = entry["attributes"] as? [String: Any] ?? [:]
                  lines.append("attribute names: \(attributes.keys.sorted())")
                }
              }
            }
          }
        } catch let error as MusicDataRequest.Error {
          lines.append(
            "\(suffix): HTTP \(error.originalResponse.urlResponse.statusCode), code=\(error.code)")
        } catch { lines.append("request error: \(error.localizedDescription)") }
      }
      let report = lines.joined(separator: "\n")
      let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      try? report.write(
        to: directory.appendingPathComponent("cloud-analysis-control.txt"), atomically: true,
        encoding: .utf8)
      NSLog("CLOUD ANALYSIS CONTROL: %@", report)
    }
    @MainActor static func runControlIfRequested() async {
      guard ProcessInfo.processInfo.arguments.contains("--audio-tap-control") else { return }
      let engine = AVAudioEngine()
      let player = AVAudioPlayerNode()
      let tap = MVPrivateAudioTap()
      let stats = TapControlStats()
      var lines = [
        "Own-process unprotected tone control",
        ProcessInfo.processInfo.operatingSystemVersionString,
      ]
      defer {
        tap.stop()
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        lines.append(stats.report())
        let report = lines.joined(separator: "\n")
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? report.write(
          to: directory.appendingPathComponent("audio-tap-control.txt"), atomically: true,
          encoding: .utf8)
        NSLog("TAP CONTROL: %@", report)
      }
      do {
        try await Task.sleep(for: .seconds(1))
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers])
        try session.setActive(true)
        lines.append("Record-capable session: \(session.category.rawValue), recordPermission=\(AVAudioApplication.shared.recordPermission.rawValue)")
        lines.append(MVPrivateAudioTap.probeProcessingQueue())
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
        buffer.frameLength = 48000
        for index in 0..<48000 {
          buffer.floatChannelData![0][index] = 0.02 * sin(Float(index) * 2 * .pi * 440 / 48000)
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        try engine.start()
        player.play()
        try await Task.sleep(for: .milliseconds(500))
        lines.append(
          "before tap: engineRunning=\(engine.isRunning), playerPlaying=\(player.isPlaying)")
        let started = tap.start(forPID: getpid()) { samples, count in
          stats.receive(samples, count: Int(count))
        }
        lines.append("start=\(started); \(tap.diagnostic)")
        try await Task.sleep(for: .milliseconds(500))
        lines.append(
          "after tap: engineRunning=\(engine.isRunning), playerPlaying=\(player.isPlaying)")
        try session.setActive(true)
        if !engine.isRunning { try engine.start() }
        player.play()
        try await Task.sleep(for: .seconds(4))
        lines.append(
          "engineRunning=\(engine.isRunning), playerTime=\(String(describing: player.lastRenderTime.flatMap { player.playerTime(forNodeTime: $0) }?.sampleTime))"
        )
      } catch { lines.append("error=\(error.localizedDescription)") }
    }
    static func runIfRequested() {
      if ProcessInfo.processInfo.environment["RUN_AUDIO_DIAGNOSTICS"] != nil {
        run()
      }
    }

    static func run() {
      var lines = ["OS: \(ProcessInfo.processInfo.operatingSystemVersionString)"]
      for framework in ["MediaPlaybackCore", "AudioToolbox"] {
        let directory = framework == "MediaPlaybackCore" ? "PrivateFrameworks" : "Frameworks"
        let path = "/System/Library/\(directory)/\(framework).framework/\(framework)"
        let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL)
        lines.append("\(framework): \(handle == nil ? "unavailable" : "loaded")")
      }
      for name in [
        "MPCProcessAudioTap", "MPCAudioSpectrumAnalyzer", "MPCAudioSpectrumObserver",
        "ATAudioTap", "ATAudioTapDescription",
      ] {
        guard let cls = NSClassFromString(name) else {
          lines.append("\(name): absent")
          continue
        }
        lines.append("\(name): present")
        var count: UInt32 = 0
        if let methods = class_copyMethodList(cls, &count) {
          defer { free(methods) }
          for index in 0..<Int(count) {
            let method = methods[index]
            let selector = NSStringFromSelector(method_getName(method))
            let encoding = method_getTypeEncoding(method).map { String(cString: $0) } ?? "?"
            lines.append("  \(selector) :: \(encoding)")
          }
        }
      }

      lines.append("\n" + MVPrivateAudioTap.runDiagnosticProbe())

      let report = lines.joined(separator: "\n")
      let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      do {
        try report.write(
          to: directory.appendingPathComponent("audio-api-diagnostics.txt"),
          atomically: true, encoding: .utf8)
      } catch { NSLog("Audio API diagnostic write failed: %@", error.localizedDescription) }
      NSLog("Audio API diagnostics:\n%@", report)
    }
  }
#endif
