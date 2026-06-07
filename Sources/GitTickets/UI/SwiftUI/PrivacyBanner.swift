import SwiftUI

/// The mandatory privacy banner shown above the report form.
///
/// Copy is derived from ``RepoVisibility`` unless ``PrivacyPolicy/bannerText``
/// overrides it: public repos warn that submissions land on github.com publicly,
/// private repos soften to "visible to repo maintainers." Adopters that compose
/// their own form should still include this banner — the form must surface what
/// happens to the user's data before the Submit button.
@available(macOS 13.0, iOS 16.0, *)
public struct PrivacyBanner: View {

    @Environment(\.gitTicketsTheme) private var theme
    let repo: RepoCoordinate
    let policy: PrivacyPolicy

    public init(repo: RepoCoordinate, policy: PrivacyPolicy = .default) {
        self.repo = repo
        self.policy = policy
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.tint)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .fill(Color.gray.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
    }

    /// The copy that will be rendered. Exposed for tests so callers don't need
    /// to render the view to assert the wording.
    public var text: String {
        Self.copy(repo: repo, policy: policy)
    }

    static func copy(repo: RepoCoordinate, policy: PrivacyPolicy) -> String {
        if let override = policy.bannerText, !override.isEmpty { return override }
        switch repo.visibility {
        case .public:
            return "This will be posted publicly to github.com/\(repo.owner)/\(repo.name)."
        case .private:
            return "This will be visible to repo maintainers at github.com/\(repo.owner)/\(repo.name)."
        }
    }
}
