//
//  ALAEWidget.swift
//  ALAE — Widget écran d'accueil : prochaine prière + compte à rebours + date Hijri + 5 horaires
//
//  ⚠️ Ce fichier appartient à la TARGET DU WIDGET (ALAEWidgetExtension),
//     PAS à la target ALAE de l'app. (Voir WIDGET-XCODE.md.)
//
//  Données : lues depuis l'App Group partagé "group.com.alae.shared".
//  L'app (ViewController) y écrit les horaires + ville à chaque calcul.
//  La date Hijri est calculée localement (Calendar islamique), pas besoin de réseau.
//

import WidgetKit
import SwiftUI

// MARK: - App Group (doit être IDENTIQUE côté app et côté widget)
let kAppGroup = "group.com.alae.misbaha.ALAE.shared"
// MARK: - Modèle d'une prière
struct Prayer {
    let key: String       // "Fajr", "Dhuhr", ...
    let labelAr: String   // affichage arabe
    let date: Date        // heure du jour
}

// MARK: - Palette (accordée à l'app)
private let kBg      = Color(red: 0.043, green: 0.051, blue: 0.063)   // #0B0D10
private let kBg2     = Color(red: 0.11,  green: 0.08,  blue: 0.045)   // brun profond
private let kGold    = Color(red: 0.78,  green: 0.647, blue: 0.357)   // #C7A55B
private let kGoldLt  = Color(red: 0.957, green: 0.847, blue: 0.608)   // #F4D89B
private let kText    = Color(red: 0.96,  green: 0.93,  blue: 0.86)
private let kTextDim = Color(red: 0.62,  green: 0.58,  blue: 0.50)

// MARK: - Timeline Entry
struct AlaeEntry: TimelineEntry {
    let date: Date
    let prayers: [Prayer]
    let next: Prayer?
    let city: String
    let hijri: String
}

// MARK: - Lecture des données partagées + calcul
enum AlaeData {
    static func loadPrayers() -> (prayers: [Prayer], city: String) {
        let order: [(String, String)] = [
            ("Fajr", "الفجر"), ("Dhuhr", "الظهر"), ("Asr", "العصر"),
            ("Maghrib", "المغرب"), ("Isha", "العشاء")
        ]
        guard let ud = UserDefaults(suiteName: kAppGroup),
              let timings = ud.dictionary(forKey: "prayerTimings") as? [String: String]
        else { return ([], "") }

        let city = ud.string(forKey: "prayerCity") ?? ""
        let cal = Calendar.current
        let today = Date()
        var result: [Prayer] = []
        for (key, label) in order {
            guard let raw = timings[key] else { continue }
            let hhmm = String(raw.prefix(5))                     // "05:23 (CEST)" -> "05:23"
            let parts = hhmm.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            var comp = cal.dateComponents([.year, .month, .day], from: today)
            comp.hour = parts[0]; comp.minute = parts[1]
            if let d = cal.date(from: comp) {
                result.append(Prayer(key: key, labelAr: label, date: d))
            }
        }
        return (result, city)
    }

    /// Prochaine prière à partir de `from` (sinon Fajr du lendemain).
    static func nextPrayer(_ prayers: [Prayer], from: Date) -> Prayer? {
        if let up = prayers.first(where: { $0.date > from }) { return up }
        // après Isha -> Fajr demain
        guard let fajr = prayers.first else { return nil }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: fajr.date)
        return tomorrow.map { Prayer(key: fajr.key, labelAr: fajr.labelAr, date: $0) }
    }

    /// Date Hijri en arabe (ex. "١٥ جمادى الأولى ١٤٤٧").
    static func hijriString(for date: Date) -> String {
        var cal = Calendar(identifier: .islamicUmmAlQura)
        cal.locale = Locale(identifier: "ar")
        let df = DateFormatter()
        df.calendar = cal
        df.locale = Locale(identifier: "ar")
        df.dateFormat = "d MMMM yyyy"
        return df.string(from: date)
    }
}

// MARK: - Provider
struct AlaeProvider: TimelineProvider {
    func placeholder(in context: Context) -> AlaeEntry {
        AlaeEntry(date: Date(), prayers: [], next: nil, city: "—", hijri: AlaeData.hijriString(for: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (AlaeEntry) -> Void) {
        completion(makeEntry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AlaeEntry>) -> Void) {
        let now = Date()
        let entry = makeEntry(at: now)
        // Rafraîchir à la prochaine prière (pour changer la cible du compte à rebours),
        // sinon dans 15 min au plus tard.
        let refresh = entry.next?.date ?? Calendar.current.date(byAdding: .minute, value: 15, to: now)!
        let capped = min(refresh, Calendar.current.date(byAdding: .minute, value: 30, to: now)!)
        completion(Timeline(entries: [entry], policy: .after(capped)))
    }

    private func makeEntry(at date: Date) -> AlaeEntry {
        let (prayers, city) = AlaeData.loadPrayers()
        let next = AlaeData.nextPrayer(prayers, from: date)
        return AlaeEntry(date: date, prayers: prayers, next: next,
                         city: city.isEmpty ? "—" : city,
                         hijri: AlaeData.hijriString(for: date))
    }
}

// MARK: - Vues
struct AlaeWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: AlaeEntry

    var body: some View {
        ZStack {
            LinearGradient(colors: [kBg2, kBg], startPoint: .top, endPoint: .bottom)
            switch family {
            case .systemSmall:  smallView
            case .systemMedium: mediumView
            default:            mediumView
            }
        }
        .widgetBackgroundCompat()
    }

    // — Petit : prochaine prière + compte à rebours —
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("آلَاء")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(kGold)
            Spacer(minLength: 0)
            if let n = entry.next {
                Text(n.labelAr)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(kGoldLt)
                Text(n.date, style: .time)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(kText)
                Text(n.date, style: .timer)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(kGold)
            } else {
                Text("Ouvre l'app").font(.system(size: 13)).foregroundColor(kTextDim)
            }
            Spacer(minLength: 0)
            Text(entry.hijri)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(kTextDim)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
    }

    // — Moyen : compte à rebours + les 5 horaires —
    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("آلَاء · \(entry.city)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(kGold).lineLimit(1)
                Spacer(minLength: 0)
                if let n = entry.next {
                    Text(n.labelAr)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(kGoldLt)
                    Text(n.date, style: .timer)
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(kText)
                }
                Spacer(minLength: 0)
                Text(entry.hijri)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(kTextDim)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Colonne des 5 horaires
            VStack(spacing: 6) {
                ForEach(entry.prayers, id: \.key) { p in
                    HStack {
                        Text(p.labelAr)
                            .font(.system(size: 12, weight: isNext(p) ? .bold : .regular))
                            .foregroundColor(isNext(p) ? kGoldLt : kText)
                        Spacer()
                        Text(p.date, style: .time)
                            .font(.system(size: 12, weight: isNext(p) ? .bold : .regular))
                            .monospacedDigit()
                            .foregroundColor(isNext(p) ? kGoldLt : kTextDim)
                    }
                }
            }
            .frame(width: 132)
            .padding(.vertical, 2)
        }
        .padding(14)
    }

    private func isNext(_ p: Prayer) -> Bool {
        entry.next?.key == p.key && Calendar.current.isDate(entry.next!.date, inSameDayAs: p.date)
    }
}

// Fond compatible iOS 17+ (containerBackground) et versions antérieures.
extension View {
    @ViewBuilder func widgetBackgroundCompat() -> some View {
        self
        
    }
}

// MARK: - Widget
struct ALAEWidget: Widget {
    let kind = "ALAEWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AlaeProvider()) { entry in
            AlaeWidgetView(entry: entry)
        }
        .configurationDisplayName("Horaires de prière")
        .description("Prochaine prière, compte à rebours et date Hijri.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ALAEWidgetBundle: WidgetBundle {
    var body: some Widget { ALAEWidget() }
}

