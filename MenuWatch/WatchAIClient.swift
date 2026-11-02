import Foundation

/// Thin wrapper around ChatEngine for the watch. Keeps model selection
/// identical to the iOS app via the shared AIModel enum.
@MainActor
enum WatchAIClient {
    static func send(prompt: String,
                     history: [ChatTurn],
                     sessionId: String,
                     menuStore: MenuStore,
                     cocktailStore: CocktailStore,
                     bottleStore: BottleStore,
                     restockStore: RestockStore,
                     interactionId: UUID,
                     onActivity: (@MainActor (String?) -> Void)? = nil) async throws -> ChatTurn {
        let engine = ChatEngine(
            menuStore: menuStore,
            bottleStore: bottleStore,
            restockStore: restockStore,
            cocktailStore: cocktailStore,
            surface: "watch",
            surfaceHint: """
            The answer will be read on an Apple Watch — a screen the size of a postage stamp. Plain text only — no markdown, no headers, no bullet characters.

            START WITH THE ANSWER. Never narrate your own process ("Let me check the menu…", "Looking that up…"). Never state what something is NOT before answering ("X isn't on our menu, but the classic recipe is…"). Never recap the question. Never hedge. Just answer.

            If the user asks for a list (ingredients, components, options), give the actual list, one item per line. If they ask a one-fact question, give one sentence. Length matches what the answer requires — never pad, never substitute a summary for a list when components were asked for.
            """
        )
        return try await engine.ask(question: prompt, history: history, sessionId: sessionId,
                                    interactionId: interactionId, onActivity: onActivity)
    }
}
