//
//  ViewController.swift
//  ALAE — v14 (WebView + notifications adhan + ALIMENTATION DU WIDGET via App Group)
//
//  1.0.8 — l'adhan sonne désormais à l'HEURE EXACTE de la prière.
//  Le préavis « X minutes avant » utilise un son doux, plus l'adhan.
//

import UIKit
import WebKit
import UserNotifications
import AVFoundation
import WidgetKit

/// Delegue de notifications de l'app.
/// Son seul role : autoriser banniere + SON + entree dans le centre de notifications
/// meme lorsque l'app est au premier plan. Sans delegue, iOS supprime silencieusement
/// ces notifications, donc l'adhan ne sonne pas si l'app est ouverte.
final class AlaeNotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlaeNotifDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

    // App Group partagé avec le widget (doit être identique côté widget)
    private let appGroupID = "group.com.alae.misbaha.ALAE.shared"

    var webView: WKWebView!

    override func loadView() {
        let contentController = WKUserContentController()
        contentController.add(self, name: "alae")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = false
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.verticalScrollIndicatorInsets = .zero
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.043, green: 0.051, blue: 0.063, alpha: 1.0)
        view = webView
    }

    // Fond sombre le temps que la WebView peigne son propre écran de démarrage HTML
    // (battements : Bismillah / Fabi ayyi âlaâi / Sadaqa Allah).
    private var splashOverlay: UIView?

    private func showSplash() {
        let bg = UIColor(red: 0.043, green: 0.051, blue: 0.063, alpha: 1.0)
        let overlay = UIView(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = bg
        view.addSubview(overlay)
        splashOverlay = overlay
    }

    private func hideSplash() {
        guard let overlay = splashOverlay else { return }
        UIView.animate(withDuration: 0.6, delay: 0.2, options: [], animations: {
            overlay.alpha = 0
        }, completion: { _ in
            overlay.removeFromSuperview()
            self.splashOverlay = nil
        })
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 14.0, *) { WidgetCenter.shared.reloadAllTimelines() } // force le refresh à chaque lancement
        showSplash()
        if let url = Bundle.main.url(forResource: "Misbaha-Standalone", withExtension: "html") {
            print("[ALAE] HTML trouvé : \(url.path)")
            let taille = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
            print("[ALAE] taille : \(taille ?? -1) octets")
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            print("[ALAE] ERREUR : Misbaha-Standalone.html ABSENT du bundle")
        }
        // Filet de sécurité : si l'intro ne signale jamais sa fin, on la retire quand même.
        DispatchQueue.main.asyncAfter(deadline: .now() + 25.0) { [weak self] in
            self?.hideSplash()
        }
        // Delegue de notifications : sans lui, iOS SUPPRIME en silence toute
        // notification qui arrive pendant que l'app est ouverte (ni banniere, ni son).
        // L'ancienne ligne castait AppDelegate en UNUserNotificationCenterDelegate,
        // ce qu'il n'est pas : le cast renvoyait nil et le delegue restait vide.
        UNUserNotificationCenter.current().delegate = AlaeNotifDelegate.shared
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[ALAE] chargement terminé : \(webView.url?.lastPathComponent ?? "?")")
        webView.evaluateJavaScript("[document.title, document.body ? document.body.children.length : -1, !!window.React, !!window.Babel].join(' | ')") { r, e in
            print("[ALAE] état page : \(r ?? "nil") \(e.map { " erreur: \($0)" } ?? "")")
        }
        hideSplash()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[ALAE] ÉCHEC navigation : \(error.localizedDescription)")
        hideSplash()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[ALAE] ÉCHEC chargement initial : \(error.localizedDescription)")
        hideSplash()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Le moteur web a été tué — typiquement faute de mémoire sur un appareil réel.
        print("[ALAE] LE MOTEUR WEB A ÉTÉ TUÉ (mémoire insuffisante ?) — rechargement")
        webView.reload()
    }

    // MARK: - Open external links in Safari
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           navigationAction.navigationType == .linkActivated,
           url.scheme == "https" || url.scheme == "http" {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { UIApplication.shared.open(url) }
        return nil
    }

    // MARK: - JS → Swift bridge
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        if type == "share" {
            let text = body["text"] as? String ?? ""
            let urlString = body["url"] as? String
            DispatchQueue.main.async {
                var items: [Any] = []
                if !text.isEmpty { items.append(text) }
                if let s = urlString, let u = URL(string: s) { items.append(u) }
                guard !items.isEmpty else { return }
                let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
                if let pop = activityVC.popoverPresentationController {
                    pop.sourceView = self.webView
                    pop.sourceRect = CGRect(x: self.webView.bounds.midX,
                                            y: self.webView.bounds.midY,
                                            width: 0, height: 0)
                    pop.permittedArrowDirections = []
                }
                self.present(activityVC, animated: true)
            }
            return
        }

        if type == "haptic" {
            let style = body["style"] as? String ?? "soft"
            DispatchQueue.main.async {
                let generator: UIImpactFeedbackGenerator
                switch style {
                case "heavy":  generator = UIImpactFeedbackGenerator(style: .heavy)
                case "rigid":  generator = UIImpactFeedbackGenerator(style: .rigid)
                case "medium": generator = UIImpactFeedbackGenerator(style: .medium)
                default:       generator = UIImpactFeedbackGenerator(style: .soft)
                }
                generator.prepare()
                generator.impactOccurred()
            }
            return
        }

        if type == "updateNotifications" {
            saveTimingsForWidget(body)          // ← alimente le widget (App Group)
            handleUpdateNotifications(body)
        }

        // Compteur de dhikr du jour, envoyé par l'app à chaque tap (syncWidgetSibha).
        // Sans ce récepteur, le widget lit une valeur jamais écrite et affiche 0.
        if type == "widgetSibha" {
            let count = body["count"] as? Int ?? 0
            if let shared = UserDefaults(suiteName: "group.com.alae.misbaha.ALAE.shared") {
                shared.set(count, forKey: "dhikrTodayCount")
                if #available(iOS 14.0, *) { WidgetCenter.shared.reloadAllTimelines() }
            }
        }
    }

    // MARK: - Widget : sauvegarde des horaires dans l'App Group + refresh
    private func saveTimingsForWidget(_ body: [String: Any]) {
        guard let ud = UserDefaults(suiteName: appGroupID) else { return }
        let timings = body["timings"] as? [String: String] ?? [:]
        let city    = body["city"] as? String ?? ""
        let hijri   = body["hijri"] as? String ?? ""

        if !timings.isEmpty {
            // Le widget lit un dictionnaire [String:String] via dictionary(forKey:)
            var clean: [String: String] = [:]
            for (k, v) in timings { clean[k] = String(v.prefix(5)) }
            ud.set(clean, forKey: "prayerTimings")
        }
        if !city.isEmpty  { ud.set(city,  forKey: "prayerCity") }
        if !hijri.isEmpty { ud.set(hijri, forKey: "hijri") }
        ud.set(Date().timeIntervalSince1970, forKey: "updatedAt")

        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Notifications
    private static let prayers: [(key: String, label: String)] = [
        ("Fajr",    "الفَجْر"),
        ("Dhuhr",   "الظُّهْر"),
        ("Asr",     "العَصْر"),
        ("Maghrib", "المَغْرِب"),
        ("Isha",    "العِشَاء"),
    ]

    /// Son de la notification : .caf COURT (≤ 30 s), sinon repli hadioui, sinon son système.
    private func adhanSound(for reciter: String) -> UNNotificationSound? {
        if reciter == "silent" { return nil }
        if Bundle.main.url(forResource: "adhan-\(reciter)-notif", withExtension: "caf") != nil {
            return UNNotificationSound(named: UNNotificationSoundName("adhan-\(reciter)-notif.caf"))
        }
        if Bundle.main.url(forResource: "adhan-hadioui-notif", withExtension: "caf") != nil {
            return UNNotificationSound(named: UNNotificationSoundName("adhan-hadioui-notif.caf"))
        }
        print("[Adhan] ⚠️ aucun .caf trouvé dans le bundle → son système par défaut")
        return .default
    }

    private func handleUpdateNotifications(_ body: [String: Any]) {
        let enabled    = body["enabled"] as? Bool ?? false
        let minutes    = body["minutesBefore"] as? Int ?? 5
        let reciter    = body["reciter"] as? String ?? "kouchi"
        let timings    = body["timings"] as? [String: String] ?? [:]
        let city       = body["city"] as? String ?? ""
        // Calendrier daté : [{date:"JJ-MM-AAAA", timings:{...}}, …] — l'heure exacte de CHAQUE jour.
        let days       = body["days"] as? [[String: Any]] ?? []

        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        if !enabled || (timings.isEmpty && days.isEmpty) { return }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }

            DispatchQueue.main.async {
                let sound = self.adhanSound(for: reciter)
                let center = UNUserNotificationCenter.current()
                let cal = Calendar.current
                let now = Date()

                // Adhan : à l'heure exacte de la prière.
                func contenu(_ label: String) -> UNMutableNotificationContent {
                    let c = UNMutableNotificationContent()
                    c.title = "آلَاء · \(label)"
                    c.body  = "حان وقت صلاة \(label) — \(city)"
                    c.sound = sound
                    return c
                }

                // Préavis : X minutes avant, son doux — jamais l'adhan,
                // sinon l'utilisateur croit que l'heure est déjà arrivée.
                func preavis(_ label: String) -> UNMutableNotificationContent {
                    let c = UNMutableNotificationContent()
                    c.title = "آلَاء · \(label)"
                    c.body  = "\(label) خلال \(minutes) دقيقة — \(city)"
                    c.sound = (reciter == "silent") ? nil : .default
                    return c
                }

                // ── Cas normal : horaires datés, jour par jour (aucune dérive) ──
                if !days.isEmpty {
                    var posees = 0
                    let plafond = 60          // iOS ne garde que 64 notifications en attente
                    for jour in days {
                        guard posees < plafond,
                              let dStr = jour["date"] as? String,
                              let t = jour["timings"] as? [String: String] else { continue }
                        let dp = dStr.split(separator: "-").compactMap { Int($0) }   // JJ-MM-AAAA
                        guard dp.count == 3 else { continue }

                        for prayer in ViewController.prayers {
                            guard posees < plafond, let raw = t[prayer.key] else { continue }
                            let hp = String(raw.prefix(5)).split(separator: ":").compactMap { Int($0) }
                            guard hp.count == 2 else { continue }

                            var comps = DateComponents()
                            comps.year = dp[2]; comps.month = dp[1]; comps.day = dp[0]
                            comps.hour = hp[0]; comps.minute = hp[1]
                            guard let brut = cal.date(from: comps) else { continue }

                            // ── 1) L'ADHAN, à l'heure exacte — toujours posé ──
                            if brut > now {
                                let cible = cal.dateComponents([.year, .month, .day, .hour, .minute], from: brut)
                                center.add(UNNotificationRequest(
                                    identifier: "alae-prayer-\(dStr)-\(prayer.key)",
                                    content: contenu(prayer.label),
                                    trigger: UNCalendarNotificationTrigger(dateMatching: cible, repeats: false)
                                ))
                                posees += 1
                            }

                            // ── 2) LE PRÉAVIS, son doux — seulement si demandé ──
                            guard minutes > 0, posees < plafond else { continue }
                            let feu = brut.addingTimeInterval(-Double(minutes) * 60)
                            guard feu > now else { continue }
                            let cibleP = cal.dateComponents([.year, .month, .day, .hour, .minute], from: feu)
                            center.add(UNNotificationRequest(
                                identifier: "alae-pre-\(dStr)-\(prayer.key)",
                                content: preavis(prayer.label),
                                trigger: UNCalendarNotificationTrigger(dateMatching: cibleP, repeats: false)
                            ))
                            posees += 1
                        }
                    }
                    print("[Adhan] \(posees) notifications datées programmées")
                    if posees > 0 { return }
                }

                // ── Repli : pas de calendrier → horaires du jour répétés quotidiennement ──
                for prayer in ViewController.prayers {
                    guard let raw = timings[prayer.key] else { continue }
                    let parts = String(raw.prefix(5)).split(separator: ":").compactMap { Int($0) }
                    guard parts.count == 2 else { continue }

                    // ── 1) L'ADHAN, à l'heure exacte ──
                    var cA = DateComponents()
                    cA.hour = parts[0]; cA.minute = parts[1]
                    center.add(UNNotificationRequest(
                        identifier: "alae-prayer-\(prayer.key)",
                        content: contenu(prayer.label),
                        trigger: UNCalendarNotificationTrigger(dateMatching: cA, repeats: true)
                    ))

                    // ── 2) LE PRÉAVIS, son doux ──
                    guard minutes > 0 else { continue }
                    var hour = parts[0]
                    var minute = parts[1] - minutes
                    if minute < 0 { minute += 60; hour -= 1 }
                    if hour < 0 { hour += 24 }
                    var cP = DateComponents()
                    cP.hour = hour; cP.minute = minute
                    center.add(UNNotificationRequest(
                        identifier: "alae-pre-\(prayer.key)",
                        content: preavis(prayer.label),
                        trigger: UNCalendarNotificationTrigger(dateMatching: cP, repeats: true)
                    ))
                }
                print("[Adhan] repli : horaires du jour répétés")
            }
        }
    }

    override var prefersStatusBarHidden: Bool { return false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
}
