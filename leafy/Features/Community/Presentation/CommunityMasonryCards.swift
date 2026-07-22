import Foundation
import os
import SwiftUI

enum CommunityCompactTimestampFormatter {
    private static let lock = NSLock()
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    static func string(from date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: date)
    }
}

struct CommunityMasonryPostCard: View {
    let post: CommunityPost
    var isFavoriteLoading = false
    var showsAuthor = true
    var showsCategory = true
    let onOpen: () -> Void
    var onToggleFavorite: (() async -> Void)?

    private let iconSize: CGFloat = 14
    private let longImageAspectRatioThreshold: CGFloat = 0.75
    private let longImageCoverHeightToWidthRatio: CGFloat = 4.0 / 3.0

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                if !post.images.isEmpty {
                    cover
                }

                VStack(alignment: .leading, spacing: post.images.isEmpty ? 8 : 9) {
                    Text(post.title)
                        .leafySubheadline()
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if post.images.isEmpty {
                        let preview = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !preview.isEmpty {
                            Text(preview)
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                    }

                    footer
                }
                .padding(post.images.isEmpty ? 11 : 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .stroke(cardStrokeColor, lineWidth: cardStrokeWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .contentShape(.interaction, RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(.interaction, RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    @ViewBuilder
    private var cover: some View {
        if let image = post.images.first, let url = image.resolvedThumbnailURL {
            GeometryReader { proxy in
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(AppTheme.fill)
                            .overlay(ProgressView().controlSize(.small))
                    case .success(let loadedImage):
                        loadedImage
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Rectangle()
                            .fill(AppTheme.fill)
                            .overlay(Image(systemName: "photo").foregroundStyle(AppTheme.secondaryText))
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(coverAspectRatio, contentMode: .fit)
            .clipped()
        }
    }

    private var coverAspectRatio: CGFloat {
        guard let image = post.images.first else { return 1 / longImageCoverHeightToWidthRatio }
        let width = image.fullWidth ?? image.width ?? image.thumbnailWidth
        let height = image.fullHeight ?? image.height ?? image.thumbnailHeight
        guard let width, let height, width > 0, height > 0 else {
            return 1 / longImageCoverHeightToWidthRatio
        }

        let aspectRatio = CGFloat(width) / CGFloat(height)
        if aspectRatio < longImageAspectRatioThreshold {
            return 1 / longImageCoverHeightToWidthRatio
        }

        return aspectRatio
    }

    private var isPinned: Bool {
        post.pin?.isCurrentlyActive == true
    }

    private var cardStrokeColor: Color {
        isPinned ? AppTheme.warning.opacity(0.9) : AppTheme.separator.opacity(0.7)
    }

    private var cardStrokeWidth: CGFloat {
        isPinned ? 1.4 : 0.7
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                if showsAuthor {
                    CommunityAvatarView(profile: post.isAnonymous ? nil : post.author, size: 20)

                    Text(post.displayAuthorName)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                }

                Spacer(minLength: 0)

                if showsCategory {
                    categoryBadge
                }
            }

            HStack(alignment: .center, spacing: 6) {
                Text(compactTimestamp)
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(1)

                Spacer(minLength: 4)

                HStack(spacing: 7) {
                    CommunityMasonryMetric(icon: "bubble.left", value: "\(post.commentCount)")
                    CommunityMasonryMetric(icon: "heart", value: "\(post.likeCount)")

                    if let onToggleFavorite {
                        Button {
                            Task { await onToggleFavorite() }
                        } label: {
                            favoriteIcon
                                .overlay {
                                    if isFavoriteLoading {
                                        ProgressView()
                                            .controlSize(.mini)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(isFavoriteLoading)
                    } else {
                        favoriteIcon
                    }
                }
                .layoutPriority(1)
            }
        }
    }

    private var compactTimestamp: String {
        guard let date = CommunityTimestampFormatter.parse(post.createdAt) else {
            return post.relativeTimestamp
        }
        return CommunityCompactTimestampFormatter.string(from: date)
    }

    private var categoryBadge: some View {
        Text(post.categoryLabel)
            .microCaption()
            .fontWeight(.semibold)
            .foregroundStyle(AppTheme.accentEmphasis)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(AppTheme.accentSoft, in: Capsule())
    }

    private var favoriteIcon: some View {
        Group {
            if post.viewerHasFavorited {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.accentEmphasis)
                    .frame(width: iconSize, height: iconSize)
            } else {
                Image(systemName: "bookmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .frame(width: iconSize, height: iconSize)
            }
        }
    }
}

struct CommunityMasonryColumns<Item> {
    let left: [Item]
    let right: [Item]

    init(items: [Item]) {
        let state = LeafyPerformanceSignposter.community.beginInterval("masonry-projection")
        defer { LeafyPerformanceSignposter.community.endInterval("masonry-projection", state) }

        var left: [Item] = []
        var right: [Item] = []
        left.reserveCapacity((items.count + 1) / 2)
        right.reserveCapacity(items.count / 2)
        for (index, item) in items.enumerated() {
            if index.isMultiple(of: 2) {
                left.append(item)
            } else {
                right.append(item)
            }
        }
        self.left = left
        self.right = right
    }
}

struct CommunityMasonryGrid<Item: Identifiable & Equatable, Content: View>: View {
    let items: [Item]
    var spacing: CGFloat = 10
    @ViewBuilder let content: (Item) -> Content
    @State private var columns: CommunityMasonryColumns<Item>

    init(
        items: [Item],
        spacing: CGFloat = 10,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.spacing = spacing
        self.content = content
        _columns = State(initialValue: CommunityMasonryColumns(items: items))
    }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            LazyVStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(columns.left.enumerated()), id: \.element.id) { index, item in
                    content(item)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .zIndex(Double(columns.left.count - index))
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            LazyVStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(columns.right.enumerated()), id: \.element.id) { index, item in
                    content(item)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .zIndex(Double(columns.right.count - index))
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .onChange(of: items) { _, newItems in
            columns = CommunityMasonryColumns(items: newItems)
        }
    }
}

struct CommunityMasonryPollCard: View {
    let poll: CommunityPoll
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.caption.weight(.bold))
                    Text("投票")
                        .microCaption()
                        .fontWeight(.semibold)

                    Spacer(minLength: 4)

                    Text(poll.statusText)
                        .microCaption()
                }
                .foregroundStyle(AppTheme.accentEmphasis)

                Text(poll.question)
                    .leafySubheadline()
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                if let detail = poll.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
                    Text(detail)
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(poll.options.prefix(2)) { option in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(AppTheme.accentSoft)
                                .frame(width: 6, height: 6)
                            Text(option.text)
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }

                HStack(spacing: 10) {
                    CommunityMasonryMetric(icon: "person.2", value: "\(poll.totalVoteCount)")
                    if poll.viewerOptionID != nil {
                        CommunityMasonryMetric(icon: "checkmark.circle", value: "已投")
                    }
                    Spacer(minLength: 4)
                    Text(poll.relativeTimestamp)
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                LinearGradient(
                    colors: [AppTheme.accentSoft.opacity(0.9), AppTheme.cardBackground],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .stroke(AppTheme.separator.opacity(0.7), lineWidth: 0.7)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .contentShape(.interaction, RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(.interaction, RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

private struct CommunityMasonryMetric: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 14, height: 14)
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .microCaption()
        .foregroundStyle(AppTheme.tertiaryText)
        .lineLimit(1)
    }
}
