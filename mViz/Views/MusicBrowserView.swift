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
            ForEach(
              player.deviceTracks.filter {
                search.isEmpty || ($0.title ?? "").localizedCaseInsensitiveContains(search)
              }, id: \.persistentID
            ) { item in
              Button("Import \(item.title ?? "Song") • \(item.rating)★") {
                Task {
                  await player.importDeviceTrack(item)
                  player.libraryMessage = player.message
                }
              }.disabled(player.importing)
            }
          } else {
            ForEach(
              player.librarySongs.filter {
                search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                  || $0.artistName.localizedCaseInsensitiveContains(search)
              }
            ) { song in
              HStack {
                VStack(alignment: .leading) {
                  Text(song.title)
                  Text(song.artistName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Play") { Task { await player.playAppleMusic(song, model: model) } }
                  .disabled(player.musicStarting || song.playParameters == nil)
              }
            }
            if player.libraryHasMore {
              Button("Load more songs") { Task { await player.loadMusicLibrary(reset: false) } }
                .disabled(player.loadingLibrary)
            }
          }
        }
        Text(
          "Imported files drive particles directly. Apple Music uses its own player; enable microphone input for audio response."
        )
        .font(.caption).foregroundStyle(.secondary)
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
