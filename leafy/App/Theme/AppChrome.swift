import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct LeafyPageBackground: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    var body: some View {
        ZStack {
            AppTheme.background
            AppTheme.pageGradient(for: themeColorPreference).opacity(0.92)
        }
        .ignoresSafeArea()
    }
}

struct LeafyCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .stroke(AppTheme.separator, lineWidth: 1)
            )
            .shadow(color: AppShadow.color(for: colorScheme), radius: AppShadow.radius, x: 0, y: AppShadow.y)
    }
}

struct LeafyFloatingCapsuleModifier: ViewModifier {
    @Environment(\.leafyControlScale) private var leafyControlScale

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14 * leafyControlScale)
            .padding(.vertical, 10 * leafyControlScale)
            .leafyGlassSurface(in: Capsule())
    }
}

struct LeafyIconBadge: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let systemName: String
    private let explicitTint: Color?
    private let foreground: Color

    init(systemName: String, tint: Color? = nil, foreground: Color = .white) {
        self.systemName = systemName
        explicitTint = tint
        self.foreground = foreground
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14 * leafyControlScale, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: 30 * leafyControlScale, height: 30 * leafyControlScale)
            .background(resolvedTint.gradient, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
    }

    private var resolvedTint: Color {
        explicitTint ?? AppTheme.accent(for: themeColorPreference)
    }
}

struct LeafyGlassIconButton: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let systemName: String
    var showsBadge = false
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label.leafyGlassSurface(in: Circle(), isInteractive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var label: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemName)
                .font(.system(size: 17 * leafyControlScale, weight: .semibold))
                .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
                .frame(width: 38 * leafyControlScale, height: 38 * leafyControlScale)
                .contentShape(Circle())

            if showsBadge {
                Circle()
                    .fill(AppTheme.danger)
                    .frame(width: 9 * leafyControlScale, height: 9 * leafyControlScale)
                    .overlay(
                        Circle()
                            .stroke(Color(uiColor: .systemBackground), lineWidth: 1.5)
                    )
                    .offset(x: -3 * leafyControlScale, y: 3 * leafyControlScale)
            }
    }
    }
}

struct LeafyGlassGroup<Content: View>: View {
    let spacing: CGFloat?
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

struct LeafyOperationAlert: Identifiable {
    enum Kind {
        case success
        case failure
    }

    let id = UUID()
    let kind: Kind
    let message: String
    let buttonTitle: String?
    let action: (() -> Void)?

    var title: String {
        switch kind {
        case .success:
            return L10n.text("操作成功")
        case .failure:
            return L10n.text("操作失败")
        }
    }

    static func success(_ message: String, buttonTitle: String? = nil, action: (() -> Void)? = nil) -> LeafyOperationAlert {
        LeafyOperationAlert(kind: .success, message: message, buttonTitle: buttonTitle, action: action)
    }

    static func failure(_ message: String, buttonTitle: String? = nil, action: (() -> Void)? = nil) -> LeafyOperationAlert {
        LeafyOperationAlert(kind: .failure, message: message, buttonTitle: buttonTitle, action: action)
    }
}

extension View {
    func leafyAdaptiveContentWidth(maxWidth: CGFloat = 760, horizontalPadding: CGFloat = AppSpacing.page) -> some View {
        modifier(LeafyAdaptiveContentWidthModifier(maxWidth: maxWidth, horizontalPadding: horizontalPadding))
    }

    func leafyOperationAlert(_ alert: Binding<LeafyOperationAlert?>) -> some View {
        self.alert(item: alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(L10n.text(alert.buttonTitle ?? alert.defaultButtonTitle))) {
                    alert.action?()
                }
            )
        }
    }

    @ViewBuilder
    func leafyGlassSurface<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        fallbackFill: Color? = nil,
        isInteractive: Bool = false
    ) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            let glass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
            if isInteractive {
                self.glassEffect(glass.interactive(), in: shape)
            } else {
                self.glassEffect(glass, in: shape)
            }
        } else {
            if let fallbackFill {
                self
                    .background(fallbackFill, in: shape)
                    .overlay(
                        shape.stroke(AppTheme.separator, lineWidth: 1)
                    )
            } else {
                self
                    .background(AppTheme.topBarMaterial, in: shape)
                    .overlay(
                        shape.stroke(AppTheme.separator, lineWidth: 1)
                    )
                }
            }
        #else
        if let fallbackFill {
            self
                .background(fallbackFill, in: shape)
                .overlay(shape.stroke(AppTheme.separator, lineWidth: 1))
        } else {
            self
                .background(AppTheme.topBarMaterial, in: shape)
                .overlay(shape.stroke(AppTheme.separator, lineWidth: 1))
        }
        #endif
    }
}

private struct LeafyAdaptiveContentWidthModifier: ViewModifier {
    let maxWidth: CGFloat
    let horizontalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth, alignment: .top)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}

private extension LeafyOperationAlert {
    var defaultButtonTitle: String {
        switch kind {
        case .success:
            return "好"
        case .failure:
            return "知道了"
        }
    }
}

struct LeafySectionTitle: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text(title, language: leafyLanguage))
                .title2()
                .foregroundStyle(AppTheme.primaryText)

            if let subtitle {
                Text(L10n.text(subtitle, language: leafyLanguage))
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LeafyCapsuleChipSurfaceModifier: ViewModifier {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .background(isSelected ? AppTheme.accent(for: themeColorPreference) : AppTheme.cardElevated.opacity(0.96), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? AppTheme.accent(for: themeColorPreference).opacity(0.18) : AppTheme.separator, lineWidth: 1)
            )
    }
}

extension View {
    func leafyCapsuleChipSurface(isSelected: Bool) -> some View {
        modifier(LeafyCapsuleChipSurfaceModifier(isSelected: isSelected))
    }

    func leafyTransparentHorizontalScrollRail() -> some View {
        self
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .background(LeafyScrollRailBackgroundClearer())
    }

    func leafyCardStyle() -> some View {
        modifier(LeafyCardModifier())
    }

    func leafyFloatingCapsule() -> some View {
        modifier(LeafyFloatingCapsuleModifier())
    }
}

#if canImport(UIKit)
private struct LeafyScrollRailBackgroundClearer: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false

        DispatchQueue.main.async {
            Self.clearScrollBackground(around: view)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            Self.clearScrollBackground(around: uiView)
        }
    }

    private static func clearScrollBackground(around view: UIView) {
        guard let scrollView = nearestScrollView(from: view) else { return }

        scrollView.backgroundColor = .clear
        scrollView.isOpaque = false

        for subview in scrollView.subviews {
            subview.backgroundColor = .clear
            subview.isOpaque = false
        }
    }

    private static func nearestScrollView(from view: UIView) -> UIScrollView? {
        var current: UIView? = view
        var depth = 0

        while let candidate = current, depth < 10 {
            if let scrollView = candidate as? UIScrollView {
                return scrollView
            }

            if let scrollView = candidate.firstDescendant(of: UIScrollView.self) {
                return scrollView
            }

            current = candidate.superview
            depth += 1
        }

        return nil
    }
}

private extension UIView {
    func firstDescendant<T: UIView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T {
                return match
            }

            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }

        return nil
    }
}
#else
private struct LeafyScrollRailBackgroundClearer: View {
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
    }
}
#endif
