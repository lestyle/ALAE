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
import BackgroundTasks

/// Lecture de l'adhan COMPLET.
///
/// iOS plafonne le son d'une notification a 30 s : impossible d'y faire tenir
/// l'adhan entier. Quand l'utilisateur touche la banniere, l'app s'ouvre et
/// c'est ici qu'on joue le fichier complet (`adhan-<reciter>.mp3`, celui qui sert
/// deja a l'ecoute dans les Reglages — a ne pas confondre avec `-notif.caf`, la
/// version courte reservee a la notification).
final class AlaeAdhanPlayer: NSObject {
    static let shared = AlaeAdhanPlayer()
    private var lecteur: AVAudioPlayer?

    func jouerComplet(reciter: String) {
        guard reciter != "silent" else { return }
        let candidats = ["mp3", "m4a", "caf", "aac", "wav"]
        var url: URL?
        for ext in candidats {
            if let u = Bundle.main.url(forResource: "adhan-\(reciter)", withExtension: ext) { url = u; break }
        }
        // Repli : la version courte, mieux que le silence
        if url == nil { url = Bundle.main.url(forResource: "adhan-\(reciter)-notif", withExtension: "caf") }
        guard let fichier = url else {
            print("[Adhan] aucun fichier complet pour \(reciter)")
            return
        }
        do {
            // .playback : l'adhan s'entend meme si le bouton silencieux est actif.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            lecteur?.stop()
            lecteur = try AVAudioPlayer(contentsOf: fichier)
            lecteur?.prepareToPlay()
            lecteur?.play()
            print("[Adhan] lecture complete : \(fichier.lastPathComponent)")
        } catch {
            print("[Adhan] lecture impossible : \(error)")
        }
    }
}

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

    /// L'utilisateur a touche la notification : on ouvre l'app et on joue
    /// l'adhan COMPLET. Uniquement pour l'adhan lui-meme — pas pour le preavis,
    /// qui annonce une priere qui n'a pas encore commence.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           (info["genre"] as? String) == "adhan",
           let reciter = info["reciter"] as? String {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                AlaeAdhanPlayer.shared.jouerComplet(reciter: reciter)
            }
        }
        completionHandler()
    }
}

/// Replanification en arriere-plan de l'adhan.
///
/// iOS ne garde que 64 notifications locales en attente : l'app en pose ~60 d'un coup,
/// puis elles se consomment jour apres jour. Une fois epuisees, plus aucun adhan tant
/// que l'utilisateur n'ouvre pas l'app. Ce module demande a iOS de reveiller l'app
/// de temps en temps, sans intervention, juste le temps de reposer les 60 suivantes.
///
/// Le dernier calendrier envoye par le JS est memorise tel quel : la tache de fond
/// n'a pas besoin de la WebView, elle rejoue simplement le meme message.
enum AlaeReplanif {

    static let tacheID = "be.lestyle.alae.replanif"
    private static let cleCache = "alae.notif.dernierPayload"

    /// Memorise le dernier message `updateNotifications` recu du JS.
    static func memoriser(_ body: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        UserDefaults.standard.set(data, forKey: cleCache)
    }

    /// Rejoue le dernier calendrier connu. Sans WebView, sans reseau.
    @discardableResult
    static func rejouerDepuisCache() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: cleCache),
              let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return false }
        ViewController.handleUpdateNotifications(body)
        return true
    }

    /// A appeler UNE FOIS au lancement, avant la fin du demarrage
    /// (dans `application(_:didFinishLaunchingWithOptions:)`).
    static func enregistrer() {
        guard #available(iOS 13.0, *) else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: tacheID, using: nil) { task in
            // Toujours reprogrammer la suivante en premier : si on l'oublie,
            // la chaine s'arrete apres un seul reveil.
            programmer()
            let ok = rejouerDepuisCache()
            task.setTaskCompleted(success: ok)
        }
    }

    /// Demande le prochain reveil. iOS choisit le moment reel selon l'usage de l'app.
    static func programmer() {
        guard #available(iOS 13.0, *) else { return }
        let req = BGAppRefreshTaskRequest(identifier: tacheID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 3600)   // au plus tot dans 12 h
        do { try BGTaskScheduler.shared.submit(req) }
        catch { print("[Adhan] replanification impossible : \(error)") }
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

        // Adhan : demander un reveil en arriere-plan, et reposer les notifications
        // a chaque retour au premier plan (filet si iOS n'a jamais accorde le reveil).
        AlaeReplanif.programmer()
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { _ in
            AlaeReplanif.rejouerDepuisCache()
            AlaeReplanif.programmer()
        }
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

    // Nombre de fois que le moteur web a ete tue depuis le lancement.
    private var nbPlantages = 0

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        nbPlantages += 1
        print("[ALAE] LE MOTEUR WEB A ETE TUE (plantage n°\(nbPlantages))")

        // Au-dela de deux tentatives on arrete : recharger en boucle ne ferait
        // que rejouer l'intro indefiniment, ce que l'utilisateur voit comme un
        // demarrage sans fin.
        guard nbPlantages <= 2 else {
            print("[ALAE] trop de plantages — rechargement automatique abandonne")
            return
        }

        // 04/09 : on relance TOUJOURS l'app complete — intro, soie, animations.
        // Le mode leger a ete supprime : il degradait l'app pour compenser les 3
        // filtres plein ecran, qui sont partis. Deux tentatives au maximum, puis
        // on s'arrete pour ne pas rejouer l'intro en boucle.
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

        // Partage d'une image (carte Sabah al-khayr, cartes de partage).
        // Le JS envoie un data URL base64 ; la Web Share API fichiers n'existe pas
        // dans une WKWebView, donc l'image doit passer par ici.
        if type == "shareImage" {
            let text = body["text"] as? String ?? ""
            let dataURL = body["image"] as? String ?? ""
            guard let comma = dataURL.firstIndex(of: ","),
                  let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]),
                                  options: .ignoreUnknownCharacters),
                  let image = UIImage(data: data) else {
                // Repli : on partage au moins le texte
                if !text.isEmpty {
                    DispatchQueue.main.async {
                        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                        if let pop = vc.popoverPresentationController {
                            pop.sourceView = self.webView
                            pop.sourceRect = CGRect(x: self.webView.bounds.midX, y: self.webView.bounds.midY, width: 0, height: 0)
                            pop.permittedArrowDirections = []
                        }
                        self.present(vc, animated: true)
                    }
                }
                return
            }
            DispatchQueue.main.async {
                var items: [Any] = [image]
                if !text.isEmpty { items.append(text) }
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
            AlaeReplanif.memoriser(body)        // ← permet de reposer les notifications sans la WebView
            ViewController.handleUpdateNotifications(body)
            AlaeReplanif.programmer()
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
    fileprivate static func adhanSound(for reciter: String) -> UNNotificationSound? {
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

    static func handleUpdateNotifications(_ body: [String: Any]) {
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
                let sound = ViewController.adhanSound(for: reciter)
                let center = UNUserNotificationCenter.current()
                let cal = Calendar.current
                let now = Date()

                // Adhan : à l'heure exacte de la prière.
                func contenu(_ label: String) -> UNMutableNotificationContent {
                    let c = UNMutableNotificationContent()
                    c.title = "آلَاء · \(label)"
                    c.body  = "حان وقت صلاة \(label) — \(city)"
                    c.sound = sound
                    // Marqueur lu au tap : c'est l'adhan, on peut jouer la version complete.
                    c.userInfo = ["genre": "adhan", "reciter": reciter]
                    return c
                }

                // Préavis : X minutes avant, son doux — jamais l'adhan,
                // sinon l'utilisateur croit que l'heure est déjà arrivée.
                func preavis(_ label: String) -> UNMutableNotificationContent {
                    let c = UNMutableNotificationContent()
                    c.title = "آلَاء · \(label)"
                    c.body  = "\(label) خلال \(minutes) دقيقة — \(city)"
                    c.sound = (reciter == "silent") ? nil : .default
                    // Pas de version complete au tap : la priere n'a pas encore commence.
                    c.userInfo = ["genre": "preavis", "reciter": reciter]
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
