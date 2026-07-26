//
//  PodSitePhotoCaptureView.swift
//  OmnipodKit
//
//  Post-attachment step: photographs the site the pod was just placed on
//  (now that it's actually visible/attached), or allows skipping with an
//  explicit confirmation dialog. The zone itself is always logged either way.
//

import SwiftUI
import UIKit

// MARK: - View Model

final class PodSitePhotoCaptureViewModel: ObservableObject {

    let zone: PodSiteZone

    @Published var capturedImage: UIImage?
    @Published var isShowingCamera: Bool = false
    @Published var isShowingSkipConfirmation: Bool = false

    var didFinish: (() -> Void)?

    private let store: PodSiteLogStore

    init(store: PodSiteLogStore, zone: PodSiteZone) {
        self.store = store
        self.zone = zone
    }

    func takePhotoTapped() {
        isShowingCamera = true
    }

    func photoCaptured(_ image: UIImage) {
        capturedImage = image
        isShowingCamera = false
    }

    func saveAndContinueTapped() {
        guard capturedImage == nil else {
            store.save(zone: zone, image: capturedImage)
            didFinish?()
            return
        }
        isShowingSkipConfirmation = true
    }

    func confirmSkipWithoutPhoto() {
        store.save(zone: zone, image: nil)
        isShowingSkipConfirmation = false
        didFinish?()
    }

    func cancelSkip() {
        isShowingSkipConfirmation = false
    }
}

// MARK: - View

struct PodSitePhotoCaptureView: View {
    @ObservedObject var viewModel: PodSitePhotoCaptureViewModel

    var body: some View {
        VStack(spacing: 24) {

            VStack(spacing: 8) {
                Text(LocalizedString("Photograph This Site", comment: "Screen heading"))
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(viewModel.zone.displayName)
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(LocalizedString("This helps you avoid this exact spot next time.", comment: "Rationale"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            Spacer()

            if let image = viewModel.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 320)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text(LocalizedString("No photo taken yet", comment: "Empty state"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    )
                    .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: { viewModel.takePhotoTapped() }) {
                    Label(
                        viewModel.capturedImage == nil
                            ? LocalizedString("Take Photo", comment: "Camera button")
                            : LocalizedString("Retake Photo", comment: "Camera button"),
                        systemImage: "camera.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: { viewModel.saveAndContinueTapped() }) {
                    Text(viewModel.capturedImage == nil
                         ? LocalizedString("Skip Photo", comment: "Skip button")
                         : LocalizedString("Continue", comment: "Continue button"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $viewModel.isShowingCamera) {
            PodSiteCameraCapture { image in
                if let image {
                    viewModel.photoCaptured(image)
                }
            }
        }
        .alert(
            LocalizedString("Log this pod change without a photo?", comment: "Skip confirmation title"),
            isPresented: $viewModel.isShowingSkipConfirmation
        ) {
            Button(LocalizedString("Log Without Photo", comment: "Confirm skip"), role: .destructive) {
                viewModel.confirmSkipWithoutPhoto()
            }
            Button(LocalizedString("Cancel", comment: "Cancel skip"), role: .cancel) {
                viewModel.cancelSkip()
            }
        } message: {
            Text(LocalizedString("The site (\(viewModel.zone.displayName)) will still be logged. You just won't have a photo reference for next time.", comment: "Skip confirmation message"))
        }
    }
}

// MARK: - Camera Capture Wrapper

struct PodSiteCameraCapture: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.cameraCaptureMode = .photo
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage?) -> Void

        init(completion: @escaping (UIImage?) -> Void) {
            self.completion = completion
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true) {
                self.completion(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) {
                self.completion(nil)
            }
        }
    }
}