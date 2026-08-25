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
import UIKit

// MARK: - App Group (doit être IDENTIQUE côté app et côté widget)
let kAppGroup = "group.com.alae.misbaha.ALAE.shared"

// MARK: - Palette (accordée à l'app : Noir & Or)
private let kBg      = Color(red: 0.055, green: 0.063, blue: 0.078)
private let kBg2     = Color(red: 0.13,  green: 0.10,  blue: 0.055)
private let kGold    = Color(red: 0.78,  green: 0.647, blue: 0.357)
private let kGoldLt  = Color(red: 0.957, green: 0.847, blue: 0.608)
private let kGoldDeep = Color(red: 0.788, green: 0.604, blue: 0.290)
private let kText    = Color(red: 0.96,  green: 0.93,  blue: 0.86)
private let kTextDim = Color(red: 0.66,  green: 0.61,  blue: 0.52)

// Dégradé or (texte) : reproduit le fondu doré vertical du mockup HTML.
private let goldGradient = LinearGradient(colors: [kGoldLt, kGold, kGoldDeep], startPoint: .top, endPoint: .bottom)
private func textShadow<V: View>(_ v: V) -> some View { v.shadow(color: .black.opacity(0.85), radius: 3, x: 0, y: 1).shadow(color: .black.opacity(0.6), radius: 6) }
// Dégradé « soie dorée » horizontal, réservé à l'heure (comme l'animation CSS du mockup).
private let shineGradient = LinearGradient(colors: [
    Color(red:0.42,green:0.26,blue:0.08), Color(red:0.72,green:0.50,blue:0.20),
    Color(red:0.95,green:0.78,blue:0.48), Color(red:1.0,green:0.98,blue:0.90),
    Color(red:1.0,green:0.93,blue:0.68), Color(red:0.85,green:0.58,blue:0.15),
    Color(red:0.55,green:0.34,blue:0.10), Color(red:0.95,green:0.78,blue:0.48),
    Color(red:1.0,green:0.96,blue:0.80)
], startPoint: .topLeading, endPoint: .bottomTrailing)
// Version adoucie du même dégradé — pour la liste des prières (moins de contraste).
private let softShineGradient = LinearGradient(colors: [
    Color(red:0.80,green:0.62,blue:0.32), Color(red:0.95,green:0.82,blue:0.56),
    Color(red:1.0,green:0.96,blue:0.86), Color(red:0.92,green:0.76,blue:0.46),
    Color(red:0.98,green:0.90,blue:0.72)
], startPoint: .topLeading, endPoint: .bottomTrailing)

// Variantes du dégradé « or qui coule », réservées à l'heure. Une variante clairement
// différente est choisie à chaque rafraîchissement du widget (voir AlaeEntry.timeGradientSeed).
private let timeGradientVariants: [LinearGradient] = [
    // 0 — Or classique
    LinearGradient(colors: [Color(red:0.55,green:0.34,blue:0.10), Color(red:0.95,green:0.78,blue:0.48),
                             Color(red:1.0,green:0.98,blue:0.90), Color(red:0.85,green:0.58,blue:0.15)],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
    // 1 — Or rosé / champagne
    LinearGradient(colors: [Color(red:0.50,green:0.28,blue:0.22), Color(red:0.92,green:0.68,blue:0.58),
                             Color(red:1.0,green:0.93,blue:0.85), Color(red:0.80,green:0.50,blue:0.42)],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
    // 2 — Bronze / ambre
    LinearGradient(colors: [Color(red:0.36,green:0.22,blue:0.06), Color(red:0.78,green:0.48,blue:0.14),
                             Color(red:0.98,green:0.80,blue:0.42), Color(red:0.55,green:0.32,blue:0.08)],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
    // 3 — Or pâle / platine
    LinearGradient(colors: [Color(red:0.58,green:0.53,blue:0.38), Color(red:0.90,green:0.87,blue:0.72),
                             Color(red:1.0,green:1.0,blue:0.96), Color(red:0.78,green:0.72,blue:0.55)],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
    // 4 — Or antique profond
    LinearGradient(colors: [Color(red:0.30,green:0.18,blue:0.04), Color(red:0.62,green:0.40,blue:0.10),
                             Color(red:0.90,green:0.70,blue:0.30), Color(red:0.45,green:0.28,blue:0.06)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
]

// MARK: - Prières (ordre + libellés)
// Clés telles qu'écrites par l'app dans prayerTimings.
private let kPrayerKeys = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
// Libellés FR translittérés voulus par l'utilisateur.
private let kPrayerFr   = ["Alfajr", "Chourouk", "Dohr", "Aasr", "Magreb", "Ichaa"]
private let kPrayerAr   = ["الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء"]

// Dhikr affiché en bas du widget.
private let kDhikr1 = "سُبْحَانَ اللَّهِ وَبِحَمْدِهِ"
private let kDhikr2 = "سُبْحَانَ اللَّهِ الْعَظيمِ"

// Polices du mockup HTML : Scheherazade New (arabe) + Cormorant Garamond (chiffres/latin).
// Fichiers ScheherazadeNew-Regular.ttf et CormorantGaramond-Medium.ttf ajoutés à la target du widget
// (+ déclarés dans son Info.plist sous « Fonts provided by application »).
// Repli automatique sur la police système si l'un des deux fichiers n'est pas encore dans la target.
private func arFont(_ size: CGFloat) -> Font {
    UIFont(name: "ScheherazadeNew-Regular", size: size) != nil ? Font.custom("ScheherazadeNew-Regular", size: size) : .system(size: size, weight: .medium)
}
// Variante plus épaisse (Medium) — utilisée uniquement pour le nom de prière du widget moyen.
private func arFontMedium(_ size: CGFloat) -> Font {
    UIFont(name: "ScheherazadeNew-Medium", size: size) != nil ? Font.custom("ScheherazadeNew-Medium", size: size)
    : (UIFont(name: "ScheherazadeNew-Regular", size: size) != nil ? Font.custom("ScheherazadeNew-Regular", size: size) : .system(size: size, weight: .semibold))
}
// Police du nom de prière (الفجر…) : même police « Amiri Quran » que la page Horaires de l'app.
// Fichier AmiriQuran.ttf à ajouter à la target du widget (Fonts provided by application).
private func prayerNameFont(_ size: CGFloat) -> Font {
    Font.custom("Amiri-Bold", size: size)
}
private func amiriRegularFont(_ size: CGFloat) -> Font {
    prayerNameFont(size)
}
private func serifFont(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
    UIFont(name: "CormorantGaramond-Medium", size: size) != nil ? Font.custom("CormorantGaramond-Medium", size: size) : .system(size: size, weight: weight, design: .serif)
}

struct PrayerItem { let fr: String; let ar: String; let time: String; let date: Date }

private func countdownString(_ target: Date) -> String {
    let mins = Int(max(0, target.timeIntervalSinceNow / 60))
    if mins >= 60 { return "Dans \(mins / 60)h \(String(format: "%02d", mins % 60))min" }
    return "Dans \(mins) min"
}

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
    let dhikrToday: Int      // compteur du jour (partagé par l'app, 0 si absent)

    // Change de manière visible à chaque rafraîchissement du widget (une variante par entry).
    var timeGradient: LinearGradient {
        let seed = Int(date.timeIntervalSince1970 / 60) % timeGradientVariants.count
        return timeGradientVariants[seed]
    }
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
        let dhikrToday = ud?.integer(forKey: "dhikrTodayCount") ?? 0
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
                         nextDate: n.date, city: city, hijri: hijri, all: items, dhikrToday: dhikrToday)
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
            Image("WidgetSilkDark")
                .resizable()
                .scaledToFill()
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
            .init(color: redDeep, location: 1.00)
        ]), center: .center)
    }
    let scale: CGFloat
    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .strokeBorder(Color.black.opacity(0.6), lineWidth: 3 * scale)
            ContainerRelativeShape()
                .strokeBorder(sheen, lineWidth: 2.6 * scale)
                .shadow(color: goldLt.opacity(0.35), radius: 3 * scale)
            ContainerRelativeShape()
                .strokeBorder(glint.opacity(0.9), lineWidth: 0.6 * scale)
        }
    }
}

// MARK: - Toile du widget : fond soie + cadre or incrusté (compile iOS 16 & 17)

// MARK: - Fond pleine surface
// .background() ne couvre que la zone de contenu : sur iOS 17+ les marges que le systeme
// ajoute autour restent au fond blanc par defaut (bandes blanches a gauche et a droite).
// .containerBackground remplit tout le widget, marges comprises. Repli sur .background
// pour iOS 16 et pour une compilation avec un SDK anterieur a iOS 17.
private extension View {
    @ViewBuilder func alaeFullBleedBackground() -> some View {
        #if compiler(>=5.9)
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) { AlaeBackground() }
        } else {
            self.background(AlaeBackground())
        }
        #else
        self.background(AlaeBackground())
        #endif
    }
}

// MARK: - Toile mise a l'echelle
// Les offset(x:y:) des deux vues sont cales en dur sur les toiles des mockups HTML :
// 158x158 pt pour le petit, 338x158 pt pour le moyen. Le widget reel est plus grand
// (ou plus petit) selon le modele d'iPhone. Sans mise a l'echelle, le texte de droite
// et du bas sort du cadre et se fait couper, et le cadre or ne suit plus les bords.
// On dessine donc a taille fixe, puis on met l'ensemble a l'echelle pour tenir
// exactement dans la place que le systeme accorde.
private struct AlaeScaledCanvas<Content: View>: View {
    let canvas: CGSize
    let alignment: Alignment
    let content: Content
    init(_ canvas: CGSize, alignment: Alignment = .topLeading, @ViewBuilder content: () -> Content) {
        self.canvas = canvas
        self.alignment = alignment
        self.content = content()
    }
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / canvas.width, geo.size.height / canvas.height)
            content
                .frame(width: canvas.width, height: canvas.height, alignment: alignment)
                .scaleEffect(s, anchor: .topLeading)
                .offset(x: (geo.size.width  - canvas.width  * s) / 2,
                        y: (geo.size.height - canvas.height * s) / 2)
        }
    }
}

// MARK: - Vues
struct AlaeWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: AlaeEntry

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(GoldFrameView(scale: family == .systemSmall ? 0.45 : 0.7))
            .alaeFullBleedBackground()
            .widgetURL(URL(string: "alae://prayer"))
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .systemSmall:  smallView
        default:            mediumView
        }
    }

    // — Petit : prochaine prière + heure + compte à rebours + dhikr —
    // Positionnement libre, calqué sur Apercu-Widget-Petit.html : chaque élément
    // a sa taille et son offset(x:y:) propres, sans arbitrage de place entre eux.
    private var smallView: some View {
        AlaeScaledCanvas(CGSize(width: 158, height: 158), alignment: .top) {
        ZStack(alignment: .top) {
            Text("آلَاء")
                .font(prayerNameFont(18))
                .foregroundStyle(shineGradient)
                .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
                .frame(height: 18, alignment: .top)
                .offset(x: 0, y: 25)
            Text(entry.nextAr)
                .font(amiriRegularFont(50))
                .foregroundStyle(shineGradient)
                .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(height: 50, alignment: .top)
                .offset(x: 0, y: 43)
            Text(entry.nextTime)
                .font(serifFont(54))
                .foregroundStyle(shineGradient)
                .shadow(color: .black.opacity(0.85), radius: 4, y: 1)
                .lineLimit(1).minimumScaleFactor(0.4)
                .frame(height: 54, alignment: .top)
                .offset(x: 0, y: 64)
            Text(countdownString(entry.nextDate))
                .font(serifFont(15))
                .foregroundStyle(kGold)
                .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                .lineLimit(1)
                .frame(height: 15, alignment: .top)
                .offset(x: 0, y: 112)
            Text(kDhikr1)
                .font(arFont(33))
                .foregroundStyle(softShineGradient)
                .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
                .shadow(color: kGold.opacity(0.6), radius: 2)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(height: 33, alignment: .top)
                .offset(x: 0, y: 124)
            Text(kDhikr2)
                .font(arFont(32))
                .foregroundStyle(softShineGradient)
                .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
                .shadow(color: kGold.opacity(0.6), radius: 2)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(height: 32, alignment: .top)
                .offset(x: 0, y: 145)
        }
        }
    }

    // — Moyen : prochaine prière (gauche) + liste du jour (droite) — calqué sur Apercu-Widget-ALAE.html (.medium)
    private var mediumView: some View {
        AlaeScaledCanvas(CGSize(width: 338, height: 158), alignment: .topLeading) {
        ZStack(alignment: .topLeading) {
            Text(entry.city.isEmpty ? "آلَاء" : entry.city)
                .font(amiriRegularFont(16))
                .foregroundStyle(softShineGradient)
                .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                .lineLimit(1)
                .frame(height: 16, alignment: .top)
                .offset(x: 30, y: 29)
            Text(entry.nextAr)
                .font(arFontMedium(38))
                .foregroundStyle(shineGradient)
                .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(height: 48, alignment: .top)
                .offset(x: 30, y: 40)
            Text(entry.nextFr)
                .font(serifFont(11, weight: .medium))
                .foregroundStyle(goldGradient)
                .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                .lineLimit(1)
                .frame(height: 11, alignment: .top)
                .offset(x: 30, y: 79)
            Text(entry.nextTime)
                .font(serifFont(54))
                .foregroundStyle(softShineGradient)
                .shadow(color: .black.opacity(0.85), radius: 4, y: 1)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(height: 54, alignment: .top)
                .offset(x: 29, y: 74)
            Text(countdownString(entry.nextDate))
                .font(serifFont(14, weight: .medium))
                .foregroundStyle(goldGradient)
                .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(height: 14, alignment: .top)
                .offset(x: 29, y: 118)
            Text(kDhikr1 + " " + kDhikr2)
                .font(serifFont(18, weight: .bold))
                .foregroundStyle(shineGradient)
                .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(height: 16, alignment: .top)
                .offset(x: 28, y: 140)
            Text(entry.hijri)
                .font(arFont(16))
                .foregroundStyle(softShineGradient)
                .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(height: 15, alignment: .top)
                .offset(x: 28, y: 155)
            HStack(spacing: 1.5) {
                Circle().fill(kGoldLt).frame(width: 3, height: 3)
                Circle().fill(kGoldLt).frame(width: 4.5, height: 4.5)
                Circle().fill(kGoldLt).frame(width: 3, height: 3)
                Text("\(entry.dhikrToday)")
                    .font(serifFont(16, weight: .bold))
                    .foregroundStyle(goldGradient)
            }
            .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
            .offset(x: 170, y: 157)
            Text("مَوَاقيتُ الصَّلَاة")
                .font(arFont(12))
                .foregroundStyle(softShineGradient)
                .lineLimit(1)
                .frame(width: 121, height: 12, alignment: .trailing)
                .offset(x: 237, y: 29)
            VStack(spacing: -2) {
                ForEach(Array(entry.all.enumerated()), id: \.offset) { _, p in
                    let isNext = (p.fr == entry.nextFr && p.time == entry.nextTime)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isNext ? AnyShapeStyle(goldGradient) : AnyShapeStyle(kGold))
                            .frame(width: 5, height: 5)
                        Text(p.fr)
                            .font(serifFont(17, weight: isNext ? .bold : .medium))
                            .foregroundStyle(softShineGradient)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Spacer(minLength: 2)
                        Text(p.time)
                            .font(serifFont(17, weight: isNext ? .bold : .medium))
                            .monospacedDigit()
                            .foregroundStyle(softShineGradient)
                            .lineLimit(1)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .frame(width: 121, alignment: .leading)
                    .padding(.vertical, 0)
                    .background(
                        isNext
                        ? RoundedRectangle(cornerRadius: 9).fill(kGold.opacity(0.16))
                        : RoundedRectangle(cornerRadius: 9).fill(Color.clear)
                    )
                }
            }
            .offset(x: 237, y: 44)
        }
        }
    }
}

// MARK: - Fond widget (background classique, compatible iOS 16.1+ — pas de SDK iOS 17 disponible)
// Le fond/cadre dépasse légèrement (padding négatif) pour compenser les marges internes
// que le système ajoute par défaut sans contentMarginsDisabled (indisponible ici).
private struct WidgetBGModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(AlaeBackground())
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
