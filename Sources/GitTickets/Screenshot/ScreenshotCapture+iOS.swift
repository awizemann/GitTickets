#if os(iOS)
import Foundation
import UIKit

extension ScreenshotCapture {

    /// iOS capture using `UIGraphicsImageRenderer` over the key window.
    /// No permission prompt — entire process stays in-app.
    @MainActor
    static func platformCapture() async -> Result<Data, ScreenshotCaptureError> {
        guard let window = activeKeyWindow() else {
            return .failure(.noActiveWindow)
        }
        let bounds = window.bounds
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
        guard let data = image.pngData() else {
            return .failure(.encodingFailed)
        }
        return .success(data)
    }

    @MainActor
    private static func activeKeyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })
    }
}
#endif
