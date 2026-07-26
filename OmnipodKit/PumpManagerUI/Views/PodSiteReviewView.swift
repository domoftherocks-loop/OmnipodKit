//
//  PodSiteReviewView.swift
//  OmnipodKit
//
//  Pre-attachment step: recommends a rotation zone, shows the most recent
//  photos logged for that zone so the person can see prior placement/scarring,
//  and allows overriding to a different zone before the pod is attached.
//

import SwiftUI
import Combine

// MARK: - View Model

final class PodSiteReviewViewModel: ObservableObject {

    @Published var selectedZone: PodSiteZone
    @Published var recentEntriesForSelectedZone: [PodSiteLogEntry] = []

    var didFinish: ((PodSiteZone) -> Void)?
    var didRequestDeactivation: (() -> Void)?

    private let store: PodSiteLogStore
    private var allLogs: [PodSiteLogEntry] = []

    let recommendedZone: PodSiteZone

    init(store: PodSiteLogStore) {
        self.store = store
        self.allLogs = store.loadAll()
        let recommended = PodSiteRotationAdvisor.recommendedZone(from: allLogs)
        self.recommendedZone = recommended
        self.selectedZone = recommended
        refreshRecentEntries()
    }

    func selectZone(_ zone: PodSiteZone) {
        selectedZone = zone
        refreshRecentEntries()
    }

    func image(for entry: PodSiteLogEntry) -> UIImage? {
        store.image(for: entry)
    }

    func continueTapped() {
        didFinish?(selectedZone)
    }

    private func refreshRecentEntries() {
        recentEntriesForSelectedZone = PodSiteRotationAdvisor.recentEntries(for: selectedZone, in: allLogs, count: 2)
    }
}

// MARK: - View

struct PodSiteReviewView: View {
    @ObservedObject var viewModel: PodSiteReviewViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedString("Recommended Site", comment: "Section header"))
                        .font(.headline)
                        .foregroundColor(.secondary)

                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                        Text(viewModel.recommendedZone.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    Text(LocalizedString("Based on your rotation history, this site has rested longest.", comment: "Rotation rationale"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedString("Choose a Different Site", comment: "Section header"))
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Picker(LocalizedString("Site", comment: "Picker label"), selection: Binding(
                        get: { viewModel.selectedZone },
                        set: { viewModel.selectZone($0) }
                    )) {
                        ForEach(PodSiteZone.allCases) { zone in
                            Text(zone.displayName).tag(zone)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: LocalizedString("Recent Photos: %1$@", comment: "Section header with zone name"), viewModel.selectedZone.displayName))
                        .font(.headline)
                        .foregroundColor(.secondary)

                    if viewModel.recentEntriesForSelectedZone.isEmpty {
                        Text(LocalizedString("No previous photos logged for this site.", comment: "Empty state"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        HStack(spacing: 12) {
                            ForEach(viewModel.recentEntriesForSelectedZone) { entry in
                                VStack(spacing: 4) {
                                    if let image = viewModel.image(for: entry) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 140, height: 140)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    } else {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.tertiarySystemFill))
                                            .frame(width: 140, height: 140)
                                            .overlay(
                                                Text(LocalizedString("No Photo", comment: "Placeholder for skipped photo"))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            )
                                    }
                                    Text(entry.date, style: .date)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 24)

                Button(action: { viewModel.continueTapped() }) {
                    Text(LocalizedString("Continue", comment: "Continue button"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: { viewModel.didRequestDeactivation?() }) {
                    Text(LocalizedString("Deactivate Pod", comment: "Deactivate pod button"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding()
        }
    }
}