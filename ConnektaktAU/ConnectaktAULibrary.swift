import Observation
import Foundation

enum ConnectaktAUSampleCategory: String, CaseIterable, Identifiable {
    case all = "ALL"
    case drums = "DRUMS"
    case melodic = "MELODIC"
    case texture = "TEXTURE"
    case vocal = "VOCAL"

    var id: String { rawValue }
}

struct ConnectaktAUSample: Identifiable, Equatable {
    let id: UUID
    let name: String
    let bpm: Int?
    let key: String?
    let duration: String
    let sizeLabel: String
    let category: ConnectaktAUSampleCategory
    let tags: [String]

    init(
        id: UUID = UUID(),
        name: String,
        bpm: Int? = nil,
        key: String? = nil,
        duration: String,
        sizeLabel: String,
        category: ConnectaktAUSampleCategory,
        tags: [String]
    ) {
        self.id = id
        self.name = name
        self.bpm = bpm
        self.key = key
        self.duration = duration
        self.sizeLabel = sizeLabel
        self.category = category
        self.tags = tags
    }
}

@Observable
final class ConnectaktAULibraryModel {
    var searchText = ""
    var selectedCategory: ConnectaktAUSampleCategory = .all
    var selectedSampleID: ConnectaktAUSample.ID?
    var favoriteIDs: Set<UUID> = []

    private(set) var samples: [ConnectaktAUSample] = ConnectaktAULibraryModel.seedSamples

    var filteredSamples: [ConnectaktAUSample] {
        samples.filter { sample in
            let matchesCategory = selectedCategory == .all || sample.category == selectedCategory
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesQuery: Bool
            if query.isEmpty {
                matchesQuery = true
            } else {
                let uppercasedQuery = query.uppercased()
                matchesQuery =
                    sample.name.uppercased().contains(uppercasedQuery) ||
                    sample.tags.joined(separator: " ").uppercased().contains(uppercasedQuery) ||
                    sample.category.rawValue.contains(uppercasedQuery)
            }
            return matchesCategory && matchesQuery
        }
    }

    var selectedSample: ConnectaktAUSample? {
        if let selectedSampleID,
           let match = samples.first(where: { $0.id == selectedSampleID }) {
            return match
        }
        return filteredSamples.first
    }

    func ensureSelection() {
        if let selectedSampleID,
           filteredSamples.contains(where: { $0.id == selectedSampleID }) {
            return
        }
        selectedSampleID = filteredSamples.first?.id
    }

    func select(_ sample: ConnectaktAUSample) {
        selectedSampleID = sample.id
    }

    func toggleFavorite(for sample: ConnectaktAUSample) {
        if favoriteIDs.contains(sample.id) {
            favoriteIDs.remove(sample.id)
        } else {
            favoriteIDs.insert(sample.id)
        }
    }

    func isFavorite(_ sample: ConnectaktAUSample) -> Bool {
        favoriteIDs.contains(sample.id)
    }

    var librarySummary: String {
        let visible = filteredSamples.count
        let total = samples.count
        return "\(visible) OF \(total) SAMPLES VISIBLE"
    }

    private static let seedSamples: [ConnectaktAUSample] = [
        ConnectaktAUSample(name: "KICK_IRON_01", bpm: nil, key: nil, duration: "00:01", sizeLabel: "148 KB", category: .drums, tags: ["KICK", "ANALOG", "PUNCH"]),
        ConnectaktAUSample(name: "SNARE_GLASS_04", bpm: nil, key: nil, duration: "00:01", sizeLabel: "164 KB", category: .drums, tags: ["SNARE", "BRIGHT", "SHORT"]),
        ConnectaktAUSample(name: "HAT_GRID_128", bpm: 128, key: nil, duration: "00:04", sizeLabel: "402 KB", category: .drums, tags: ["HAT", "LOOP", "ELEKTRO"]),
        ConnectaktAUSample(name: "BASSLINE_A_MIN", bpm: 124, key: "A MIN", duration: "00:08", sizeLabel: "1.1 MB", category: .melodic, tags: ["BASS", "MONO", "LOOP"]),
        ConnectaktAUSample(name: "CHORD_WASH_C", bpm: 118, key: "C MAJ", duration: "00:06", sizeLabel: "980 KB", category: .melodic, tags: ["CHORD", "PAD", "ATMOS"]),
        ConnectaktAUSample(name: "TEXTURE_TAPE_DUST", bpm: nil, key: nil, duration: "00:11", sizeLabel: "1.8 MB", category: .texture, tags: ["NOISE", "TEXTURE", "LOFI"]),
        ConnectaktAUSample(name: "VINYL_AIR_LONG", bpm: nil, key: nil, duration: "00:14", sizeLabel: "2.3 MB", category: .texture, tags: ["VINYL", "AMBIENT", "BED"]),
        ConnectaktAUSample(name: "VOCAL_CHOP_E", bpm: 132, key: "E MIN", duration: "00:03", sizeLabel: "512 KB", category: .vocal, tags: ["VOCAL", "CHOP", "HOOK"]),
        ConnectaktAUSample(name: "PHRASE_SHOUT_02", bpm: 140, key: nil, duration: "00:02", sizeLabel: "264 KB", category: .vocal, tags: ["VOCAL", "ONE SHOT", "FX"]),
        ConnectaktAUSample(name: "PLUCK_SEQ_FM", bpm: 126, key: "F MIN", duration: "00:05", sizeLabel: "744 KB", category: .melodic, tags: ["PLUCK", "FM", "SEQUENCE"])
    ]
}
