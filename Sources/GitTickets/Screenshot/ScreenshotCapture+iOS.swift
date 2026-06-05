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
        // On iPad with Split View / multiple scenes, several windows may have
        // `isKeyWindow == true` cached. Restrict to the scene the user is
        // actually looking at so the screenshot matches the foreground UI.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let active = scenes.first(where: { $0.activationState == .foregroundActive }),
           let window = active.windows.first(where: { $0.isKeyWindow }) ?? active.windows.first {
            return window
        }
        if let inactive = scenes.first(where: { $0.activationState == .foregroundInactive }),
           let window = inactive.windows.first(where: { $0.isKeyWindow }) ?? inactive.windows.first {
            return window
        }
        return scenes.flatMap(\.windows).first(where: { $0.isKeyWindow })
    }
}
#endif
