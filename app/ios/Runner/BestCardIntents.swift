// Siri / App Shortcuts: "Hey Siri, best card for groceries in Best Card".
// The intent writes the requested category into the shared App Group and opens
// the app; Flutter reads it on launch/resume and shows the recommendation.
//
// Shared contract (keep in sync with lib/home_widget_service.dart):
//   App Group: group.com.dapp.bestcard   Key: siri_category  (category id string)

import AppIntents

private let appGroup = "group.com.dapp.bestcard"
private let siriKey = "siri_category"

@available(iOS 16.0, *)
enum SpendCategory: String, AppEnum {
    case dining, grocery, fuel, travel, online, entertainment, general

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Spend category" }

    static var caseDisplayRepresentations: [SpendCategory: DisplayRepresentation] {
        [
            .dining: "dining",
            .grocery: "groceries",
            .fuel: "fuel",
            .travel: "travel",
            .online: "online shopping",
            .entertainment: "entertainment",
            .general: "everyday spend",
        ]
    }
}

@available(iOS 16.0, *)
struct ShowBestCardIntent: AppIntent {
    static var title: LocalizedStringResource { "Show best card" }
    static var description: IntentDescription {
        "Shows which of your cards earns the most for a spend category."
    }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Category")
    var category: SpendCategory

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: appGroup)?.set(category.rawValue, forKey: siriKey)
        return .result()
    }
}

@available(iOS 16.0, *)
struct BestCardShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowBestCardIntent(),
            phrases: [
                "Best card for \(\.$category) in \(.applicationName)",
                "Which card for \(\.$category) in \(.applicationName)",
                "\(.applicationName) best card for \(\.$category)",
            ],
            shortTitle: "Best card",
            systemImageName: "creditcard"
        )
    }
}
