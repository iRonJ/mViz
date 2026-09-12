#if DEBUG
  import Darwin
  import Foundation
  import ObjectiveC

  /// Read-only runtime inspection. Does not instantiate taps or capture any audio.
  enum AudioAPIDiagnostics {
    static func run() {
      var lines = ["OS: \(ProcessInfo.processInfo.operatingSystemVersionString)"]
      for framework in ["MediaPlaybackCore", "AudioToolbox"] {
        let directory = framework == "MediaPlaybackCore" ? "PrivateFrameworks" : "Frameworks"
        let path = "/System/Library/\(directory)/\(framework).framework/\(framework)"
        let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL)
        lines.append("\(framework): \(handle == nil ? "unavailable" : "loaded")")
        // Leave loaded for this diagnostic process; no private function is invoked.
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

      // Test MVPrivateAudioTap initialization and activation
      let tap = MVPrivateAudioTap()
      var samplesReceived: UInt32 = 0
      let started = tap.startDefault { samples, count in
        samplesReceived += count
      }
      lines.append("\nMVPrivateAudioTap Test:")
      lines.append("  Started: \(started)")
      lines.append("  Diagnostic: \(tap.diagnostic)")
      lines.append("  Sample Rate: \(tap.sampleRate)")
      lines.append("  Channels: \(tap.numberOfChannels)")
      lines.append("  Samples Received: \(samplesReceived)")
      tap.stop()

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
