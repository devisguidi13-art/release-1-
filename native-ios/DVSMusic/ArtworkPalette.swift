import Foundation
import SwiftUI
import UIKit

/// Optional UI-only tint extracted from cover art; failures revert to DVS green.
@MainActor
final class ArtworkPalette: ObservableObject {
    @Published private(set) var color = Color(red: 0.10, green: 0.29, blue: 0.18)
    private var requestID = UUID()

    func load(_ track: MusicTrack?) {
        let request = UUID()
        requestID = request
        color = Color(red: 0.10, green: 0.29, blue: 0.18)
        guard let track else { return }
        Task {
            let url = await CoverArtService.shared.artworkURL(for: track) ?? track.artworkURL
            guard let url,
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let artwork = UIImage(data: data) else { return }
            let reduced = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in
                artwork.draw(in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            guard let cg = reduced.cgImage,
                  let provider = cg.dataProvider,
                  let cfData = provider.data else { return }
            let bytes = cfData as Data
            guard bytes.count >= 4 else { return }
            guard requestID == request else { return }
            let red = Double(bytes[0]) / 255
            let green = Double(bytes[1]) / 255
            let blue = Double(bytes[2]) / 255
            color = Color(red: max(0.04, red * 0.55), green: max(0.05, green * 0.55),
                          blue: max(0.06, blue * 0.55))
        }
    }
}
