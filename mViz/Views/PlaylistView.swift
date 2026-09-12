import SwiftUI
import UniformTypeIdentifiers

struct PlaylistView: View {
  var model: VisualizerModel
  @Bindable var player: LocalMusicPlayer
  @State private var showImporter = false
  @State private var showBrowser = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Your playlist").font(.title3.bold())
        Spacer()
        Button("Import audio", systemImage: "plus") { showImporter = true }
          .disabled(player.importing)
      }
      Text(player.message).font(.caption).foregroundStyle(.secondary)
      Toggle("Autoplay next track", isOn: $player.autoplay)
      Toggle("Favorites mix • random 3★+ or favorites", isOn: $player.smartOrder)
        .disabled(player.appleMusicActive)
      Text(
        "Ratings and favorites below are saved in mViz. Imported device songs retain their star rating."
      )
      .font(.caption).foregroundStyle(.secondary)
      Button("Browse music", systemImage: "music.note.list") {
        showBrowser = true
      }.disabled(player.importing)
      if !player.tracks.isEmpty || player.appleMusicActive {
        HStack {
          if player.isPlaying || player.isPaused {
            Button(player.isPlaying ? "Pause" : "Resume") { player.togglePause(model: model) }
            Button("Stop") { model.stop() }
          } else {
            Button("Play playlist") { player.skip(model: model) }
          }
          if !player.appleMusicActive {
            Button("Next", systemImage: "forward.end.fill") { player.skip(model: model) }
          }
        }
      }
      ForEach(player.tracks) { track in
        HStack {
          Button {
            player.play(track, model: model)
          } label: {
            Label(
              track.title,
              systemImage: player.currentID == track.id && player.isPlaying
                ? "waveform" : "play.fill"
            )
            .lineLimit(1)
          }
          Spacer()
          Menu {
            ForEach(0...5, id: \.self) { stars in
              Button(stars == 0 ? "Unrated" : "\(stars) stars") {
                player.rate(track.id, stars: stars)
              }
            }
          } label: {
            Text("\(track.rating ?? 0)★")
          }
          .accessibilityLabel("Rating for \(track.title)")
          Button {
            player.toggleFavorite(track.id)
          } label: {
            Image(systemName: track.isFavorite == true ? "heart.fill" : "heart")
          }.accessibilityLabel(
            "\(track.isFavorite == true ? "Unfavorite" : "Favorite") \(track.title)")
          Button(role: .destructive) {
            player.remove(track, model: model)
          } label: {
            Image(systemName: "minus.circle")
          }.accessibilityLabel("Remove \(track.title) from playlist")
        }
      }
    }
    .sheet(isPresented: $showBrowser) {
      MusicBrowserView(model: model, player: player)
    }
    .fileImporter(
      isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true
    ) { result in
      switch result {
      case .success(let urls): Task { await player.importFiles(urls) }
      case .failure(let error): player.message = "Import failed: \(error.localizedDescription)"
      }
    }
  }
}
