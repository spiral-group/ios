//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 413): Spiral's own photo and video viewer. It fades in over the chat, and a
// drag down on the page closes it, the photo following the finger as the black fades. The pages are a paging
// collection view of UIKit cells whose photos are decoded off the main thread ahead of the swipe; the bars float
// over them in their own SwiftUI hosts.
//

import Combine
import SwiftUI

final class MediaViewerController: UIViewController, StatusBarHidingCover {
    /// Called once the viewer has left the screen, however it was closed.
    var onDismissed: () -> Void = { }

    private let context: TimelineMediaPreviewViewModel.Context
    /// The black behind the media, which fades as the viewer opens, closes, or is dragged down.
    private let backdrop = UIView()
    private let layout = UICollectionViewFlowLayout()
    private let collectionView: UICollectionView
    private var pagesDataSource: UICollectionViewDiffableDataSource<Int, TimelineMediaPreviewPage>?
    private var topChrome: UIHostingController<MediaViewerTopBar>?
    private let bottomChrome: UIHostingController<MediaViewerBottomChrome>
    private let sheets: UIHostingController<MediaViewerSheets>
    private let imageLoader = MediaViewerImageLoader()
    private let audioSession = MediaViewerAudioSession()
    /// The system player, made when the first video or audio page settles. Its video is let go, and its view taken
    /// out, whenever the pager leaves that page; only the empty controller is kept, which is cheaper than a new one.
    private var player: MediaViewerPlayer?
    private var playbacks: [MediaPreviewItemID: MediaViewerPlayback] = [:]
    private var cancellables: Set<AnyCancellable> = []

    /// The pages in the timeline's order, oldest first. They only change while the pager is at rest.
    private var pages: [TimelineMediaPreviewPage] = []
    /// The same pages as the collection view lays them out, left to right: reversed in a right-to-left language, so the
    /// next media comes in from the left. The collection view itself is always left to right, because a flow layout
    /// mirrors its items in right-to-left but not its content offset, and the pager would show one media while the
    /// count, Delete and Forward act on another.
    private var pagesOnScreen: [TimelineMediaPreviewPage] = []
    /// The page the pager last came to rest on.
    private var settledPage: TimelineMediaPreviewPage
    /// The media the user came from onto a loading page, to land next to once more media loads.
    private var anchorID: MediaPreviewItemID?
    private var needsPagesUpdate = false
    private var isChromeHidden = false
    /// Set once, when the viewer starts closing by any path, so it never closes twice.
    private var isClosing = false
    private var isDraggingToClose = false
    /// The screen behind, hidden from VoiceOver while the viewer covers it.
    private weak var coveredView: UIView?
    /// Whether the viewer has handed back what it took (the player, the audio, VoiceOver behind) and said it left.
    private var hasLeft = false
    private let dismissPan = UIPanGestureRecognizer()

    private var dataSource: TimelineMediaPreviewDataSource {
        context.viewState.dataSource
    }

    private var pageWidth: CGFloat {
        collectionView.bounds.width
    }

    private var isPagerMoving: Bool {
        collectionView.isTracking || collectionView.isDragging || collectionView.isDecelerating
    }

    private var settledCell: MediaViewerPageCell? {
        cell(for: settledPage)
    }

    /// The status bar goes with the bars, and comes back while a drag down shows the chat behind.
    override var prefersStatusBarHidden: Bool {
        isChromeHidden && !isDraggingToClose && !isClosing
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    init(context: TimelineMediaPreviewViewModel.Context) {
        self.context = context
        settledPage = context.viewState.dataSource.currentPage
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        bottomChrome = UIHostingController(rootView: MediaViewerBottomChrome(context: context))
        sheets = UIHostingController(rootView: MediaViewerSheets(context: context))
        super.init(nibName: nil, bundle: nil)

        topChrome = UIHostingController(rootView: MediaViewerTopBar(context: context) { [weak self] in self?.close() })
        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Closes the viewer: the one way out, for ✕, a drag down and the timeline taking it away. Runs once.
    func close() {
        guard !isClosing else { return }
        MediaViewerFrameProbe.begin(.close)
        finishClosing(pageTransform: settledCell?.contentView.transform.scaledBy(x: 0.94, y: 0.94) ?? .identity,
                      gesture: .close)
    }

    /// AGENT-PLATFORM (1.0.2, DEBT "a call under the sheet"): goes at once, with no fade, for a call screen or the
    /// in-app ring coming up: a ring's cover can't present while the viewer is still up. Runs once, like `close()`.
    func closeAtOnce() {
        guard !isClosing else { return }
        isClosing = true
        view.isUserInteractionEnabled = false
        releasePlayer()
        audioSession.restore()
        if let presenter = presentingViewController {
            presenter.dismiss(animated: false) { self.didLeave() }
        } else {
            didLeave()
        }
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
        backdrop.backgroundColor = .black
        backdrop.frame = view.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backdrop)

        setUpCollectionView()
        setUpChrome()
        subscribe()
        updatePages()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Each page is the screen plus the strip that separates it from the next one, off the trailing edge.
        let frame = CGRect(x: 0, y: 0, width: view.bounds.width + MediaViewerPageCell.pageSpacing, height: view.bounds.height)
        if collectionView.frame != frame {
            collectionView.frame = frame
            layout.itemSize = frame.size
            layout.invalidateLayout()
            collectionView.layoutIfNeeded()
            scrollToSettledPage()
        }
        imageLoader.screenPixels = max(view.bounds.width, view.bounds.height) * traitCollection.displayScale
        updatePlayerSafeArea()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard isBeingPresented else { return }
        // The chat stays behind, for the drag down to reveal it; VoiceOver mustn't wander into it meanwhile.
        coveredView = presentingViewController?.view
        coveredView?.accessibilityElementsHidden = true
        view.layoutIfNeeded()
        backdrop.alpha = 0
        collectionView.alpha = 0
        collectionView.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        setChrome(visible: false)
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.backdrop.alpha = 1
            self.collectionView.alpha = 1
            self.collectionView.transform = .identity
            self.setChrome(visible: !self.isChromeHidden)
        } completion: { _ in
            MediaViewerFrameProbe.end(.open)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updatePlayback(isNewSettle: true)
        prefetch()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Taken off the screen without closing itself, say with the chat behind it: still give everything back.
        if isBeingDismissed || presentingViewController == nil {
            didLeave()
        }
    }

    override func accessibilityPerformEscape() -> Bool {
        close()
        return true
    }

    // MARK: Set-up

    private func setUpCollectionView() {
        collectionView.backgroundColor = .clear
        collectionView.semanticContentAttribute = .forceLeftToRight
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.scrollsToTop = false
        collectionView.allowsSelection = false
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        view.addSubview(collectionView)
        MediaViewerFrameProbe.track(pageSwipes: collectionView.panGestureRecognizer)

        let registration = UICollectionView.CellRegistration<MediaViewerPageCell, TimelineMediaPreviewPage> { [weak self] cell, _, page in
            self?.configure(cell, page: page)
        }
        pagesDataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, page in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: page)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleChrome))
        tap.delegate = self
        collectionView.addGestureRecognizer(tap)

        // A drag down closes; sideways the pager takes it straight away, as this pan fails at once.
        dismissPan.addTarget(self, action: #selector(handleDismissPan(_:)))
        dismissPan.maximumNumberOfTouches = 1 // A pinch that drifts down is a zoom, not a close.
        dismissPan.delegate = self
        view.addGestureRecognizer(dismissPan)
        collectionView.panGestureRecognizer.require(toFail: dismissPan)
    }

    /// The bars sit in hosts sized to their content, so the pages between them take every touch.
    private func setUpChrome() {
        guard let topChrome else { return }

        for host in [topChrome, bottomChrome, sheets] as [UIViewController] {
            addChild(host)
            host.view.backgroundColor = .clear
            host.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }
        topChrome.sizingOptions = .intrinsicContentSize
        bottomChrome.sizingOptions = .intrinsicContentSize

        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            topChrome.view.topAnchor.constraint(equalTo: safeArea.topAnchor),
            topChrome.view.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            topChrome.view.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),

            bottomChrome.view.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
            bottomChrome.view.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            bottomChrome.view.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),

            sheets.view.topAnchor.constraint(equalTo: view.topAnchor),
            sheets.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheets.view.widthAnchor.constraint(equalToConstant: 0),
            sheets.view.heightAnchor.constraint(equalToConstant: 0)
        ])
    }

    private func subscribe() {
        dataSource.previewItemsPaginationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updatePages() }
            .store(in: &cancellables)

        context.viewState.pagerDriver
            .sink { [weak self] page in self?.jump(to: page) }
            .store(in: &cancellables)

        context.viewState.mediaDidLoad
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in self?.mediaDidLoad(id) }
            .store(in: &cancellables)

        // The view state is changed after it says it will change, so look on the next turn of the run loop.
        context.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)
    }

    // MARK: Pages

    /// Brings the pages in line with the loaded media without moving the page on screen: media arriving at either
    /// end slides in off screen, and a loading page gives way to the media that arrived next to it.
    private func updatePages() {
        guard !isPagerMoving else {
            needsPagesUpdate = true
            return
        }
        needsPagesUpdate = false

        // A sent local echo now goes by its event ID: follow it, so its page stays and its video keeps its state.
        if case let .media(id) = settledPage {
            settledPage = .media(dataSource.currentID(for: id))
        }
        anchorID = anchorID.map(dataSource.currentID)
        playbacks = Dictionary(playbacks.map { (dataSource.currentID(for: $0.key), $0.value) }) { _, newer in newer }

        let newPages = dataSource.pages.uniqued()
        guard newPages != pages, !newPages.isEmpty, let pagesDataSource else { return }

        let previousIndex = pages.firstIndex(of: settledPage) ?? 0
        let keptPage = TimelineMediaPreviewDataSource.page(keeping: settledPage, in: newPages, anchor: anchorID)
            ?? newPages[min(previousIndex, newPages.count - 1)]
        pages = newPages
        pagesOnScreen = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? newPages.reversed() : newPages

        var snapshot = NSDiffableDataSourceSnapshot<Int, TimelineMediaPreviewPage>()
        snapshot.appendSections([0])
        snapshot.appendItems(pagesOnScreen)
        pagesDataSource.apply(snapshot, animatingDifferences: false)

        if keptPage != settledPage {
            settle(on: keptPage)
        }
        scrollToSettledPage()
    }

    /// Puts the settled page on screen in the same layout pass, so the user never sees the pages shift.
    private func scrollToSettledPage() {
        guard pageWidth > 0, let index = pagesOnScreen.firstIndex(of: settledPage) else { return }
        collectionView.layoutIfNeeded()
        collectionView.contentOffset = CGPoint(x: CGFloat(index) * pageWidth, y: 0)
    }

    /// A tapped thumbnail: straight there, without passing every page on the way.
    private func jump(to page: TimelineMediaPreviewPage) {
        guard page != settledPage, pages.contains(page) else { return }
        settle(on: page)
        scrollToSettledPage()
        updatePlayback(isNewSettle: true)
    }

    private func pagerDidSettle() {
        guard pageWidth > 0 else { return }
        let index = Int((collectionView.contentOffset.x / pageWidth).rounded())
        guard pagesOnScreen.indices.contains(index) else { return }
        let page = pagesOnScreen[index]

        let isNewSettle = page != settledPage
        settle(on: page)
        updatePlayback(isNewSettle: isNewSettle)
        if needsPagesUpdate {
            updatePages()
        }
    }

    private func settle(on page: TimelineMediaPreviewPage) {
        if case let .media(id) = page {
            anchorID = id
        }
        guard page != settledPage else { return }
        settledPage = page
        context.send(viewAction: .pageChanged(page))

        // A photo zoomed in on a page left behind is whole again when the user comes back.
        for case let cell as MediaViewerPageCell in collectionView.visibleCells where cell.page != page {
            cell.zoomOut()
        }
        prefetch()
    }

    /// Downloads and decodes the photos two pages either way, so a swipe finds them ready.
    private func prefetch() {
        guard let index = pages.firstIndex(of: settledPage) else { return }
        let neighbours = TimelineMediaPreviewDataSource.neighbourIndices(around: index, count: pages.count).map { pages[$0] }
        context.send(viewAction: .prefetch(neighbours))

        var urls: Set<URL> = []
        for page in [settledPage] + neighbours {
            guard case let .media(id) = page, let media = dataSource.media(for: id), media.kind == .image, let url = media.fileURL else {
                continue
            }
            urls.insert(url)
            Task { [imageLoader] in _ = await imageLoader.image(for: url, resolution: .screen) }
        }
        imageLoader.keepOnly(urls)
    }

    private func mediaDidLoad(_ id: MediaPreviewItemID) {
        if let cell = cell(for: .media(id)) {
            configure(cell, page: .media(id))
        }
        // A file arriving, the settled page's or a neighbour's, only ever starts a video that is waiting for it.
        updatePlayback(isNewSettle: false)
        prefetch()
    }

    /// Every visible page and the bars, in line with the view state.
    private func refresh() {
        for case let cell as MediaViewerPageCell in collectionView.visibleCells {
            if let page = cell.page {
                configure(cell, page: page)
            }
        }

        let isChromeHidden = context.viewState.bindings.isChromeHidden
        guard isChromeHidden != self.isChromeHidden else { return }
        self.isChromeHidden = isChromeHidden
        UIView.animate(withDuration: 0.2) {
            self.setChrome(visible: !isChromeHidden)
            self.setNeedsStatusBarAppearanceUpdateInScene()
        }
    }

    private func configure(_ cell: MediaViewerPageCell, page: TimelineMediaPreviewPage) {
        var media: TimelineMediaPreviewItem.Media?
        if case let .media(id) = page {
            media = dataSource.media(for: id)
        }
        var scanState: TimelineMediaPreviewItem.Scan.State?
        if case let .contentScan(scan) = context.viewState.currentItem, scan.media === media {
            scanState = scan.state
        }

        cell.configure(.init(page: page,
                             media: media,
                             scanState: scanState,
                             playback: media.flatMap { playbacks[$0.id] },
                             mediaProvider: context.mediaProvider,
                             imageLoader: imageLoader,
                             openFile: { [weak self] in
                                 guard let media else { return }
                                 self?.context.send(viewAction: .openFile(media))
                             },
                             play: { [weak self] in
                                 guard let media else { return }
                                 self?.playTapped(media)
                             },
                             zoomStarted: { [weak self] in
                                 // As in Photos, zooming in puts the photo alone on black.
                                 guard let self, !context.viewState.bindings.isChromeHidden else { return }
                                 context.send(viewAction: .toggleChrome)
                             }))

        // A cell reused for another page gives the player back.
        if let player, player.controller.viewIfLoaded?.superview === cell.playerContainer,
           page != player.mediaID.map(TimelineMediaPreviewPage.media) {
            releasePlayer()
        }
    }

    private func cell(for page: TimelineMediaPreviewPage) -> MediaViewerPageCell? {
        guard let index = pagesOnScreen.firstIndex(of: page) else { return nil }
        return collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? MediaViewerPageCell
    }

    // MARK: Video

    /// Plays the settled page's video when the pager comes to rest on it (`isNewSettle`), or when its file arrives
    /// while it waits; pauses every other one. Anything else, a neighbour's download say, leaves playback alone, so a
    /// video the user paused or watched to the end stays that way.
    private func updatePlayback(isNewSettle: Bool) {
        if isNewSettle {
            for (id, var playback) in playbacks where settledPage != .media(id) {
                _ = playback.pageSettled(isThisPage: false)
                playbacks[id] = playback
            }
        }

        guard case let .media(id) = settledPage, let media = dataSource.media(for: id), media.kind == .video || media.kind == .audio else {
            if isNewSettle {
                releasePlayer()
            }
            return
        }
        if let player, player.mediaID != nil, player.mediaID != id {
            releasePlayer()
        }
        let isFirstVisit = playbacks[id] == nil
        var playback = playbacks[id] ?? MediaViewerPlayback(autoplays: media.kind == .video, hasFile: false)
        let command = playback.settledPageUpdated(isNewSettle: isNewSettle || isFirstVisit, hasFile: media.fileURL != nil)
        playbacks[id] = playback
        if let url = media.fileURL {
            attachPlayer(url, for: id).perform(command)
        }
        if let cell = cell(for: settledPage) {
            configure(cell, page: settledPage)
        }
    }

    private func playTapped(_ media: TimelineMediaPreviewItem.Media) {
        guard let url = media.fileURL, settledPage == .media(media.id) else { return }
        var playback = playbacks[media.id] ?? MediaViewerPlayback(autoplays: media.kind == .video, hasFile: true)
        let command = playback.playTapped()
        playbacks[media.id] = playback
        attachPlayer(url, for: media.id).perform(command)
        if let cell = cell(for: .media(media.id)) {
            configure(cell, page: .media(media.id))
        }
    }

    /// The player for the page of `id`, made now if there is none, with its view in that page.
    private func attachPlayer(_ url: URL, for id: MediaPreviewItemID) -> MediaViewerPlayer {
        let player = player ?? makePlayer()
        player.load(url, for: id)
        if let cell = cell(for: .media(id)), let playerView = player.controller.view, playerView.superview !== cell.playerContainer {
            addChild(player.controller)
            playerView.frame = cell.playerContainer.bounds
            playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            cell.playerContainer.addSubview(playerView)
            player.controller.didMove(toParent: self)
        }
        updatePlayerSafeArea()
        return player
    }

    private func makePlayer() -> MediaViewerPlayer {
        let player = MediaViewerPlayer(audioSession: audioSession)
        player.onEvent = { [weak self] id, event in
            guard let self else { return }
            switch event {
            case .played: playbacks[id]?.didPlay()
            case .paused: playbacks[id]?.didPause()
            case .ended: playbacks[id]?.didEnd()
            case .readyForDisplay: break
            }
            if let cell = cell(for: .media(id)) {
                configure(cell, page: .media(id))
            }
        }
        self.player = player
        return player
    }

    /// Stops the player and lets its video go, so nothing of it is left on pages that aren't showing it.
    private func releasePlayer() {
        guard let player else { return }
        player.unload()
        guard player.controller.parent != nil else { return }
        player.controller.willMove(toParent: nil)
        player.controller.view.removeFromSuperview()
        player.controller.removeFromParent()
    }

    /// Keeps the player's controls between the bars.
    private func updatePlayerSafeArea() {
        guard let topChrome, let player, let mediaID = player.mediaID, settledPage == .media(mediaID) else { return }
        let safeArea = view.safeAreaInsets
        let top = max(0, topChrome.view.frame.maxY - safeArea.top)
        let bottom = max(0, view.bounds.maxY - safeArea.bottom - bottomChrome.view.frame.minY)
        let insets = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        if player.controller.additionalSafeAreaInsets != insets {
            player.controller.additionalSafeAreaInsets = insets
        }
    }

    // MARK: Chrome

    @objc private func toggleChrome() {
        context.send(viewAction: .toggleChrome)
    }

    private func setChrome(visible: Bool) {
        for host in [topChrome, bottomChrome] as [UIViewController?] {
            host?.view.alpha = visible ? 1 : 0
            host?.view.isUserInteractionEnabled = visible
        }
    }

    // MARK: Closing

    /// The page follows a drag down, shrinking a little as the black fades; let go far or fast enough and it closes.
    @objc private func handleDismissPan(_ recognizer: UIPanGestureRecognizer) {
        guard !isClosing, let pageView = settledCell?.contentView else { return }
        let translation = recognizer.translation(in: view)
        let drag = MediaViewerDrag(translation: translation, height: view.bounds.height)

        switch recognizer.state {
        case .began:
            MediaViewerFrameProbe.begin(.swipeDown)
            isDraggingToClose = true
            UIView.animate(withDuration: 0.2) { self.setNeedsStatusBarAppearanceUpdateInScene() }
        case .changed:
            pageView.transform = drag.pageTransform
            backdrop.alpha = 1 - drag.progress
            setChrome(visible: false)
        case .ended, .cancelled, .failed:
            if recognizer.state == .ended, drag.closes(velocity: recognizer.velocity(in: view).y) {
                finishClosing(pageTransform: drag.pageTransform.translatedBy(x: 0, y: view.bounds.height / 2), gesture: .swipeDown)
            } else {
                isDraggingToClose = false
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                               options: [.allowUserInteraction]) {
                    pageView.transform = .identity
                    self.backdrop.alpha = 1
                    self.setChrome(visible: !self.isChromeHidden)
                    self.setNeedsStatusBarAppearanceUpdateInScene()
                } completion: { _ in
                    MediaViewerFrameProbe.end(.swipeDown)
                }
            }
        default:
            break
        }
    }

    /// The one way the viewer leaves: the page and the black fade in 0.25 s, then it goes without UIKit animating.
    private func finishClosing(pageTransform: CGAffineTransform, gesture: MediaViewerFrameProbe.Gesture) {
        guard !isClosing else { return }
        isClosing = true
        view.isUserInteractionEnabled = false
        releasePlayer()
        audioSession.restore()
        let pageView = settledCell?.contentView

        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            pageView?.transform = pageTransform
            pageView?.alpha = 0
            self.backdrop.alpha = 0
            self.setChrome(visible: false)
            self.setNeedsStatusBarAppearanceUpdateInScene()
        } completion: { _ in
            MediaViewerFrameProbe.end(gesture)
            if let presenter = self.presentingViewController {
                presenter.dismiss(animated: false) { self.didLeave() }
            } else {
                self.didLeave()
            }
        }
    }

    /// Hands back what the viewer took and reports it gone, once, whether it closed itself or something else took
    /// it off the screen.
    private func didLeave() {
        guard !hasLeft else { return }
        hasLeft = true
        releasePlayer()
        audioSession.restore()
        coveredView?.accessibilityElementsHidden = false
        coveredView?.window.map { window in
            window.windowScene?.windows.forEach { $0.rootViewController?.setNeedsStatusBarAppearanceUpdate() }
        }
        onDismissed()
    }
}

/// Where a drag down has taken the page, and whether letting go there closes the viewer.
struct MediaViewerDrag {
    /// How far down, in points, closes the viewer however slowly the finger lets go.
    static let closingDistance: CGFloat = 120
    /// How fast down, in points per second, closes it however short the drag.
    static let closingSpeed: CGFloat = 900

    let translation: CGPoint
    let height: CGFloat

    /// How far the drag has gone towards closing, from 0 to 1, over half the screen.
    var progress: CGFloat {
        guard height > 0 else { return 0 }
        return min(1, max(0, translation.y) / (height / 2))
    }

    /// The page follows the finger and shrinks to 85 % at half the screen.
    var pageTransform: CGAffineTransform {
        let scale = 1 - 0.15 * progress
        return CGAffineTransform(translationX: translation.x, y: max(0, translation.y)).scaledBy(x: scale, y: scale)
    }

    func closes(velocity: CGFloat) -> Bool {
        translation.y > Self.closingDistance || (velocity > Self.closingSpeed && translation.y > 0)
    }
}

// MARK: - UICollectionViewDelegate

extension MediaViewerController: UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        pagerDidSettle()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            pagerDidSettle()
        }
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let pages = indexPaths.compactMap { pagesDataSource?.itemIdentifier(for: $0) }
        context.send(viewAction: .prefetch(pages))
    }
}

// MARK: - UIGestureRecognizerDelegate

extension MediaViewerController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer === dismissPan else { return true }
        // Only a drag mostly downwards closes, never while a photo is zoomed in or the pages are still sliding.
        let velocity = dismissPan.velocity(in: view)
        guard velocity.y > abs(velocity.x), !isClosing, settledCell?.isZoomedIn != true,
              !collectionView.isDragging, !collectionView.isDecelerating else {
            return false
        }
        return true
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard recognizer !== dismissPan else { return dismissPanMayStart(on: touch.view) }
        // A tap on a page's own button, ▶ or Open, doesn't also toggle the bars.
        guard let touchedView = touch.view else { return true }
        return !collectionView.visibleCells.contains { ($0 as? MediaViewerPageCell)?.ownsControl(touchedView) == true }
    }
    
    /// A drag to close starts on the page: not on the bars, the strip or the caption, which scroll and take taps.
    func dismissPanMayStart(on touchedView: UIView?) -> Bool {
        guard let touchedView else { return true }
        let chrome = [topChrome?.view, bottomChrome.view].compactMap(\.self)
        return !chrome.contains { touchedView.isDescendant(of: $0) }
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // A tap also reaches the player's own controls, so both show and hide together.
        recognizer !== dismissPan
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        // A tap toggles the bars only once it can't be a photo's double tap to zoom.
        guard recognizer !== dismissPan, let otherTap = other as? UITapGestureRecognizer else { return false }
        return otherTap.numberOfTapsRequired == 2
    }
}

private extension Array where Element: Hashable {
    /// The elements in order without repeats: a page shows once even if the timeline listed its media twice.
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
