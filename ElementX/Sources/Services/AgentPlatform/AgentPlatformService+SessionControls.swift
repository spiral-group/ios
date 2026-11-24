//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0054): in-call agent session controls.
//
// Implements the voice-session controls slice of
// `AgentPlatformServiceProtocol` — the REST backing for the Element
// Call widget's `window.controls.spiralBridge`. The widget never
// holds credentials; the CallScreen bridge proxies every call here
// with the session's MAS token.
//

import AgentPlatformClient
import Foundation
import OpenAPIRuntime

nonisolated extension AgentPlatformService {
    // MARK: - Session discovery

    func voiceSessionControlContexts(roomID: String) async -> Result<[VoiceSessionControlContext], VoiceControlsError> {
        await controlsCall {
            let response = try await self.client.underlying.listForOwnerHandler(.init(query: .init(limit: 50)))
            switch response {
            case .ok(let ok):
                let sessions = try ok.body.json.items
                // `starting` and `ending` joined the backend's vocabulary
                // with two-phase teardown (audit C9): `starting` is the
                // startup claim between consent and `active`, `ending` is a
                // teardown still converging. Both are sessions that EXIST —
                // omitting them made the Agent Center drop a session exactly
                // during the join window (controls flickered off on every
                // doorbell-triggered reload) and pretend a tearing-down agent
                // was already gone. The per-session controls read still
                // decides what is operable; membership in this set only
                // decides visibility.
                let live: Set = ["pending_consent", "pending_join", "starting", "active", "ending"]
                let contexts = sessions
                    .filter { $0.roomId == roomID && live.contains($0.state) }
                    .map { session in
                        // The owner listing only returns the caller's own
                        // sessions — everything here is controllable.
                        //
                        VoiceSessionControlContext(sessionID: session.id,
                                                   agentMxid: session.agentMxid,
                                                   canControl: true,
                                                   state: session.state)
                    }
                return .success(contexts)
            case .badRequest:
                return .failure(.unavailable("bad request"))
            case .unauthorized:
                return .failure(.unauthorized)
            case .internalServerError:
                return .failure(.unavailable("status 500"))
            case .undocumented(statusCode: let code, _):
                return .failure(.unavailable("status \(code)"))
            }
        }
    }

    // MARK: - Controls state + catalog

    func voiceSessionControls(sessionID: String) async -> Result<VoiceControlsState, VoiceControlsError> {
        await controlsCall {
            let response = try await self.client.underlying.getSessionControls(.init(path: .init(sessionId: sessionID)))
            switch response {
            case .ok(let ok):
                return try .success(Self.controlsState(from: ok.body.json))
            case .forbidden:
                return .failure(.unavailable("forbidden"))
            case .notFound:
                return .failure(.gone)
            case .badRequest:
                return .failure(.unavailable("status 400"))
            case .unauthorized:
                return .failure(.unauthorized)
            case .internalServerError:
                return .failure(.unavailable("status 500"))
            // A 503 says the room couldn't be read just now (transient): the reader tries again shortly.
            case .serviceUnavailable:
                return .failure(.serviceUnavailable(retryAfter: self.serviceUnavailableRetryDelay))
            case .undocumented(statusCode: let code, _):
                return .failure(.unavailable("status \(code)"))
            }
        }
    }

    /// ADR-0094 A.8: the voice-translation catalog for any signed-in user, independent of any agent.
    func voiceLanguages() async -> Result<[VoiceControlsCatalogLanguage], VoiceControlsError> {
        await controlsCall {
            let response = try await self.client.underlying.getVoiceLanguages(.init())
            switch response {
            case .ok(let ok):
                return try .success(ok.body.json.languages.map { VoiceControlsCatalogLanguage(code: $0.code, label: $0.displayName) })
            case .unauthorized:
                return .failure(.unauthorized)
            case .internalServerError:
                return .failure(.unavailable("status 500"))
            case .undocumented(statusCode: let code, _):
                return .failure(.unavailable("status \(code)"))
            }
        }
    }

    // MARK: - Writes

    /// An enabling write (ADR-0094 A.2): turning translation on, changing its language, «Продолжить».
    func setVoiceTranslation(sessionID: String,
                             params: VoiceTranslationParams,
                             revision: Int32) async -> Result<VoiceControlsState, VoiceControlsError> {
        await enablingCall {
            let body = try Components.Schemas.SetControlRequest(params: Self.translationParamsObject(params),
                                                                revision: revision,
                                                                state: "enabled")
            let response = try await self.client.underlying.putSessionControl(.init(path: .init(sessionId: sessionID,
                                                                                                control: "translation"),
                                                                                    body: .json(body)))
            return try Self.mapSetControlResponse(response, serviceUnavailableRetryDelay: self.serviceUnavailableRetryDelay)
        }
    }

    /// `SessionControlParams` `kind: translation` (A.2): exactly one of `for_language` and `pocket`.
    static func translationParamsObject(_ params: VoiceTranslationParams) throws -> OpenAPIObjectContainer {
        switch params {
        case .forLanguage(let language):
            try OpenAPIObjectContainer(unvalidatedValue: ["kind": "translation", "for_language": language])
        case .pocket(let first, let second):
            try OpenAPIObjectContainer(unvalidatedValue: ["kind": "translation", "pocket": [first, second]])
        }
    }

    func disableVoiceTranslation(sessionID: String,
                                 revision: Int32) async -> Result<VoiceControlsState, VoiceControlsError> {
        await controlsCall {
            let body = Components.Schemas.SetControlRequest(params: nil,
                                                            revision: revision,
                                                            state: "disabled")
            let response = try await self.client.underlying.putSessionControl(.init(path: .init(sessionId: sessionID,
                                                                                                control: "translation"),
                                                                                    body: .json(body)))
            return try Self.mapSetControlResponse(response, serviceUnavailableRetryDelay: self.serviceUnavailableRetryDelay)
        }
    }

    // MARK: - Brief 0055: attach / end / artifact disable

    /// One attempt: a 503 goes back to the agent center, which retries it, because the backend lets an assistant the
    /// refused attach had joined go again and the retry may need it invited back.
    func attachVoiceAgent(agentID: String,
                          roomID: String,
                          params: VoiceAttachParams) async -> Result<String, VoiceControlsError> {
        await controlsCall {
            // WYSIWYG: the sheet's toggles are the whole truth for this
            // call, so every control is sent EXPLICITLY (translation off
            // = `disabled`, not "inherit whatever Tools say").
            let translation: Components.Schemas.AttachControlWrite
            if let t = params.translation {
                translation = try .init(params: Self.translationParamsObject(t), state: "enabled")
            } else {
                translation = .init(state: "disabled")
            }
            // Conversation off is the call's own rule, not "silent": the
            // owner's own chat with the assistant still talks (decision 180).
            let body = Components.Schemas.AttachRequest(controls: .init(conversation: .init(state: params.conversation ? "enabled" : "inherit"),
                                                                        recording: .init(state: params.recording ? "enabled" : "disabled"),
                                                                        summary: .init(state: params.summary ? "enabled" : "disabled"),
                                                                        translation: translation),
                                                        leavePolicy: .callEnd,
                                                        roomId: roomID)
            let response = try await self.client.underlying.attachHandler(.init(path: .init(id: agentID),
                                                                                body: .json(body)))
            switch response {
            case .accepted(let accepted):
                return try .success(accepted.body.json.sessionId)
            case .conflict(let conflict):
                // The agent already has a session in this room: the "add"
                // gesture joins it (the panel converges on it). Any other 409
                // (not a voice agent, a read-back race) is a retry.
                let problem = try? conflict.body.applicationProblemJson
                if problem?._type == VoiceControlsError.voiceSessionActiveTypeURI, let existing = problem?.existingSessionId {
                    return .success(existing)
                }
                if problem?._type == AgentPlatformError.agentPausedTypeURI {
                    return .failure(.agentPaused)
                }
                return .failure(Self.recordingCovered(problem) ?? .conflict)
            case .badRequest:
                return .failure(.rejected("bad request"))
            case .forbidden:
                return .failure(.unavailable("forbidden"))
            case .unauthorized:
                return .failure(.unauthorized)
            case .unprocessableContent(let rejection):
                let problem = try? rejection.body.applicationProblemJson
                let detail = problem?.detail
                    ?? "the agent could not join this room — invite it first"
                // The invite-only refusal is the only 422 the caller acts on,
                // so it is identified by the backend's stable `type` URI rather
                // than by reading its prose.
                if problem?._type == VoiceControlsError.inviteRequiredTypeURI {
                    return .failure(.inviteRequired(detail))
                }
                return .failure(Self.translationRefusal(problem) ?? .rejected(detail))
            case .unsupportedMediaType:
                return .failure(.unavailable("status 415"))
            case .internalServerError:
                return .failure(.unavailable("status 500"))
            case .serviceUnavailable:
                return .failure(.serviceUnavailable(retryAfter: self.serviceUnavailableRetryDelay))
            case .undocumented(statusCode: let code, _):
                return .failure(.unavailable("status \(code)"))
            }
        }
    }

    func endVoiceSession(sessionID: String) async -> Result<Void, VoiceControlsError> {
        await controlsCall {
            let response = try await self.client.underlying.endOrPurgeHandler(.init(path: .init(sessionId: sessionID)))
            switch response {
            case .noContent, .ok:
                return .success(())
            case .forbidden:
                return .failure(.unavailable("forbidden"))
            case .unauthorized:
                return .failure(.unauthorized)
            case .notFound:
                return .failure(.gone)
            case .conflict:
                // "Purge requested while teardown is still in progress".
                // Unreachable from here — this client never passes
                // `?purge=true` — but the case appeared when the spec was
                // refreshed, having been documented on the backend since
                // April while the vendored copy predated it. Surfaced
                // honestly rather than folded into success: if it ever does
                // arrive, the session is mid-teardown and a reload will show
                // the truth.
                return .failure(.conflict)
            case .badRequest:
                return .failure(.unavailable("status 400"))
            case .internalServerError:
                return .failure(.unavailable("status 500"))
            case .undocumented(statusCode: let code, _):
                return .failure(.unavailable("status \(code)"))
            }
        }
    }

    func voiceSessionProgress(sessionID: String) async -> Result<VoiceSessionProgress, VoiceControlsError> {
        await controlsCall {
            let response = try await self.client.underlying.fetchSessionHandler(.init(path: .init(sessionId: sessionID)))
            switch response {
            case .ok(let ok):
                let session = try ok.body.json
                if let reason = session.endReason ?? (session.state == "ended" ? "" : nil) {
                    return .success(.ended(VoiceSessionEndReason(wire: reason, category: session.category)))
                }
                switch session.state {
                case "active": return .success(.active)
                case "ending": return .success(.ending)
                default: return .success(.joining)
                }
            case .notFound:
                return .failure(.gone)
            case .forbidden:
                return .failure(.unavailable("forbidden"))
            case .unauthorized:
                return .failure(.unauthorized)
            case .badRequest:
                return .failure(.unavailable("status 400"))
            case .internalServerError:
                return .failure(.unavailable("status 500"))
            case .undocumented(statusCode: let code, _):
                return .failure(.unavailable("status \(code)"))
            }
        }
    }

    func voiceJoinCheck(agentID: String, roomID: String) async -> Result<VoiceJoinCheckReason, VoiceControlsError> {
        await controlsCall {
            let response = try await self.client.underlying.joinCheckHandler(.init(path: .init(id: agentID),
                                                                                   query: .init(roomId: roomID)))
            switch response {
            case .ok(let ok):
                return try .success(VoiceJoinCheckReason(wire: ok.body.json.reason))
            case .forbidden:
                return .failure(.unavailable("forbidden"))
            case .unauthorized:
                return .failure(.unauthorized)
            case .badRequest:
                return .failure(.unavailable("status 400"))
            case .serviceUnavailable:
                return .failure(.unavailable("status 503"))
            case .internalServerError:
                return .failure(.unavailable("status 500"))
            case .undocumented(statusCode: let code, _):
                return .failure(.unavailable("status \(code)"))
            }
        }
    }

    /// Turn an on/off session control on or off mid-call. Recording and
    /// summary were disable-only until Brief 0059 (stopping a recording left
    /// no way back); every switch shares this one write.
    func setVoiceSwitch(sessionID: String,
                        control: VoiceSessionSwitch,
                        enabled: Bool,
                        revision: Int32) async -> Result<VoiceControlsState, VoiceControlsError> {
        await controlsCall {
            let body = Components.Schemas.SetControlRequest(params: nil,
                                                            revision: revision,
                                                            state: enabled ? "enabled" : "disabled")
            let response = try await self.client.underlying.putSessionControl(.init(path: .init(sessionId: sessionID,
                                                                                                control: control.rawValue),
                                                                                    body: .json(body)))
            return try Self.mapSetControlResponse(response, serviceUnavailableRetryDelay: self.serviceUnavailableRetryDelay)
        }
    }

    // MARK: - Mapping

    private static func mapSetControlResponse(_ response: Operations.PutSessionControl.Output,
                                              serviceUnavailableRetryDelay: Duration) throws -> Result<VoiceControlsState, VoiceControlsError> {
        switch response {
        case .ok(let ok):
            return try .success(controlsState(from: ok.body.json.controls))
        case .forbidden:
            return .failure(.unavailable("forbidden"))
        case .notFound:
            return .failure(.gone)
        case .conflict(let conflict):
            // A recording someone else's assistant already makes (question 404); else the stale revision, the one 409
            // a translation write has left (ADR-0094 A.2): re-read and retry.
            return .failure(recordingCovered(try? conflict.body.applicationProblemJson) ?? .conflict)
        case .gone:
            return .failure(.gone)
        case .unprocessableContent(let rejection):
            let problem = try? rejection.body.applicationProblemJson
            let detail = problem?.detail ?? "the request was rejected — reload and try again"
            return .failure(translationRefusal(problem) ?? .rejected(detail))
        case .serviceUnavailable:
            return .failure(.serviceUnavailable(retryAfter: serviceUnavailableRetryDelay))
        case .badRequest:
            return .failure(.unavailable("status 400"))
        case .unauthorized:
            return .failure(.unauthorized)
        case .unsupportedMediaType:
            return .failure(.unavailable("status 415"))
        case .internalServerError:
            return .failure(.unavailable("status 500"))
        case .undocumented(statusCode: let code, _):
            return .failure(.unavailable("status \(code)"))
        }
    }

    /// The two typed 422s of an enabling translation write (ADR-0094 A.2); nil for any other.
    private static func translationRefusal(_ problem: Components.Schemas.ProblemDetails?) -> VoiceControlsError? {
        switch problem?._type {
        case VoiceControlsError.translationPausedTypeURI:
            .translationPaused(.init(reason: .init(wire: problem?.reason), pauseUntil: problem?.pauseUntil))
        case VoiceControlsError.intentUnavailableTypeURI:
            .intentUnavailable(roomKind: problem?.roomKind ?? "unknown")
        default:
            nil
        }
    }

    /// `409 /errors/recording-covered` (question 404), by its type alone: either name may be null; nil for any other 409.
    private static func recordingCovered(_ problem: Components.Schemas.ProblemDetails?) -> VoiceControlsError? {
        guard problem?._type == VoiceControlsError.recordingCoveredTypeURI else { return nil }
        return .recordingCovered(VoiceRecordingCover(agentMxid: problem?.recordingAgent, ownerMxid: problem?.recordingOwner))
    }

    private static func controlsState(from response: Components.Schemas.SessionControlsResponse) -> VoiceControlsState {
        let view = response.effective
        let effective = VoiceControlsEffective(source: view.source,
                                               style: view.style,
                                               forLanguage: view.forLanguage,
                                               pocket: view.pocket,
                                               lanes: view.lanes.compactMap { VoiceTranslationLane(speaker: $0.speaker, input: $0.input, language: $0.language) },
                                               isStandby: view.standby,
                                               stoppedReason: view.stoppedReason.map(VoiceTranslationStopReason.init(wire:)),
                                               isSyncing: view.syncing,
                                               pause: .init(paused: view.paused, pauseUntil: view.pauseUntil))
        let override = response.overrides
            .first { $0.control == "translation" }
            .map { VoiceControlsOverride(state: $0.state, revision: $0.revision) }
        func artifactRevision(_ control: String) -> Int32 {
            response.overrides.first { $0.control == control }?.revision ?? 0
        }
        let artifacts = VoiceControlsArtifacts(recording: VoiceArtifactState(enabled: response.callArtifacts.recordingEnabled,
                                                                             revision: artifactRevision("recording"),
                                                                             delivery: response.callArtifacts.recordingDelivery,
                                                                             deliveryTarget: response.callArtifacts.recordingDeliveryTarget,
                                                                             stopped: response.callArtifacts.recordingStopped),
                                               summary: VoiceArtifactState(enabled: response.callArtifacts.summaryEnabled,
                                                                           revision: artifactRevision("summary"),
                                                                           delivery: response.callArtifacts.summaryDelivery,
                                                                           deliveryTarget: response.callArtifacts.summaryDeliveryTarget,
                                                                           stopped: false))
        return VoiceControlsState(sessionID: response.sessionId,
                                  effective: effective,
                                  override: override,
                                  artifacts: artifacts,
                                  conversation: VoiceConversationState(active: response.conversation.active,
                                                                       available: response.conversation.available,
                                                                       revision: response.conversation.revision))
    }

    /// An enabling write (ADR-0094 A.2): a 503 means the call's participants couldn't be read and nothing was
    /// written, so the same request goes once more after `Retry-After`. The caller keeps its spinner meanwhile.
    private func enablingCall<Value>(_ operation: () async throws -> Result<Value, VoiceControlsError>) async -> Result<Value, VoiceControlsError> {
        let first = await controlsCall(operation)
        guard case .failure(.serviceUnavailable(let retryAfter)) = first else { return first }
        MXLog.info("Voice translation write: participants unreadable, retrying once after \(retryAfter)")
        try? await Task.sleep(for: retryAfter)
        return await controlsCall(operation)
    }

    /// Same stale-MAS-token retry as `withUnauthorizedRetry` — a 401 gets
    /// one more attempt once the SDK has had time to refresh the token — but
    /// folding transport errors into the call controls' vocabulary instead
    /// of `AgentPlatformError`.
    private func controlsCall<Value>(_ operation: () async throws -> Result<Value, VoiceControlsError>) async -> Result<Value, VoiceControlsError> {
        let first = await controlsAttempt(operation)
        guard case .failure(.unauthorized) = first else { return first }
        try? await Task.sleep(for: Self.unauthorizedRetryDelay)
        return await controlsAttempt(operation)
    }

    private func controlsAttempt<Value>(_ operation: () async throws -> Result<Value, VoiceControlsError>) async -> Result<Value, VoiceControlsError> {
        do {
            return try await operation()
        } catch {
            MXLog.error("Voice session controls call failed: \(error)")
            return .failure(.unavailable("transport error"))
        }
    }
}
