//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: the room-scoped Tool + Trigger control surface.
//
// This is the narrow slice of `AgentPlatformServiceProtocol` the
// in-room agent-tools flow actually depends on (Brief 0036 / ADR-0048):
// reading a room's active Tools, the arm-form catalog, arming and
// disabling a Tool, plus resolving the caller's agents (personal, and the
// agents of every space they own) so the flow can decide which agents are
// present / addable.
//
// Interface segregation (see the software-architecture skill): the
// `AgentToolsFlowCoordinator` and its screen ViewModels take
// `any RoomToolsServiceProtocol`, not the ~1300-LOC god-protocol, so
// their dependency surface is exactly the routes they call and
// their tests reason about nothing more.
//
// `AgentPlatformServiceProtocol` REFINES this protocol, so the concrete
// `AgentPlatformService` and the single Sourcery-generated
// `AgentPlatformServiceMock` satisfy both automatically — there is no
// second mock and no test churn. The `// sourcery: AutoMockable`
// annotation stays on `AgentPlatformServiceProtocol` only.

import AgentPlatformClient
import Foundation

@MainActor
protocol RoomToolsServiceProtocol: AnyObject {
    // MARK: - Personal agents

    /// `GET /api/v1/me/personal-agents`. Drives the Settings →
    /// "My Agents" screen. Returns the caller's live personal
    /// agents (0 or 1 in Phase 6.a, N in Phase 6.c) plus the
    /// `provisioning_status` envelope field
    /// (`ready` / `in_progress` / `idle` per R3.3.c).
    func listMyPersonalAgents() async -> Result<MyPersonalAgentsView, AgentPlatformError>

    // MARK: - Agent-Spaces directory (Brief 0037)

    /// `GET /api/v1/me/agent-spaces` — the owner's Agent-Spaces
    /// directory: their Personal space plus every company they
    /// own, Personal-first. This is the root query of the rebuilt
    /// Agents tab (artboard 0037-A), and the add-agent picker lists
    /// the agents of every space in it (re-walk R1).
    ///
    /// `provisioningStatus` mirrors the personal-agent reconcile
    /// worker: `.inProgress` while the owner's personal agent (and
    /// thus their Personal space) is still being provisioned —
    /// the screen shows a provisioning hint instead of an empty
    /// directory in that window.
    func listMyAgentSpaces() async -> Result<AgentSpacesDirectory, AgentPlatformError>

    /// `GET /api/v1/agent-spaces/{org_id}` — one space's header +
    /// its agents as rich cards (artboards 0037-B/C). 403/404 for
    /// spaces the caller doesn't own.
    func fetchAgentSpace(orgID: String) async -> Result<AgentSpaceDetail, AgentPlatformError>

    // MARK: - Unified Tool + Trigger control (Brief 0036 / ADR-0048)

    /// `GET /api/v1/rooms/:room_id/tools`. Room-wide read of the active
    /// Tools across every agent joined to the room. Own Tools carry full
    /// params/trigger/id; other owners' Tools are a safe slice (Brief 0035
    /// visibility model). Any participant may read (not owner-gated).
    /// Drives the in-chat active-tools banner + the capabilities sheet +
    /// the add-agent presence.
    func fetchRoomTools(roomID: String) async -> Result<RoomToolsView, AgentPlatformError>

    /// `GET /api/v1/agents/:id/rooms/:room_id/tools/catalog`. The typed
    /// `ToolParams` + `TriggerKind` JSON Schemas (schemars, ADR-0039) the
    /// client renders arm forms from. Owner-only (403 otherwise).
    func fetchToolsCatalog(agentID: String,
                           roomID: String) async -> Result<ToolsCatalogView, AgentPlatformError>

    /// `POST /api/v1/agents/:id/rooms/:room_id/tools`. Arms a Tool: the
    /// typed `params` (WHAT) composed with the typed `trigger` (WHEN).
    /// Routed through the three-layer gate server-side via `tool.arm`,
    /// never a repository write (ADR-0047 Principle 1). Returns the SET
    /// outcome (`applied` synchronously on the owner-bypass path).
    ///
    /// An edit passes `replacesToolID`: the backend turns that tool off in
    /// the same transaction (ADR-0088), so an edit works at the cap and an
    /// unchanged save is not a duplicate. The cap, duplicate and
    /// does-not-fire-here refusals come back as their own `RoomToolArmError`.
    func armTool(agentID: String,
                 roomID: String,
                 params: ToolParams,
                 trigger: TriggerKind,
                 replacesToolID: String?) async -> Result<ControlSetResultView, RoomToolArmError>

    /// `DELETE /api/v1/agents/:id/rooms/:room_id/tools/:tool_id`. Turns a
    /// Tool off through the gate via `tool.disable` (the owner's own
    /// tool id comes from `fetchRoomTools`).
    func disableTool(agentID: String,
                     roomID: String,
                     toolID: String) async -> Result<ControlSetResultView, AgentPlatformError>
}
