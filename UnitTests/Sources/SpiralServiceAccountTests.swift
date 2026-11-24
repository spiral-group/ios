//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (1.0.3): people search shows only people.
//

@testable import Spiral
import Testing

struct SpiralServiceAccountTests {
    private let server = "spiral.md"
    
    @Test(arguments: [
        // Agents and the platform's appservice sender.
        "@assistant-alice:spiral.md", "@agent-shop-2:spiral.md", "@agent-platform-bot:spiral.md",
        // Bridge bots and puppets.
        "@telegrambot:spiral.md", "@whatsappbot:spiral.md", "@instagrambot:spiral.md", "@instagram-login-bot:spiral.md",
        "@telegram_12345:spiral.md", "@whatsapp_380501234567:spiral.md", "@instagram_9876:spiral.md",
        // The `_` convention, LiveKit's JWT service.
        "@_lk_jwt_service:spiral.md", "@_anything:spiral.md",
        // The official feed account.
        "@spiral:spiral.md"
    ])
    func serviceAccountIsClassified(_ userID: String) {
        #expect(SpiralServiceAccount.isService(userID, ownServerName: server))
    }
    
    @Test(arguments: ["@Agent-X:spiral.md", "@agent-x:SPIRAL.MD", "@ASSISTANT-alice:Spiral.md", "@TelegramBot:spiral.md",
                      "@Telegram_42:spiral.md", "@Spiral:spiral.md", "@_LK_JWT_Service:spiral.md"])
    func mixedCaseServiceAccountIsClassified(_ userID: String) {
        #expect(SpiralServiceAccount.isService(userID, ownServerName: server))
        #expect(SpiralServiceAccount.isService(userID, ownServerName: "Spiral.MD"))
    }
    
    @Test(arguments: [
        "@alice:spiral.md", "@telegramfan:spiral.md", "@spiralfan:spiral.md", "@myspiral:spiral.md",
        "@assistant:spiral.md", "@agent:spiral.md", "@agentsmith:spiral.md", "@bot_telegram:spiral.md", "@whatsapp:spiral.md"
    ])
    func personIsKept(_ userID: String) {
        #expect(!SpiralServiceAccount.isService(userID, ownServerName: server))
    }
    
    @Test(arguments: [
        "@assistant-alice:matrix.org", "@telegrambot:matrix.org", "@_lk_jwt_service:matrix.org", "@spiral:matrix.org",
        "@spiral:spiral.md.evil.org"
    ])
    func anotherServerIsNotClassified(_ userID: String) {
        #expect(!SpiralServiceAccount.isService(userID, ownServerName: server))
    }
    
    @Test(arguments: ["spiral", "@spiral", "", "@:spiral.md"])
    func malformedIDIsNotClassified(_ userID: String) {
        #expect(!SpiralServiceAccount.isService(userID, ownServerName: server))
    }
}
