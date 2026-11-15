//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
@testable import Spiral
import Testing

/// Decision 357 item 11: a failed read must not read as a room without threads.
@MainActor
struct RoomThreadListScreenViewModelTests {
    private let paginationState = CurrentValueSubject<RoomThreadListPaginationState, Never>(.idle(endReached: false))
    private let proxy = RoomThreadListServiceProxyMock(.init(items: []))
    
    init() {
        proxy.paginationStatePublisher = paginationState.asCurrentValuePublisher()
    }
    
    @Test
    func aRoomWithoutThreadsReadsItsFirstPageThenIsEmpty() async {
        proxy.paginateClosure = { [paginationState] in
            paginationState.send(.idle(endReached: true))
            return .success(())
        }
        let viewModel = makeViewModel()
        #expect(viewModel.context.viewState.content == .loading)
        
        await wait(for: viewModel) { $0.content == .empty }
        
        #expect(proxy.paginateCallsCount == 1)
    }
    
    @Test
    func aFailedReadIsNotEmptyAndDoesNotRetryByItself() async {
        proxy.paginateReturnValue = .failure(.sdkError(RoomProxyMockError.generic))
        let viewModel = makeViewModel()
        
        await wait(for: viewModel) { $0.content == .failed }
        
        // The SDK goes back to idle after a failure.
        paginationState.send(.loading)
        paginationState.send(.idle(endReached: false))
        await settle()
        
        #expect(viewModel.context.viewState.content == .failed)
        #expect(proxy.paginateCallsCount == 1)
    }
    
    @Test
    func retryReadsAgain() async {
        proxy.paginateReturnValue = .failure(.sdkError(RoomProxyMockError.generic))
        let viewModel = makeViewModel()
        await wait(for: viewModel) { $0.content == .failed }
        
        proxy.paginateClosure = { [paginationState] in
            paginationState.send(.idle(endReached: true))
            return .success(())
        }
        viewModel.context.send(viewAction: .retry)
        
        await wait(for: viewModel) { $0.content == .empty }
        #expect(proxy.paginateCallsCount == 2)
    }
    
    @Test
    func aFailedOlderPageKeepsTheListAndSaysSo() async {
        let proxy = RoomThreadListServiceProxyMock(.init(paginationState: .idle(endReached: false),
                                                         paginateResult: .failure(.sdkError(RoomProxyMockError.generic))))
        let viewModel = RoomThreadListScreenViewModel(threadListServiceProxy: proxy, mediaProvider: MediaProviderMock(.init()))
        
        viewModel.context.send(viewAction: .oldestItemDidAppear)
        await wait(for: viewModel) { $0.hasFailedToLoad }
        
        #expect(viewModel.context.viewState.content == .list)
    }
    
    @Test
    func aListIsNotReadUntilItsOldestItemShows() async {
        let proxy = RoomThreadListServiceProxyMock(.init(paginationState: .idle(endReached: false)))
        let viewModel = RoomThreadListScreenViewModel(threadListServiceProxy: proxy, mediaProvider: MediaProviderMock(.init()))
        
        await settle()
        
        #expect(viewModel.context.viewState.content == .list)
        #expect(proxy.paginateCallsCount == 0)
    }
    
    private func makeViewModel() -> RoomThreadListScreenViewModel {
        RoomThreadListScreenViewModel(threadListServiceProxy: proxy, mediaProvider: MediaProviderMock(.init()))
    }
    
    private func wait(for viewModel: RoomThreadListScreenViewModel, until condition: (RoomThreadListScreenViewState) -> Bool) async {
        for _ in 0..<200 where !condition(viewModel.context.viewState) {
            await settle()
        }
        #expect(condition(viewModel.context.viewState))
    }
    
    /// Lets the main queue's hops and the view model's tasks run.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
