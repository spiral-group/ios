//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082, the pinned post's concept A). Latest with
// its pinned rules post and a few posts from people, on the mock service: the
// screen the operator looks at, in Ukrainian or English as the device is set.
//

import SwiftUI

class FeedScreenHarnessCoordinator: CoordinatorProtocol {
    private let viewModel: FeedScreenViewModel

    init() {
        let posts = Self.texts.people.enumerated().map { index, entry in
            FeedPreviewData.post(id: String(format: "01933f2a-0000-7000-8000-%012d", 2000 + index),
                                 author: FeedAuthor(userID: "@harness\(index):spiral.md", name: entry.name, avatarURL: nil, bio: nil,
                                                    isOfficial: false, isNameWithheld: false),
                                 minutesAgo: entry.minutesAgo,
                                 text: entry.text)
                .withCounts(likes: index == 0 ? 7 : 0, comments: index == 0 ? 2 : 0)
        }
        let pinned = FeedPreviewData.post(id: FeedPreviewData.welcomePost.id,
                                          author: FeedPreviewData.spiral,
                                          minutesAgo: 34,
                                          text: Self.texts.welcome)
        viewModel = FeedScreen_Previews.makeViewModel(.success(FeedPage(items: posts, nextCursor: nil, pinned: pinned)))
    }

    func toPresentable() -> AnyView {
        AnyView(ElementNavigationStack { FeedScreen(context: viewModel.context) })
    }

    // MARK: - Texts

    private struct Texts {
        let welcome: String
        let people: [(name: String, minutesAgo: Int, text: String)]
    }

    private static var texts: Texts {
        Locale.preferredLanguages.first?.hasPrefix("uk") == true ? ukrainian : english
    }

    private static let ukrainian = Texts(welcome: "👋 Привіт! Це стрічка Spiral — місце, де всі в Spiral діляться думками, новинами й тим, що їх тішить. "
        + "Найсвіжіше — вгорі.\n\nЩоб тут було добре кожному, домовмося про просте:\n"
        + "• будьмо доброзичливими — без ненависті, цькування й погроз;\n• без сексуального вмісту, спаму й шахрайства.\n\n"
        + "Усі правила: https://spiral.md/brand/terms (розділ 6). Раді вам тут!",
        people: [("Олена Коваль", 120, "Нарешті перший сніг у Львові ❄️ Хто ще сьогодні вийшов погуляти з самого ранку?"),
                 ("Тарас Мельник", 300, "Зробив собі агента, який нагадує поливати вазони. Вазони живі вже третій тиждень. Це рекорд 🌱"),
                 ("Ірина Бойко", 1440, "Хто знає гарну кав'ярню біля Контрактової, де можна попрацювати з ноутбуком?")])

    private static let english = Texts(welcome: FeedPreviewData.welcomePost.content.text,
                                       people: [("Olena Koval", 120, "First snow in Lviv at last ❄️ Who else went out for a walk first thing this morning?"),
                                                ("Taras Melnyk", 300, "Made myself an agent that reminds me to water the plants. Three weeks alive. A record 🌱"),
                                                ("Iryna Boiko", 1440, "Anyone know a good café near Kontraktova where I can work on a laptop?")])
}
