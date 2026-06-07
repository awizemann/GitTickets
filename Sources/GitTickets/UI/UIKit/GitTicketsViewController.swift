#if os(iOS)
import UIKit
import SwiftUI

/// UIKit-facing container for ``GitTicketsView``. The natural drop-in for
/// hosts that don't drive their UI with SwiftUI scenes.
///
/// ```swift
/// // From a UIKit view controller, present the report form modally:
/// let report = GitTicketsViewController()
/// let nav = UINavigationController(rootViewController: report)
/// present(nav, animated: true)
/// ```
///
/// Subclasses `UIHostingController<GitTicketsView>` rather than re-implementing
/// a child-view-controller embed — the hosting controller already does the
/// safe-area / sizeThatFits / layout-pass bridging that a hand-rolled embed
/// would have to mirror by hand.
///
/// The form's built-in "Cancel" button calls SwiftUI's
/// `@Environment(\.dismiss)`, which UIKit wires to the modal/push-pop
/// presentation — so a modal presentation gets dismissed when the user taps
/// Cancel, and a pushed presentation gets popped from the navigation stack.
/// Hosts that want their own bar buttons can add them via
/// `navigationItem.leftBarButtonItem` / `rightBarButtonItem` after init.
@available(iOS 16.0, *)
public final class GitTicketsViewController: UIHostingController<GitTicketsView> {

    public init() {
        super.init(rootView: GitTicketsView())
        title = "Report an Issue"
    }

    @available(*, unavailable)
    @MainActor public required dynamic init?(coder aDecoder: NSCoder) {
        // Storyboard / nib instantiation isn't supported — the rootView depends
        // on `GitTickets.configuration` having been set at app launch, which
        // can't be expressed in Interface Builder. Programmatic init only.
        fatalError("init(coder:) is not supported — instantiate GitTicketsViewController programmatically after GitTickets.configure(_:).")
    }
}
#endif
