//
//  PodSiteLog.swift
//  OmnipodKit
//
//  Data model, local storage, and rotation recommendation logic for
//  pod site placement tracking (scar-tissue / absorption rotation feature).
//

import Foundation
import UIKit

// MARK: - Zone

enum PodSiteZone: String, Codable, CaseIterable, Identifiable {
    case leftArmOuter
    case leftArmInner
    case rightArmOuter
    case rightArmInner
    case leftLowerBack
    case rightLowerBack
    case leftUpperButt
    case rightUpperButt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leftArmOuter:     return LocalizedString("Left Arm – Outer", comment: "Pod site zone")
        case .leftArmInner:     return LocalizedString("Left Arm – Inner", comment: "Pod site zone")
        case .rightArmOuter:    return LocalizedString("Right Arm – Outer", comment: "Pod site zone")
        case .rightArmInner:    return LocalizedString("Right Arm – Inner", comment: "Pod site zone")
        case .leftLowerBack:    return LocalizedString("Left Lower Back", comment: "Pod site zone")
        case .rightLowerBack:   return LocalizedString("Right Lower Back", comment: "Pod site zone")
        case .leftUpperButt:    return LocalizedString("Left Upper Buttock", comment: "Pod site zone")
        case .rightUpperButt:   return LocalizedString("Right Upper Buttock", comment: "Pod site zone")
        }
    }
}

// MARK: - Log Entry

struct PodSiteLogEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let zone: PodSiteZone
    /// Filename within the site-log photo directory. Nil when the person confirmed
    /// skipping the photo for this change.
    let photoFileName: String?

    init(id: UUID = UUID(), date: Date = Date(), zone: PodSiteZone, photoFileName: String?) {
        self.id = id
        self.date = date
        self.zone = zone
        self.photoFileName = photoFileName
    }
}

// MARK: - Rotation Recommendation

enum PodSiteRotationAdvisor {

    static func recommendedZone(from logs: [PodSiteLogEntry], excludeMostRecentCount: Int = 2) -> PodSiteZone {
        let sortedByDateDesc = logs.sorted { $0.date > $1.date }

        var recentZones: [PodSiteZone] = []
        for entry in sortedByDateDesc {
            if !recentZones.contains(entry.zone) {
                recentZones.append(entry.zone)
            }
            if recentZones.count >= excludeMostRecentCount {
                break
            }
        }

        let excluded = Set(recentZones)
        var candidates = PodSiteZone.allCases.filter { !excluded.contains($0) }

        if candidates.isEmpty {
            let lastZone = sortedByDateDesc.first?.zone
            candidates = PodSiteZone.allCases.filter { $0 != lastZone }
        }
        if candidates.isEmpty {
            candidates = PodSiteZone.allCases
        }

        var lastUsed: [PodSiteZone: Date] = [:]
        for entry in sortedByDateDesc {
            if lastUsed[entry.zone] == nil {
                lastUsed[entry.zone] = entry.date
            }
        }

        return candidates.min { lhs, rhs in
            let l = lastUsed[lhs] ?? .distantPast
            let r = lastUsed[rhs] ?? .distantPast
            return l < r
        } ?? candidates[0]
    }

    static func recentEntries(for zone: PodSiteZone, in logs: [PodSiteLogEntry], count: Int = 2) -> [PodSiteLogEntry] {
        return logs
            .filter { $0.zone == zone }
            .sorted { $0.date > $1.date }
            .prefix(count)
            .map { $0 }
    }
}

// MARK: - Storage

final class PodSiteLogStore {

    static let shared = PodSiteLogStore()

    private let retentionInterval: TimeInterval = 60 * 60 * 24 * 30 * 6 // ~6 months

    private let fileManager = FileManager.default
    private let indexFileName = "podSiteLogIndex.json"
    private let photoDirectoryName = "PodSiteLogPhotos"

    private var containerURL: URL {
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return urls[0].appendingPathComponent("PodSiteLog", isDirectory: true)
    }

    private var indexURL: URL {
        containerURL.appendingPathComponent(indexFileName)
    }

    private var photoDirectoryURL: URL {
        containerURL.appendingPathComponent(photoDirectoryName, isDirectory: true)
    }

    private init() {
        try? fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: photoDirectoryURL, withIntermediateDirectories: true)
        var containerURLMutable = containerURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? containerURLMutable.setResourceValues(resourceValues)
    }

    func loadAll() -> [PodSiteLogEntry] {
        purgeExpiredIfNeeded()
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? JSONDecoder().decode([PodSiteLogEntry].self, from: data)) ?? []
    }

    @discardableResult
    func save(zone: PodSiteZone, image: UIImage?) -> PodSiteLogEntry {
        var photoFileName: String? = nil

        if let image, let jpegData = image.jpegData(compressionQuality: 0.85) {
            let fileName = "\(UUID().uuidString).jpg"
            let url = photoDirectoryURL.appendingPathComponent(fileName)
            try? jpegData.write(to: url, options: .atomic)
            photoFileName = fileName
        }

        let entry = PodSiteLogEntry(zone: zone, photoFileName: photoFileName)
        var all = loadAll()
        all.append(entry)
        persist(all)
        return entry
    }

    func image(for entry: PodSiteLogEntry) -> UIImage? {
        guard let fileName = entry.photoFileName else { return nil }
        let url = photoDirectoryURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func purgeExpiredIfNeeded() {
        guard let data = try? Data(contentsOf: indexURL),
              let all = try? JSONDecoder().decode([PodSiteLogEntry].self, from: data) else { return }

        let cutoff = Date().addingTimeInterval(-retentionInterval)
        let (expired, kept) = all.reduce(into: ([PodSiteLogEntry](), [PodSiteLogEntry]())) { result, entry in
            if entry.date < cutoff {
                result.0.append(entry)
            } else {
                result.1.append(entry)
            }
        }

        guard !expired.isEmpty else { return }

        for entry in expired {
            if let fileName = entry.photoFileName {
                try? fileManager.removeItem(at: photoDirectoryURL.appendingPathComponent(fileName))
            }
        }
        persist(kept)
    }

    private func persist(_ entries: [PodSiteLogEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}