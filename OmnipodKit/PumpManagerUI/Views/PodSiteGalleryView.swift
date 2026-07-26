//
//  PodSiteGalleryView.swift
//  OmnipodKit
//
//  Standalone gallery for browsing full site-log history (accessible from
//  pod Settings, not part of the pairing flow itself). Gated behind
//  Face ID / Touch ID given the sensitivity of body-site photos.
//

import SwiftUI
import LocalAuthentication

final class PodSiteGalleryViewModel: ObservableObject {

    @Published var isUnlocked: Bool = false
    @Published var authFailed: Bool = false
    @Published var entries: [PodSiteLogEntry] = []

    private let store: PodSiteLogStore

    init(store: PodSiteLogStore) {
        self.store = store
    }

    func authenticate() {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            authenticateWithPasscodeFallback(context: context)
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: LocalizedString("Unlock to view pod site photo history.", comment: "Face ID prompt reason")
        ) { [weak self] success, _ in
            DispatchQueue.main.async {
                if success {
                    self?.unlock()
                } else {
                    self?.authFailed = true
                }
            }
        }
    }

    private func authenticateWithPasscodeFallback(context: LAContext) {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authFailed = true
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: LocalizedString("Unlock to view pod site photo history.", comment: "Passcode prompt reason")
        ) { [weak self] success, _ in
            DispatchQueue.main.async {
                if success {
                    self?.unlock()
                } else {
                    self?.authFailed = true
                }
            }
        }
    }

    private func unlock() {
        isUnlocked = true
        entries = store.loadAll().sorted { $0.date > $1.date }
    }

    func image(for entry: PodSiteLogEntry) -> UIImage? {
        store.image(for: entry)
    }
}

struct PodSiteGalleryView: View {
    @StateObject var viewModel: PodSiteGalleryViewModel

    init(store: PodSiteLogStore = .shared) {
        _viewModel = StateObject(wrappedValue: PodSiteGalleryViewModel(store: store))
    }

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        Group {
            if viewModel.isUnlocked {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(viewModel.entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
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
                                            Text(LocalizedString("No Photo", comment: "Placeholder"))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        )
                                }
                                Text(entry.zone.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text(entry.date, style: .date)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                }
            } else if viewModel.authFailed {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(LocalizedString("Authentication required to view site photos.", comment: "Auth failed message"))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Button(LocalizedString("Try Again", comment: "Retry auth button")) {
                        viewModel.authFailed = false
                        viewModel.authenticate()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                ProgressView()
                    .onAppear { viewModel.authenticate() }
            }
        }
        .navigationTitle(LocalizedString("Pod Site History", comment: "Gallery screen title"))
    }
}