import MediaPlayer
import MusicKit
import SwiftUI

struct MusicBrowserView: View {
  var model: VisualizerModel
  @Bindable var player: LocalMusicPlayer
  @Environment(\.dismiss) private var dismiss
  @State private var deviceFiles = false
  @State private var search = ""

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {
        Picker("Source", selection: $deviceFiles) {
          Text("Music Library").tag(false)
          Text("Importable device files").tag(true)
        }.pickerStyle(.segmented)
        Text(player.libraryMessage).font(.callout).foregroundStyle(.secondary)
        if player.loadingLibrary { ProgressView("Loading music…") }
        if !player.loadingLibrary {
          Button("Refresh") { Task { await reload() } }
        }
        TextField("Filter loaded songs", text: $search)
          .textFieldStyle(.roundedBorder)
        List {
          if deviceFiles {
            if !player.deviceTracks.isEmpty {
              Section {
                Button(action: {
                  Task { await player.importAllDeviceTracks() }
                }) {
                  Label("Import All to Playlist (\(player.deviceTracks.count) songs)", systemImage: "arrow.down.circle.fill")
                }
                .disabled(player.importing)
              }
            }
            ForEach(
              player.deviceTracks.filter {
                search.isEmpty || ($0.title ?? "").localizedCaseInsensitiveContains(search)
                  || ($0.artist ?? "").localizedCaseInsensitiveContains(search)
              }, id: \.persistentID
            ) { item in
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(item.title ?? "Song").font(.body)
                  HStack(spacing: 6) {
                    Text(item.artist ?? "Unknown artist").font(.caption).foregroundStyle(.secondary)
                    Label("Direct Audio", systemImage: "waveform")
                      .font(.caption2)
                      .foregroundStyle(.cyan)
                  }
                }
                Spacer()
                if player.isTrackCached(item) != nil {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                } else {
                  Button("Import") {
                    Task {
                      await player.importDeviceTrack(item)
                      player.libraryMessage = player.message
                    }
                  }
                  .buttonStyle(.bordered)
                  .disabled(player.importing)
                }
                Button("Play") {
                  Task { await player.playDeviceTrack(item, model: model) }
                }
                .buttonStyle(.borderedProminent)
              }
            }
          } else {
            ForEach(
              player.librarySongs.filter {
                search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                  || $0.artistName.localizedCaseInsensitiveContains(search)
              }
            ) { song in
              let nonDRM = player.nonDRMItem(for: song)
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(song.title).font(.body)
                  HStack(spacing: 6) {
                    Text(song.artistName).font(.caption).foregroundStyle(.secondary)
                    if nonDRM != nil {
                      Label("DRM-Free • Direct Audio", systemImage: "waveform")
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                    } else {
                      Label("Apple Music", systemImage: "apple.logo")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                  }
                }
                Spacer()
                Button("Play") { Task { await player.playAppleMusic(song, model: model) } }
                  .disabled(player.musicStarting || (nonDRM == nil && song.playParameters == nil))
              }
            }
            if player.libraryHasMore {
              Button("Load more songs") { Task { await player.loadMusicLibrary(reset: false) } }
                .disabled(player.loadingLibrary)
            }
          }
        }
        HStack(spacing: 6) {
          Image(systemName: player.audioTapSource.contains("Microphone") ? "mic.fill" : "waveform")
            .foregroundStyle(player.audioTapSource.contains("Direct") ? .cyan : .green)
          Text("Audio Source: \(player.audioTapSource)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        if player.appleMusicActive {
          Button(player.isPlaying ? "Pause music" : "Resume music") {
            player.togglePause(model: model)
          }
        }
      }
      .padding(24)
      .navigationTitle("Browse music")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    .frame(width: 680, height: 680)
    .task(id: deviceFiles) { await reload() }
    .onDisappear { player.cancelLibraryRequest() }
  }

  private func reload() async {
    if deviceFiles { await player.loadDeviceMusic() } else { await player.loadMusicLibrary() }
  }
}
