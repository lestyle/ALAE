//
//  ViewController.swift
//  ALAE — v13 (ViewController + AdhanManager FUSIONNÉS dans un seul fichier)
//
//  ⚠️ AdhanManager est inclus À LA FIN de ce fichier pour garantir sa compilation
//     (le projet n'arrivait pas à compiler AdhanManager.swift séparément).
//     => Assure-toi que AdhanManager.swift N'EST PAS coché dans la target ALAE,
//        sinon "duplicate AdhanManager". Le plus simple : supprime AdhanManager.swift
//        de la target (Remove Reference) — son code vit maintenant ici.
//

import UIKit
import WebKit
import UserNotifications
import AVFoundation
import WidgetKit

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

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
        // Plein écran edge-to-edge : empêche iOS d'ajouter un encart de safe-area
        // (sinon barre sombre en haut/bas, le fond ne remplit pas tout l'écran).
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.verticalScrollIndicatorInsets = .zero
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.043, green: 0.051, blue: 0.063, alpha: 1.0)
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let url = Bundle.main.url(forResource: "Misbaha-Standalone", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        UNUserNotificationCenter.current().delegate = (UIApplication.shared.delegate as? UNUserNotificationCenterDelegate)
        // Prépare la session audio pour l'adhan complet en arrière-plan
        AdhanManager.shared.reschedule()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Reprogramme l'adhan complet quand l'app revient au premier plan
        AdhanManager.shared.reschedule()
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
                // iPad: ancre le popover au centre (sinon crash sur iPad)
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

        if type == "playAdhan" {
            let reciter = body["reciter"] as? String ?? "hadioui"
            AdhanManager.shared.playPreview(reciter: reciter)
            return
        }
        if type == "stopAdhan" {
            AdhanManager.shared.stopPreview()
            return
        }

        if type == "updateNotifications" {
            handleUpdateNotifications(body)
        }
    }

    // MARK: - Notifications
    private func handleUpdateNotifications(_ body: [String: Any]) {
        let enabled    = body["enabled"] as? Bool ?? false
        let minutes    = body["minutesBefore"] as? Int ?? 5
        let reciter    = body["reciter"] as? String ?? "kouchi"
        let timings    = body["timings"] as? [String: String] ?? [:]
        let city       = body["city"] as? String ?? ""

        // ── Adhan COMPLET en arrière-plan (lecteur audio, pas de limite 30s) ──
        AdhanManager.shared.update(enabled: enabled, reciter: reciter, timings: timings)

        // ── Widget : écrire les horaires + ville dans l'App Group partagé ──
        writeWidgetData(timings: timings, city: city)

        // 1) Clear all existing scheduled notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        if !enabled || timings.isEmpty { return }

        // 2) Request permission then schedule
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            guard granted else { return }

            DispatchQueue.main.async {
                let prayers: [(key: String, label: String)] = [
                    ("Fajr",    "الفَجْر"),
                    ("Dhuhr",   "الظُّهْر"),
                    ("Asr",     "العَصْر"),
                    ("Maghrib", "المَغْرِب"),
                    ("Isha",    "العِشَاء"),
                ]

                for prayer in prayers {
                    guard let raw = timings[prayer.key] else { continue }
                    let hhmm = String(raw.prefix(5))           // "05:23 (CEST)" → "05:23"
                    let parts = hhmm.split(separator: ":").compactMap { Int($0) }
                    guard parts.count == 2 else { continue }
                    var hour = parts[0]
                    var minute = parts[1] - minutes
                    if minute < 0 { minute += 60; hour -= 1 }
                    if hour < 0 { hour += 24 }

                    let content = UNMutableNotificationContent()
                    content.title = "آلَاء · \(prayer.label)"
                    content.body  = minutes == 0
                        ? "حان وقت صلاة \(prayer.label) — \(city)"
                        : "\(prayer.label) خلال \(minutes) دقيقة — \(city)"

                    // Custom adhan sound (if reciter has audio file)
                    if reciter != "silent" {
                        // Version COURTE (≤ 30 s) dédiée à la notification (règle Apple).
                        // Repli sur hadioui si le récitateur choisi n'a pas encore de fichier.
                        let hasOwn = Bundle.main.url(forResource: "adhan-\(reciter)-notif", withExtension: "caf") != nil
                        let soundName = hasOwn ? "adhan-\(reciter)-notif.caf" : "adhan-hadioui-notif.caf"
                        content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
                    } else {
                        content.sound = nil
                    }

                    var dateComponents = DateComponents()
                    dateComponents.hour = hour
                    dateComponents.minute = minute

                    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                    let request = UNNotificationRequest(
                        identifier: "alae-prayer-\(prayer.key)",
                        content: content,
                        trigger: trigger
                    )
                    UNUserNotificationCenter.current().add(request)
                }
            }
        }
    }

    override var prefersStatusBarHidden: Bool { return false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - Widget (App Group partagé)
    private func writeWidgetData(timings: [String: String], city: String) {
        // ⚠️ Doit être IDENTIQUE à kAppGroup dans ALAEWidget.swift
        let appGroup = "group.com.alae.misbaha.ALAE.shared"
        guard let ud = UserDefaults(suiteName: appGroup) else {
            print("[Widget] App Group introuvable — vérifie l'entitlement.")
            return
        }
        ud.set(timings, forKey: "prayerTimings")
        ud.set(city, forKey: "prayerCity")
        // Recharge le widget écran d'accueil.
        WidgetCenter.shared.reloadAllTimelines()
    }
}


// =====================================================================
// ============  AdhanManager (fusionné ici — ne pas dupliquer)  ========
// =====================================================================
final class AdhanManager: NSObject {

    static let shared = AdhanManager()

    private var adhanPlayer: AVAudioPlayer?
    private var keepAlivePlayer: AVAudioPlayer?
    private var previewPlayer: AVAudioPlayer?
    private var timers: [Timer] = []

    private var enabled = false
    private var reciter = "kouchi"
    private var timings: [String: String] = [:]

    private let prayerKeys = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

    // MARK: - Session audio

    private func activateSession(duckOthers: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback = joue même en silencieux / écran verrouillé.
            let options: AVAudioSession.CategoryOptions = duckOthers ? [.duckOthers] : [.mixWithOthers]
            try session.setCategory(.playback, mode: .default, options: options)
            try session.setActive(true)
        } catch {
            print("[Adhan] session error: \(error)")
        }
    }

    // MARK: - API publique (appelée depuis ViewController)

    /// Reçoit les réglages + horaires depuis le JS et (re)programme l'adhan complet.
    func update(enabled: Bool, reciter: String, timings: [String: String]) {
        self.enabled = enabled
        self.reciter = reciter
        self.timings = timings

        cancelTimers()

        guard enabled, reciter != "silent", !timings.isEmpty else {
            stopKeepAlive()
            return
        }

        // Keep-alive en arrière-plan DÉSACTIVÉ (conformité App Store, règle 2.5.4).
        // L'adhan à l'heure passe uniquement par la notification (.caf ≤ 30 s).
        // L'adhan complet s'écoute dans l'app.
        stopKeepAlive()
        return
    }

    /// À rappeler quand l'app revient au premier plan (pour reprogrammer proprement).
    func reschedule() {
        guard enabled, reciter != "silent", !timings.isEmpty else { return }
        cancelTimers()
        scheduleRemainingToday()
    }

    // MARK: - Keep-alive (silence en boucle)

    private func startKeepAlive() {
        guard keepAlivePlayer == nil else { return }
        guard let url = Bundle.main.url(forResource: "silence", withExtension: "wav")
                     ?? Bundle.main.url(forResource: "silence", withExtension: "caf") else {
            print("[Adhan] silence.wav/.caf introuvable dans le bundle")
            return
        }
        activateSession(duckOthers: false)
        keepAlivePlayer = try? AVAudioPlayer(contentsOf: url)
        keepAlivePlayer?.numberOfLoops = -1   // boucle infinie
        keepAlivePlayer?.volume = 0.0         // silencieux
        keepAlivePlayer?.play()
    }

    private func stopKeepAlive() {
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Programmation des minuteurs

    private func cancelTimers() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
    }

    private func scheduleRemainingToday() {
        let cal = Calendar.current
        let now = Date()

        for key in prayerKeys {
            guard let raw = timings[key] else { continue }
            let hhmm = String(raw.prefix(5))                 // "05:23 (CEST)" → "05:23"
            let parts = hhmm.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { continue }

            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = parts[0]
            comps.minute = parts[1]
            comps.second = 0
            guard let fire = cal.date(from: comps), fire > now else { continue }

            let interval = fire.timeIntervalSince(now)
            let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
                self?.playAdhan()
            }
            RunLoop.main.add(t, forMode: .common)
            timers.append(t)
        }
    }

    // MARK: - Lecture de l'adhan complet

    // MARK: - Écoute in-app (premier plan, à la demande — 100 % sûr App Store)

    func playPreview(reciter: String) {
        let url = Bundle.main.url(forResource: "adhan-\(reciter)", withExtension: "mp3")
               ?? Bundle.main.url(forResource: "adhan-\(reciter)", withExtension: "caf")
               ?? Bundle.main.url(forResource: "adhan-hadioui", withExtension: "mp3")
               ?? Bundle.main.url(forResource: "adhan-hadioui", withExtension: "caf")
        guard let fileURL = url else { print("[Adhan] preview introuvable"); return }
        activateSession(duckOthers: true)
        previewPlayer?.stop()
        previewPlayer = try? AVAudioPlayer(contentsOf: fileURL)
        previewPlayer?.numberOfLoops = 0
        previewPlayer?.volume = 1.0
        previewPlayer?.play()
    }

    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func playAdhan() {
        // mp3 complet en priorité, sinon .caf si présent.
        let url = Bundle.main.url(forResource: "adhan-\(reciter)", withExtension: "mp3")
               ?? Bundle.main.url(forResource: "adhan-\(reciter)", withExtension: "caf")
               // repli : si le fichier du récitateur choisi manque, joue un adhan présent dans le bundle
               ?? Bundle.main.url(forResource: "adhan-hadioui", withExtension: "mp3")
               ?? Bundle.main.url(forResource: "adhan-hadioui", withExtension: "caf")
        guard let fileURL = url else {
            print("[Adhan] fichier adhan-\(reciter) introuvable")
            return
        }
        activateSession(duckOthers: true)  // baisse la musique en cours pendant l'adhan
        adhanPlayer = try? AVAudioPlayer(contentsOf: fileURL)
        adhanPlayer?.numberOfLoops = 0
        adhanPlayer?.volume = 1.0
        adhanPlayer?.delegate = self
        adhanPlayer?.play()

        // reprogramme les prières suivantes (au cas où)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.reschedule()
        }
    }
}

extension AdhanManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Fin de l'adhan : on revient à la session keep-alive silencieuse.
        if player == adhanPlayer {
            activateSession(duckOthers: false)
        }
    }
}

