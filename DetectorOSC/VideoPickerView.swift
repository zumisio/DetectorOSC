import SwiftUI
import PhotosUI

struct VideoPickerView: UIViewControllerRepresentable {
    @Binding var selectedVideoURL: URL?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPickerView
        
        init(_ parent: VideoPickerView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                parent.presentationMode.wrappedValue.dismiss()
                return
            }
            
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    if let error = error {
                        print("Error loading video: \(error)")
                        return
                    }
                    
                    guard let url = url else { return }
                    
                    // Create a local copy of the video in the app's temporary directory
                    let temporaryDirectoryURL = FileManager.default.temporaryDirectory
                    let localURL = temporaryDirectoryURL.appendingPathComponent(url.lastPathComponent)
                    
                    do {
                        if FileManager.default.fileExists(atPath: localURL.path) {
                            try FileManager.default.removeItem(at: localURL)
                        }
                        try FileManager.default.copyItem(at: url, to: localURL)
                        
                        DispatchQueue.main.async {
                            self.parent.selectedVideoURL = localURL
                            self.parent.presentationMode.wrappedValue.dismiss()
                        }
                    } catch {
                        print("Error copying video to local storage: \(error)")
                    }
                }
            }
        }
    }
}

