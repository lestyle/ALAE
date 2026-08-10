//
//  ALAEWidget.swift
//  ALAE — Widget écran d'accueil : PROCHAINE PRIÈRE + compte à rebours + date Hijri
//
//  ⚠️ Ce fichier appartient à la TARGET DU WIDGET (ALAEWidgetExtension),
//     PAS à la target ALAE de l'app. (Voir WIDGET-XCODE.md.)
//
//  Données : lues depuis l'App Group partagé "group.com.alae.misbaha.ALAE.shared".
//  L'app (ViewController) y écrit les horaires de prière (prayerTimings) + la ville.
//  Le compte à rebours utilise Text(date, style:.relative) → se met à jour tout seul.
//  Conforme App Store : aucun son, aucune vibration — affichage uniquement.
//

import WidgetKit
import SwiftUI

// MARK: - App Group (doit être IDENTIQUE côté app et côté widget)
let kAppGroup = "group.com.alae.misbaha.ALAE.shared"

// MARK: - Palette (accordée à l'app : Noir & Or)
private let kBg      = Color(red: 0.055, green: 0.063, blue: 0.078)
private let kBg2     = Color(red: 0.13,  green: 0.10,  blue: 0.055)
private let kGold    = Color(red: 0.78,  green: 0.647, blue: 0.357)
private let kGoldLt  = Color(red: 0.957, green: 0.847, blue: 0.608)
private let kText    = Color(red: 0.96,  green: 0.93,  blue: 0.86)
private let kTextDim = Color(red: 0.66,  green: 0.61,  blue: 0.52)

// MARK: - Prières (ordre + libellés)
// Clés telles qu'écrites par l'app dans prayerTimings.
private let kPrayerKeys = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
// Libellés FR translittérés voulus par l'utilisateur.
private let kPrayerFr   = ["Sobh", "Chourouk", "Dohr", "Aasr", "Magreb", "Ichaa"]
private let kPrayerAr   = ["الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء"]

// Dhikr affiché en bas du widget.
private let kDhikr = "سُبْحَانَ اللَّهِ وَبِحَمْدِهِ سُبْحَانَ اللَّهِ الْعَظيمِ"

// Police Moshaf (naskh coranique) : fichier AmiriQuran.ttf ajouté à la target du widget.
// Repli automatique sur la police système si absente.
// Police Moshaf Médine (QPC V4 Tajweed) : fichier QPC-V4-Tajweed.ttf ajouté à la target du widget.
// ⚠️ Vérifie le nom exact de la police dans Xcode (double-clic sur le .ttf, ou via Font Book) :
//    si "QCF_P528" ne s'affiche pas, remplace la chaîne ci-dessous par le nom réel affiché.
private func arFont(_ size: CGFloat) -> Font { Font.custom("QCF_P528", size: size) }

struct PrayerItem { let fr: String; let ar: String; let time: String; let date: Date }

// MARK: - Timeline Entry
struct AlaeEntry: TimelineEntry {
    let date: Date
    let nextFr: String
    let nextAr: String
    let nextTime: String     // "23:40"
    let nextDate: Date       // pour le compte à rebours
    let city: String
    let hijri: String
    let all: [PrayerItem]    // toutes les prières du jour (format moyen)
}

// MARK: - Lecture des données partagées
enum AlaeData {
    static func hijriString(for date: Date) -> String {
        var cal = Calendar(identifier: .islamicUmmAlQura)
        cal.locale = Locale(identifier: "ar")
        let df = DateFormatter()
        df.calendar = cal
        df.locale = Locale(identifier: "ar_SA@numbers=latn")
        df.dateFormat = "d MMMM yyyy"
        return df.string(from: date)
    }

    /// Construit la liste des prières du jour + trouve la prochaine.
    static func compute(now: Date = Date()) -> AlaeEntry {
        let ud = UserDefaults(suiteName: kAppGroup)
        let timings = (ud?.dictionary(forKey: "prayerTimings") as? [String: String]) ?? [:]
        let city = ud?.string(forKey: "prayerCity") ?? ""
        let hijri = hijriString(for: now)

        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)

        var items: [PrayerItem] = []
        for (i, key) in kPrayerKeys.enumerated() {
            guard let t = timings[key], t.contains(":") else { continue }
            let parts = t.split(separator: ":")
            guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) else { continue }
            let d = cal.date(byAdding: .minute, value: h * 60 + m, to: startOfDay) ?? now
            items.append(PrayerItem(fr: kPrayerFr[i], ar: kPrayerAr[i], time: String(format: "%02d:%02d", h, m), date: d))
        }

        // Prochaine prière = première dont l'heure est > maintenant ; sinon Fajr de demain.
        var next = items.first(where: { $0.date > now })
        if next == nil, let first = items.first {
            let tomorrow = cal.date(byAdding: .day, value: 1, to: first.date) ?? first.date
            next = PrayerItem(fr: first.fr, ar: first.ar, time: first.time, date: tomorrow)
        }

        let n = next ?? PrayerItem(fr: "—", ar: "", time: "--:--", date: now.addingTimeInterval(3600))
        return AlaeEntry(date: now, nextFr: n.fr, nextAr: n.ar, nextTime: n.time,
                         nextDate: n.date, city: city, hijri: hijri, all: items)
    }
}

// MARK: - Provider
struct AlaeProvider: TimelineProvider {
    func placeholder(in context: Context) -> AlaeEntry { AlaeData.compute() }
    func getSnapshot(in context: Context, completion: @escaping (AlaeEntry) -> Void) {
        completion(AlaeData.compute())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AlaeEntry>) -> Void) {
        let entry = AlaeData.compute()
        // Rafraîchit à l'heure de la prochaine prière (+5 s) pour passer à la suivante ;
        // filet de sécurité à 30 min max.
        let soon = min(entry.nextDate.addingTimeInterval(5),
                       Date().addingTimeInterval(30 * 60))
        completion(Timeline(entries: [entry], policy: .after(soon)))
    }
}

// MARK: - Fond commun : SOIE noir & or dessinée en SwiftUI (aucune image externe requise)
private struct AlaeBackground: View {
    private let g0 = Color(red: 0.05,  green: 0.045, blue: 0.03)   // presque noir chaud
    private let g1 = Color(red: 0.17,  green: 0.12,  blue: 0.05)   // brun doré sombre
    private let g2 = Color(red: 0.42,  green: 0.30,  blue: 0.10)   // or moyen
    private let g3 = Color(red: 0.72,  green: 0.55,  blue: 0.22)   // or clair (reflet)

    var body: some View {
        ZStack {
            LinearGradient(colors: [g1, g0], startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(
                stops: [
                    .init(color: g0.opacity(0.0),  location: 0.00),
                    .init(color: g3.opacity(0.55), location: 0.16),
                    .init(color: g1.opacity(0.0),  location: 0.30),
                    .init(color: g2.opacity(0.45), location: 0.46),
                    .init(color: g0.opacity(0.0),  location: 0.60),
                    .init(color: g3.opacity(0.40), location: 0.78),
                    .init(color: g0.opacity(0.0),  location: 1.00)
                ],
                startPoint: .topTrailing, endPoint: .bottomLeading
            )
            RadialGradient(colors: [g3.opacity(0.35), .clear],
                           center: .init(x: 0.5, y: 0.42), startRadius: 6, endRadius: 240)
            RadialGradient(colors: [Color.clear, Color.black.opacity(0.35)],
                           center: .center, startRadius: 30, endRadius: 230)
            LinearGradient(colors: [Color.white.opacity(0.08), .clear],
                           startPoint: .top, endPoint: .center)
            Image("WidgetSilk")
                .resizable()
                .scaledToFill()
                .opacity(1.0)
                .brightness(0.12)
                .saturation(1.15)
            LinearGradient(colors: [Color.black.opacity(0.04), Color.black.opacity(0.16)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.clear, Color.clear, Color.black.opacity(0.5)],
                           center: .center, startRadius: 60, endRadius: 250)
            Color.black.opacity(0.30) // voile sombre pour la lisibilité du texte
        }
        .clipShape(ContainerRelativeShape())
    }
}

// MARK: - Cadre OR fin & élégant (incrusté 3 pt → jamais tronqué par les coins)
private struct GoldFrameView: View {
    private let redDeep = Color(red: 0.48, green: 0.18, blue: 0.06)   // #7a2f10
    private let redAmb  = Color(red: 0.76, green: 0.40, blue: 0.06)   // #c1650f
    private let goldLt  = Color(red: 1.00, green: 0.91, blue: 0.66)   // #ffe9a8
    private let glint   = Color(red: 1.00, green: 0.99, blue: 0.94)   // #fffdf0
    private let amber   = Color(red: 0.72, green: 0.48, blue: 0.10)   // #b8791a
    private let bronze  = Color(red: 0.48, green: 0.20, blue: 0.06)   // #7a3410
    private let gold    = Color(red: 0.91, green: 0.63, blue: 0.13)   // #e8a020
    private let cream   = Color(red: 1.00, green: 0.96, blue: 0.85)   // #fff6d8
    private var sheen: AngularGradient {
        AngularGradient(gradient: Gradient(stops: [
            .init(color: redDeep, location: 0.00),
            .init(color: redAmb,  location: 0.06),
            .init(color: goldLt,  location: 0.13),
            .init(color: glint,   location: 0.18),
            .init(color: amber,   location: 0.26),
            .init(color: bronze,  location: 0.34),
            .init(color: gold,    location: 0.42),
            .init(color: cream,   location: 0.50),
            .init(color: amber,   location: 0.58),
            .init(color: bronze,  location: 0.66),
            .init(color: goldLt,  location: 0.74),
            .init(color: glint,   location: 0.80),
            .init(color: amber,   location: 0.88),
            .init(color: redDeep, location: 0.94),
            .init(color: goldLt,  location: 1.00)
        ]), center: .center)
    }
    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .strokeBorder(Color.black.opacity(0.85), lineWidth: 8)
            ContainerRelativeShape()
                .strokeBorder(sheen, lineWidth: 5)
                .shadow(color: goldLt.opacity(0.4), radius: 6)
            ContainerRelativeShape()
                .strokeBorder(glint.opacity(0.95), lineWidth: 1)
            ContainerRelativeShape()
                .stroke(LinearGradient(colors: [.clear, .white.opacity(0.5), .clear],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 5)
                .blendMode(.overlay)
                .opacity(0.55)
        }
    }
}

// MARK: - Toile du widget : fond soie + cadre or incrusté (compile iOS 16 & 17)

// MARK: - Vues
struct AlaeWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: AlaeEntry

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(GoldFrameView())
            .modifier(WidgetBGModifier())
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .systemSmall:  smallView
        default:            mediumView
        }
    }

    // — Petit : prochaine prière + heure + compte à rebours + dhikr —
    private var smallView: some View {
        VStack(spacing: 2) {
            Text("آلَاء")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(kGold)
            Spacer(minLength: 0)
            Text(entry.nextAr)
                .font(arFont(20))
                .foregroundColor(kGoldLt)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(entry.nextFr)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(kTextDim)
            Text(entry.nextTime)
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundColor(kText)
                .shadow(color: kGold.opacity(0.35), radius: 8)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(entry.nextDate, style: .relative)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(kGold)
                .multilineTextAlignment(.center)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(kDhikr)
                .font(arFont(11))
                .foregroundColor(kGoldLt.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    // — Moyen : prochaine prière (gauche) + liste du jour (droite) —
    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.city.isEmpty ? "آلَاء" : entry.city)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(kGold)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(entry.nextAr)
                    .font(arFont(28))
                    .foregroundColor(kGoldLt)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(entry.nextFr)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(kTextDim)
                Text(entry.nextTime)
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .foregroundColor(kText)
                    .shadow(color: kGold.opacity(0.35), radius: 8)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(entry.nextDate, style: .relative)
                    .font(.system(size: 10.8, weight: .semibold))
                    .foregroundColor(kGold)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(kDhikr)
                    .font(arFont(11.5))
                    .foregroundColor(kGoldLt.opacity(0.9))
                    .lineLimit(2).minimumScaleFactor(0.7)
                Text(entry.hijri)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(kTextDim)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Liste des prières du jour
            VStack(spacing: 0) {
                Text("مَوَاقيتُ الصَّلَاة")
                    .font(arFont(11))
                    .foregroundColor(kGold.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.bottom, 3)
                ForEach(Array(entry.all.enumerated()), id: \.offset) { _, p in
                    let isNext = (p.fr == entry.nextFr && p.time == entry.nextTime)
                    HStack {
                        Text(p.fr)
                            .font(.system(size: 12, weight: isNext ? .bold : .medium))
                            .foregroundColor(isNext ? kGoldLt : kTextDim)
                        Spacer(minLength: 6)
                        Text(p.time)
                            .font(.system(size: 12, weight: isNext ? .bold : .medium, design: .serif))
                            .foregroundColor(isNext ? kText : kTextDim)
                    }
                    .padding(.vertical, 3.5)
                    .padding(.horizontal, 8)
                    .background(
                        isNext
                        ? RoundedRectangle(cornerRadius: 8).fill(kGold.opacity(0.14))
                        : RoundedRectangle(cornerRadius: 8).fill(Color.clear)
                    )
                }
            }
            .frame(width: 130)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

// MARK: - Fond widget : containerBackground obligatoire iOS 17+ (sinon widget noir/vide)
private struct WidgetBGModifier: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(for: .widget) { AlaeBackground() }
        } else {
            content.background(AlaeBackground())
        }
    }
}

// MARK: - Widget
struct ALAEWidget: Widget {
    let kind = "ALAEWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AlaeProvider()) { entry in
            AlaeWidgetView(entry: entry)
        }
        .configurationDisplayName("Prière — آلاء")
        .description("La prochaine prière, son heure et le compte à rebours.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ALAEWidgetBundle: WidgetBundle {
    var body: some Widget { ALAEWidget() }
}
