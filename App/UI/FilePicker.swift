import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Opens the system document picker in "copy" mode: the chosen files are copied into the
/// app's own temporary folder, so no security-scoped access is needed (which is what made
/// imports fail in sideloaded builds). It accepts every file type and the caller checks
/// the extension, because Files often tags `.pgn` / `.py` files with types a strict
/// filter would grey out.
enum FilePicker {
    private static var current: PickerDelegate?

    static func present(types: [UTType] = [.item],
                        multiple: Bool = true,
                        completion: @escaping ([URL]) -> Void) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = multiple
        let delegate = PickerDelegate { urls in
            current = nil
            if !urls.isEmpty { completion(urls) }
        }
        current = delegate
        picker.delegate = delegate
        guard let top = topViewController() else {
            current = nil
            return
        }
        top.present(picker, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    private final class PickerDelegate: NSObject, UIDocumentPickerDelegate {
        let done: ([URL]) -> Void
        init(done: @escaping ([URL]) -> Void) { self.done = done }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            done(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            done([])
        }
    }
}
