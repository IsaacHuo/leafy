import SwiftData
import SwiftSoup
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct TimetableScrollContainer<Corner: View, Header: View, Axis: View, GridBody: View>: UIViewRepresentable {
    let axisWidth: CGFloat
    let headerHeight: CGFloat
    let totalWeeks: Int
    let weekStride: CGFloat
    let dayColumnWidth: CGFloat
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let allowsVerticalScroll: Bool
    @Binding var currentWeek: Int
    @Binding var scrollToWeek: Int?
    @Binding var isAwayFromCurrentWeek: Bool
    let containerID: String
    let corner: Corner
    let header: Header
    let axis: Axis
    let gridBody: GridBody
    let onFirstInteractiveLayout: () -> Void

    init(
        axisWidth: CGFloat,
        headerHeight: CGFloat,
        totalWeeks: Int,
        weekStride: CGFloat,
        dayColumnWidth: CGFloat,
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        allowsVerticalScroll: Bool,
        currentWeek: Binding<Int>,
        scrollToWeek: Binding<Int?>,
        isAwayFromCurrentWeek: Binding<Bool>,
        containerID: String,
        onFirstInteractiveLayout: @escaping () -> Void = {},
        @ViewBuilder corner: () -> Corner,
        @ViewBuilder header: () -> Header,
        @ViewBuilder axis: () -> Axis,
        @ViewBuilder body: () -> GridBody
    ) {
        self.axisWidth = axisWidth
        self.headerHeight = headerHeight
        self.totalWeeks = totalWeeks
        self.weekStride = weekStride
        self.dayColumnWidth = dayColumnWidth
        self.rowHeight = rowHeight
        self.rowSpacing = rowSpacing
        self.allowsVerticalScroll = allowsVerticalScroll
        _currentWeek = currentWeek
        _scrollToWeek = scrollToWeek
        _isAwayFromCurrentWeek = isAwayFromCurrentWeek
        self.containerID = containerID
        self.corner = corner()
        self.header = header()
        self.axis = axis()
        self.gridBody = body()
        self.onFirstInteractiveLayout = onFirstInteractiveLayout
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        context.coordinator.makeContainer()
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncStateFromParent()
        context.coordinator.updateContent()
        context.coordinator.scheduleLayoutUpdate()
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.isDismantled = true
        coordinator.bodyScrollView.delegate = nil
        coordinator.deferredScrollRetryScheduled = false
        coordinator.layoutUpdateScheduled = false
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: TimetableScrollContainer
        var isDismantled = false
        let cornerHost: UIHostingController<Corner>
        let headerHost: UIHostingController<Header>
        let axisHost: UIHostingController<Axis>
        let bodyHost: UIHostingController<GridBody>

        let rootView: TimetableScrollRootView
        let cornerContainer = UIView()
        let headerScrollView = UIScrollView()
        let axisScrollView = UIScrollView()
        let bodyScrollView = UIScrollView()

        private var cornerWidthConstraint: NSLayoutConstraint?
        private var cornerHeightConstraint: NSLayoutConstraint?
        private var headerHeightConstraint: NSLayoutConstraint?
        private var axisWidthConstraint: NSLayoutConstraint?
        private var lastReportedAwayFromCurrentWeek = false
        private var isAnimatingToTarget = false
        var deferredScrollRetryScheduled = false
        var layoutUpdateScheduled = false
        private var hasAppliedInitialScrollRequest = false
        private var hasReportedInteractiveLayout = false
        private var lastLayoutSignature: LayoutSignature?
        private var pendingLayoutRealignmentWeek: Int?
        private var pendingLayoutRealignmentPasses = 0
        private var dragStartWeek = 1

        init(_ parent: TimetableScrollContainer) {
            self.parent = parent
            rootView = TimetableScrollRootView()
            cornerHost = UIHostingController(rootView: parent.corner)
            headerHost = UIHostingController(rootView: parent.header)
            axisHost = UIHostingController(rootView: parent.axis)
            bodyHost = UIHostingController(rootView: parent.gridBody)
            super.init()
            rootView.onBoundsChange = { [weak self] in
                guard let self, !self.isDismantled else { return }
                self.scheduleLayoutUpdate()
            }
        }

        @inline(never)
        deinit {
            bodyScrollView.delegate = nil
        }

        func syncStateFromParent() {
            if lastReportedAwayFromCurrentWeek != parent.isAwayFromCurrentWeek {
                lastReportedAwayFromCurrentWeek = parent.isAwayFromCurrentWeek
            }
        }

        func makeContainer() -> UIView {
            rootView.backgroundColor = .clear

            [cornerContainer, headerScrollView, axisScrollView, bodyScrollView].forEach {
                $0.translatesAutoresizingMaskIntoConstraints = false
                $0.backgroundColor = .clear
            }

            headerScrollView.showsHorizontalScrollIndicator = false
            headerScrollView.showsVerticalScrollIndicator = false
            headerScrollView.isScrollEnabled = false
            headerScrollView.contentInsetAdjustmentBehavior = .never

            axisScrollView.showsHorizontalScrollIndicator = false
            axisScrollView.showsVerticalScrollIndicator = false
            axisScrollView.isScrollEnabled = false
            axisScrollView.contentInsetAdjustmentBehavior = .never

            bodyScrollView.showsHorizontalScrollIndicator = false
            bodyScrollView.showsVerticalScrollIndicator = false
            bodyScrollView.alwaysBounceHorizontal = false
            bodyScrollView.alwaysBounceVertical = false
            bodyScrollView.bounces = false
            bodyScrollView.decelerationRate = .fast
            bodyScrollView.isDirectionalLockEnabled = true
            bodyScrollView.contentInsetAdjustmentBehavior = .never
            bodyScrollView.delegate = self

            rootView.addSubview(cornerContainer)
            rootView.addSubview(headerScrollView)
            rootView.addSubview(axisScrollView)
            rootView.addSubview(bodyScrollView)

            cornerWidthConstraint = cornerContainer.widthAnchor.constraint(equalToConstant: parent.axisWidth)
            cornerHeightConstraint = cornerContainer.heightAnchor.constraint(equalToConstant: parent.headerHeight)
            headerHeightConstraint = headerScrollView.heightAnchor.constraint(equalToConstant: parent.headerHeight)
            axisWidthConstraint = axisScrollView.widthAnchor.constraint(equalToConstant: parent.axisWidth)

            NSLayoutConstraint.activate([
                cornerContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
                cornerContainer.topAnchor.constraint(equalTo: rootView.topAnchor),
                cornerWidthConstraint!,
                cornerHeightConstraint!,

                headerScrollView.leadingAnchor.constraint(equalTo: cornerContainer.trailingAnchor, constant: AppSpacing.micro),
                headerScrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
                headerScrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
                headerHeightConstraint!,

                axisScrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
                axisScrollView.topAnchor.constraint(equalTo: cornerContainer.bottomAnchor, constant: AppSpacing.micro),
                axisScrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
                axisWidthConstraint!,

                bodyScrollView.leadingAnchor.constraint(equalTo: axisScrollView.trailingAnchor, constant: AppSpacing.micro),
                bodyScrollView.topAnchor.constraint(equalTo: headerScrollView.bottomAnchor, constant: AppSpacing.micro),
                bodyScrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
                bodyScrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
            ])

            embed(host: cornerHost, in: cornerContainer)
            embed(host: headerHost, in: headerScrollView, pinToContentGuide: true)
            embed(host: axisHost, in: axisScrollView, pinToContentGuide: true)
            embed(host: bodyHost, in: bodyScrollView, pinToContentGuide: true)

            headerHost.view.heightAnchor.constraint(equalTo: headerScrollView.frameLayoutGuide.heightAnchor).isActive = true
            axisHost.view.widthAnchor.constraint(equalTo: axisScrollView.frameLayoutGuide.widthAnchor).isActive = true

            rootView.bringSubviewToFront(bodyScrollView)
            rootView.bringSubviewToFront(headerScrollView)
            rootView.bringSubviewToFront(axisScrollView)
            rootView.bringSubviewToFront(cornerContainer)

            return rootView
        }

        func updateContent() {
            cornerHost.rootView = parent.corner
            headerHost.rootView = parent.header
            axisHost.rootView = parent.axis
            bodyHost.rootView = parent.gridBody
            let hosts: [UIViewController] = [cornerHost, headerHost, axisHost, bodyHost]
            hosts.forEach { host in
                host.view.invalidateIntrinsicContentSize()
                host.view.setNeedsLayout()
            }
        }

        func scheduleLayoutUpdate() {
            guard !isDismantled else { return }
            guard !layoutUpdateScheduled else { return }
            layoutUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !self.isDismantled else { return }
                self.layoutUpdateScheduled = false
                self.updateLayout()
            }
        }

        func updateLayout() {
            let signature = LayoutSignature(parent: parent)
            let didChangeLayout = signature != lastLayoutSignature
            lastLayoutSignature = signature

            cornerWidthConstraint?.constant = parent.axisWidth
            cornerHeightConstraint?.constant = parent.headerHeight
            headerHeightConstraint?.constant = parent.headerHeight
            axisWidthConstraint?.constant = parent.axisWidth
            bodyScrollView.alwaysBounceVertical = parent.allowsVerticalScroll
            bodyScrollView.isScrollEnabled = true

            guard hasStableContainerBounds else {
                rootView.setNeedsLayout()
                scheduleDeferredScrollRetry()
                return
            }

            UIView.performWithoutAnimation {
                rootView.layoutIfNeeded()
            }
            rootView.bringSubviewToFront(bodyScrollView)
            rootView.bringSubviewToFront(headerScrollView)
            rootView.bringSubviewToFront(axisScrollView)
            rootView.bringSubviewToFront(cornerContainer)

            if rootView.accessibilityIdentifier != parent.containerID {
                rootView.accessibilityIdentifier = parent.containerID
                hasAppliedInitialScrollRequest = false
                hasReportedInteractiveLayout = false
                pendingLayoutRealignmentWeek = nil
                pendingLayoutRealignmentPasses = 0
                headerScrollView.setContentOffset(.zero, animated: false)
                axisScrollView.setContentOffset(.zero, animated: false)
                bodyScrollView.setContentOffset(.zero, animated: false)
            } else if didChangeLayout {
                queueLayoutRealignment()
                scheduleDeferredScrollRetry()
            }

            clampBodyOffsetIfNeeded()
            if !parent.allowsVerticalScroll && bodyScrollView.contentOffset.y != 0 {
                bodyScrollView.setContentOffset(CGPoint(x: bodyScrollView.contentOffset.x, y: 0), animated: false)
            }

            guard canApplyScrollRequest else {
                syncFromBody()
                scheduleDeferredScrollRetry()
                return
            }

            reportFirstInteractiveLayoutIfNeeded()

            if let targetWeek = parent.scrollToWeek {
                pendingLayoutRealignmentWeek = nil
                pendingLayoutRealignmentPasses = 0
                let targetOffset = CGPoint(
                    x: xOffset(for: targetWeek),
                    y: clampedYOffset(bodyScrollView.contentOffset.y)
                )
                let shouldAnimateScroll = hasAppliedInitialScrollRequest

                if bodyScrollView.contentOffset == targetOffset {
                    isAnimatingToTarget = false
                } else {
                    isAnimatingToTarget = shouldAnimateScroll
                    bodyScrollView.setContentOffset(targetOffset, animated: shouldAnimateScroll)
                }
                hasAppliedInitialScrollRequest = true
                syncFromBody()

                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.isDismantled else { return }
                    self.parent.currentWeek = targetWeek
                    self.parent.scrollToWeek = nil
                }
            } else {
                applyPendingLayoutRealignmentIfNeeded()
                syncFromBody()
            }
            updateAwayFromCurrentWeek()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isDismantled else { return }
            guard scrollView === bodyScrollView else { return }
            if !parent.allowsVerticalScroll && scrollView.contentOffset.y != 0 {
                scrollView.contentOffset.y = 0
            }
            syncFromBody()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            guard !isDismantled else { return }
            guard scrollView === bodyScrollView else { return }
            isAnimatingToTarget = false
            dragStartWeek = week(for: scrollView.contentOffset.x)
        }

        func scrollViewWillEndDragging(
            _ scrollView: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            guard !isDismantled else { return }
            guard scrollView === bodyScrollView else { return }
            guard parent.weekStride > 0 else { return }

            let targetWeek: Int
            if abs(velocity.x) > 0.18 {
                targetWeek = clampedWeek(dragStartWeek + (velocity.x > 0 ? 1 : -1))
            } else {
                targetWeek = week(for: targetContentOffset.pointee.x)
            }

            targetContentOffset.pointee = CGPoint(
                x: xOffset(for: targetWeek),
                y: clampedYOffset(targetContentOffset.pointee.y)
            )
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !isDismantled else { return }
            guard scrollView === bodyScrollView else { return }
            if !decelerate {
                updateCurrentWeek()
                updateAwayFromCurrentWeek()
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            guard !isDismantled else { return }
            guard scrollView === bodyScrollView else { return }
            updateCurrentWeek()
            updateAwayFromCurrentWeek()
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            guard !isDismantled else { return }
            guard scrollView === bodyScrollView else { return }
            isAnimatingToTarget = false
            updateCurrentWeek()
            updateAwayFromCurrentWeek()
        }

        private func updateCurrentWeek() {
            guard !isDismantled else { return }
            let visibleWeek = week(for: bodyScrollView.contentOffset.x)
            if visibleWeek != parent.currentWeek {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.isDismantled else { return }
                    self.parent.currentWeek = visibleWeek
                }
            }
        }

        private func syncFromBody() {
            headerScrollView.setContentOffset(
                CGPoint(x: bodyScrollView.contentOffset.x, y: 0),
                animated: false
            )
            axisScrollView.setContentOffset(
                CGPoint(x: 0, y: clampedAxisYOffset(bodyScrollView.contentOffset.y)),
                animated: false
            )
        }

        private func queueLayoutRealignment() {
            pendingLayoutRealignmentWeek = clampedWeek(parent.currentWeek)
            pendingLayoutRealignmentPasses = 4
        }

        private func applyPendingLayoutRealignmentIfNeeded() {
            guard let week = pendingLayoutRealignmentWeek else { return }
            preserveWeekAfterLayoutChange(week)
            pendingLayoutRealignmentPasses -= 1
            if pendingLayoutRealignmentPasses > 0 {
                scheduleDeferredScrollRetry()
            } else {
                pendingLayoutRealignmentWeek = nil
            }
        }

        private func preserveWeekAfterLayoutChange(_ week: Int) {
            UIView.performWithoutAnimation {
                rootView.layoutIfNeeded()
                headerScrollView.layoutIfNeeded()
                axisScrollView.layoutIfNeeded()
                bodyScrollView.layoutIfNeeded()
            }
            let targetOffset = CGPoint(
                x: xOffset(for: week),
                y: clampedYOffset(bodyScrollView.contentOffset.y)
            )
            if bodyScrollView.contentOffset != targetOffset {
                bodyScrollView.setContentOffset(targetOffset, animated: false)
            }
            syncFromBody()
        }

        private var canApplyScrollRequest: Bool {
            bodyScrollView.bounds.width > 0
                && bodyScrollView.bounds.height > 0
                && bodyScrollView.contentSize.width > 0
                && bodyScrollView.contentSize.height > 0
        }

        private var hasStableContainerBounds: Bool {
            rootView.bounds.width > 0
                && rootView.bounds.height > parent.headerHeight + AppSpacing.micro
        }

        private func scheduleDeferredScrollRetry() {
            guard !isDismantled else { return }
            guard rootView.window != nil else { return } // Stop polling if view is offscreen
            guard !deferredScrollRetryScheduled else { return }
            deferredScrollRetryScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16)) { [weak self] in
                guard let self else { return }
                guard !self.isDismantled else { return }
                // Also double check window before continuing the loop
                guard self.rootView.window != nil else {
                    self.deferredScrollRetryScheduled = false
                    return
                }
                self.deferredScrollRetryScheduled = false
                self.rootView.setNeedsLayout()
                self.scheduleLayoutUpdate()
            }
        }

        private func reportFirstInteractiveLayoutIfNeeded() {
            guard !isDismantled else { return }
            guard !hasReportedInteractiveLayout else { return }
            hasReportedInteractiveLayout = true
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isDismantled else { return }
                self.parent.onFirstInteractiveLayout()
            }
        }

        private func clampBodyOffsetIfNeeded() {
            let maxX = max(bodyScrollView.contentSize.width - bodyScrollView.bounds.width, 0)
            let clampedOffset = CGPoint(
                x: min(max(bodyScrollView.contentOffset.x, 0), maxX),
                y: clampedYOffset(bodyScrollView.contentOffset.y)
            )
            if bodyScrollView.contentOffset != clampedOffset {
                bodyScrollView.setContentOffset(clampedOffset, animated: false)
            }
        }

        private func clampedYOffset(_ proposedY: CGFloat) -> CGFloat {
            guard parent.allowsVerticalScroll else { return 0 }
            let maxY = max(bodyScrollView.contentSize.height - bodyScrollView.bounds.height, 0)
            return min(max(proposedY, 0), maxY)
        }

        private func clampedAxisYOffset(_ proposedY: CGFloat) -> CGFloat {
            guard parent.allowsVerticalScroll else { return 0 }
            let maxY = max(axisScrollView.contentSize.height - axisScrollView.bounds.height, 0)
            return min(max(proposedY, 0), maxY)
        }

        private func xOffset(for week: Int) -> CGFloat {
            let index = CGFloat(max(min(week, parent.totalWeeks), 1) - 1)
            let maxX = max(bodyScrollView.contentSize.width - bodyScrollView.bounds.width, 0)
            return min(index * parent.weekStride, maxX)
        }

        private func clampedWeek(_ week: Int) -> Int {
            min(max(week, 1), parent.totalWeeks)
        }

        private func updateAwayFromCurrentWeek() {
            guard !isAnimatingToTarget else { return }
            let visibleWeek = week(for: bodyScrollView.contentOffset.x)
            reportAwayFromCurrentWeek(visibleWeek != SemesterConfig.currentWeek())
        }

        private func reportAwayFromCurrentWeek(_ isAway: Bool) {
            guard !isDismantled else { return }
            guard isAway != lastReportedAwayFromCurrentWeek else { return }
            lastReportedAwayFromCurrentWeek = isAway
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isDismantled else { return }
                self.parent.isAwayFromCurrentWeek = isAway
            }
        }

        private func week(for offsetX: CGFloat) -> Int {
            guard parent.weekStride > 0 else { return 1 }
            let centerX = offsetX + bodyScrollView.bounds.width * 0.5
            let rawIndex = Int(centerX / parent.weekStride)
            return min(max(rawIndex + 1, 1), parent.totalWeeks)
        }

        private func embed(host: UIHostingController<some View>, in container: UIView, pinToContentGuide: Bool = false) {
            host.view.translatesAutoresizingMaskIntoConstraints = false
            host.view.backgroundColor = .clear
            container.addSubview(host.view)

            if let scrollView = container as? UIScrollView, pinToContentGuide {
                NSLayoutConstraint.activate([
                    host.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                    host.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                    host.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                    host.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor)
                ])
            } else {
                NSLayoutConstraint.activate([
                    host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    host.view.topAnchor.constraint(equalTo: container.topAnchor),
                    host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
                ])
            }
        }

        private struct LayoutSignature: Equatable {
            let axisWidth: CGFloat
            let headerHeight: CGFloat
            let weekStride: CGFloat
            let dayColumnWidth: CGFloat
            let rowHeight: CGFloat
            let rowSpacing: CGFloat
            let allowsVerticalScroll: Bool

            init(parent: TimetableScrollContainer) {
                axisWidth = parent.axisWidth
                headerHeight = parent.headerHeight
                weekStride = parent.weekStride
                dayColumnWidth = parent.dayColumnWidth
                rowHeight = parent.rowHeight
                rowSpacing = parent.rowSpacing
                allowsVerticalScroll = parent.allowsVerticalScroll
            }
        }
    }
}

final class TimetableScrollRootView: UIView {
    var onBoundsChange: (() -> Void)?
    private var lastBoundsSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastBoundsSize else { return }
        lastBoundsSize = bounds.size
        onBoundsChange?()
    }
}
