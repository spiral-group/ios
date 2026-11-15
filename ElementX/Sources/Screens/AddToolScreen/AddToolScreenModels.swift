//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359, item 12): adding a tool: its kinds, a line on each, then the form. Only what
// fires here is offered: `available_tool_kinds` says so, and `domain::tool::tool_fires_in` stays the server's.
//

import Foundation

enum AddToolScreenViewModelAction: Equatable {
    case selectKind(AgentToolKind)
}

enum AddToolListState: Equatable {
    case loading
    case loaded(text: [AgentToolKind], calls: [AgentToolKind])
    /// The catalogue couldn't be read: "couldn't check", never "nothing fires here".
    case failed
}

struct AddToolScreenViewState: BindableState {
    /// The agent the tool is for, under the title.
    let agentDisplayName: String
    var listState: AddToolListState = .loading
}

enum AddToolScreenViewAction {
    case retry
    case selectKind(AgentToolKind)
}
