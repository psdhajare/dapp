// BestCardWidget — home-screen widget showing the best card for the user's
// top spend category. Data is written by the Flutter app via the `home_widget`
// package into the shared App Group and read here.
//
// Shared contract (keep in sync with lib/home_widget_service.dart):
//   App Group:  group.com.dapp.bestcard
//   Key:        best_card   (JSON string)
//   JSON shape: {"category": "dining", "issuer": "Emirates NBD",
//                "name": "Duo", "headline": "5%", "caption": "back on dining",
//                "primary": "#2B2B33", "secondary": "#131318"}

import WidgetKit
import SwiftUI

private let appGroup = "group.com.dapp.bestcard"
private let dataKey = "best_card"

struct BestCard {
    var category: String
    var issuer: String
    var name: String
    var headline: String
    var caption: String
    var primary: Color
    var secondary: Color

    static let placeholder = BestCard(
        category: "dining", issuer: "Your bank", name: "Best Card",
        headline: "5%", caption: "back on dining",
        primary: Color(hex: "2B2B33"), secondary: Color(hex: "131318"))
}

struct Entry: TimelineEntry {
    let date: Date
    let card: BestCard
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), card: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), card: readCard() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: Date(), card: readCard() ?? .placeholder)
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func readCard() -> BestCard? {
        guard
            let defaults = UserDefaults(suiteName: appGroup),
            let raw = defaults.string(forKey: dataKey),
            let data = raw.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return BestCard(
            category: json["category"] as? String ?? "spend",
            issuer: json["issuer"] as? String ?? "",
            name: json["name"] as? String ?? "",
            headline: json["headline"] as? String ?? "",
            caption: json["caption"] as? String ?? "",
            primary: Color(hex: json["primary"] as? String ?? "2B2B33"),
            secondary: Color(hex: json["secondary"] as? String ?? "131318"))
    }
}

struct BestCardWidgetEntryView: View {
    var entry: Entry

    var body: some View {
        let c = entry.card
        ZStack(alignment: .leading) {
            LinearGradient(colors: [c.primary, c.secondary],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 6) {
                Text("BEST FOR \(c.category.uppercased())")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(1.2)
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Text(c.headline)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                Text(c.caption)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text("\(c.issuer.uppercased()) · \(c.name)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(16)
        }
    }
}

@main
struct BestCardWidget: Widget {
    let kind = "BestCardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                BestCardWidgetEntryView(entry: entry)
                    .containerBackground(.clear, for: .widget)
            } else {
                BestCardWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("ToroKard")
        .description("Your best card for your top spend category.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

extension Color {
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(
            .sRGB,
            red: Double((v >> 16) & 0xff) / 255,
            green: Double((v >> 8) & 0xff) / 255,
            blue: Double(v & 0xff) / 255,
            opacity: 1)
    }
}
