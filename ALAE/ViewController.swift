//
//  ViewController.swift
//  ALAE — v14 (WebView + notifications adhan + ALIMENTATION DU WIDGET via App Group)
//
//  1.0.8 — l'adhan sonne désormais à l'HEURE EXACTE de la prière.
//  Le préavis « X minutes avant » utilise un son doux, plus l'adhan.
//

import UIKit
import WebKit
import CoreLocation
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

    // 19/10 : bouton sous la notification du vendredi (ALAE).
    static let categorieSalawat = "alae-jumua-salat-cat"
    static let actionSalawat = "alae-action-salawat"
    static let ouvrirSalawat = Notification.Name("alaeOuvrirSalawat")
    static var salawatEnAttente = false

    static func enregistrerCategories() {
        let titre = "اللَّهُمَّ صَلِّ وَسَلِّمْ عَلَى نَبِيِّنَا مُحَمَّدٍ ﷺ"
        let action: UNNotificationAction
        if #available(iOS 15.0, *) {
            action = UNNotificationAction(identifier: actionSalawat, title: titre, options: [.foreground],
                                          icon: UNNotificationActionIcon(systemImageName: "sparkles"))
        } else {
            action = UNNotificationAction(identifier: actionSalawat, title: titre, options: [.foreground])
        }
        let cat = UNNotificationCategory(identifier: categorieSalawat, actions: [action], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([cat])
    }

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
        // 19/10 : notification du vendredi (salawat) — bouton ou toucher -> compteur salat ﷺ.
        if (info["genre"] as? String) == "jumua",
           response.actionIdentifier == AlaeNotifDelegate.actionSalawat ||
           (response.actionIdentifier == UNNotificationDefaultActionIdentifier &&
            response.notification.request.identifier == "alae-jumua-salat") {
            AlaeNotifDelegate.salawatEnAttente = true
            NotificationCenter.default.post(name: AlaeNotifDelegate.ouvrirSalawat, object: nil)
        }
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

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, CLLocationManagerDelegate {

    // App Group partagé avec le widget (doit être identique côté widget)
    private let appGroupID = "group.com.alae.misbaha.ALAE.shared"

    // Date de fin de la derniere intro (secondes depuis 1970). Voir loadView().
    static let bootAtKey = "alae.bootAt"
    // Copie durable du localStorage de la page (JSON). Voir loadView().
    static let storeKey = "alae.store"
    // 24/10 : copie DEDIEE du compteur (misbaha.v1), petite et ecrite tout de suite
    // dans un fichier. Le gros miroir ci-dessus (plusieurs Mo, cache du code compris)
    // pouvait rater les derniers dhikr si l'app etait fermee avant son ecriture.
    static let dhikrKey = "alae.dhikr"
    static var dhikrFile: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("alae-dhikr.json")
    }
    static func lireDhikr() -> String {
        if let f = dhikrFile, let s = try? String(contentsOf: f, encoding: .utf8), !s.isEmpty { return s }
        return UserDefaults.standard.string(forKey: dhikrKey) ?? ""
    }

    var webView: WKWebView!

    override func loadView() {
        let contentController = WKUserContentController()
        contentController.add(self, name: "alae")

        // 07/09 — ANTI-BOUCLE D'INTRO + PERSISTANCE DES REGLAGES, cote natif.
        // La page est chargee par loadFileURL : sous file:// WebKit lui donne une
        // origine opaque, et son localStorage n'est pas relu au chargement suivant.
        // Deux choses en dependaient : le garde anti-boucle de l'intro, qui ne
        // pouvait jamais s'armer, et TOUS les reglages (langue, theme, luminosite,
        // total des dhikr), perdus a chaque redemarrage. Les deux vivent desormais
        // dans UserDefaults, cote natif, et sont injectes AVANT le premier script.
        contentController.addUserScript(Self.scriptInjection())

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
        ReviewManager.noterPremierLancement()
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
        AlaeNotifDelegate.enregistrerCategories()
        NotificationCenter.default.addObserver(forName: AlaeNotifDelegate.ouvrirSalawat, object: nil, queue: .main) { [weak self] _ in
            self?.ouvrirSalawatSiBesoin(essai: 0)
        }

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
    /// 19/10 : passe le compteur sur la salat ﷺ quand la page est prete (intro comprise).
    func ouvrirSalawatSiBesoin(essai: Int) {
        guard AlaeNotifDelegate.salawatEnAttente, essai < 20 else { return }
        webView.evaluateJavaScript("window.__alaeOuvrirSalawat ? (window.__alaeOuvrirSalawat(), 'ok') : 'attente'") { [weak self] r, _ in
            if (r as? String) == "ok" { AlaeNotifDelegate.salawatEnAttente = false; return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.ouvrirSalawatSiBesoin(essai: essai + 1) }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.ouvrirSalawatSiBesoin(essai: 0) }
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

    // Valeurs natives injectees avant le premier script de la page.
    // 20/10 : fabrique a chaque chargement — avant, le script etait fige au
    // lancement, donc un rechargement apres plantage recevait l'ANCIEN bootAt
    // (intro rejouee) et l'ancien store (reglages de la session perdus).
    // Passe par un tableau JSON : JSONSerialization echappe guillemets, retours
    // a la ligne et accents pour nous. Concatener la chaine brute casserait le JS.
    static func scriptInjection() -> WKUserScript {
        let bootAt = UserDefaults.standard.double(forKey: bootAtKey)
        let store = UserDefaults.standard.string(forKey: storeKey) ?? "{}"
        let litteral = (try? JSONSerialization.data(withJSONObject: [store, lireDhikr()]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"{}\",\"\"]"
        return WKUserScript(
            source: """
            window.__alaeBootAt = \(Int(bootAt * 1000));
            window.__alaeStore = \(litteral)[0];
            window.__alaeDhikr = \(litteral)[1];
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    // Nombre de fois que le moteur web a ete tue depuis le lancement.
    private var nbPlantages = 0

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        nbPlantages += 1
        print("[ALAE] LE MOTEUR WEB A ETE TUE (plantage n°\(nbPlantages))")

        // 06/09 : UNE seule tentative. Le HTML signale la fin de son intro a Swift
        // (message 'bootAt'), qui la retient dans UserDefaults et la reinjecte au
        // chargement suivant : ce rechargement saute l'intro et le Dou'a et repart
        // directement sur l'app — plus de boucle visible.
        // 20/10 : 3 tentatives (au lieu d'1 puis ecran noir), toutes SANS intro.
        guard nbPlantages <= 3 else {
            print("[ALAE] trop de plantages — rechargement automatique abandonne")
            return
        }

        // On marque l'intro comme "vient d'avoir lieu" puis on reinjecte des
        // valeurs fraiches : la page relancee saute l'intro et le Dou'a et repart
        // directement sur la page principale, avec les reglages de la session.
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.bootAtKey)
        let cc = webView.configuration.userContentController
        cc.removeAllUserScripts()
        cc.addUserScript(Self.scriptInjection())
        webView.reload()
    }

    // 20/10 : boussole de la Qibla. Sans cette methode, WebKit affichait SA fenetre
    // "/private/var/containers/.../Misbaha-Standalone.html veut acceder au mouvement"
    // en plus de celle de la position. On accorde directement : une seule fenetre (iOS).
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView,
                 requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
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

    // MARK: - Position native (CoreLocation)
    private lazy var gestionnaireLoc: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return m
    }()
    private var locDemandee = false

    // Cible minimale iOS 16.2 : la propriete d'instance existe partout, l'ancienne
    // methode de classe (depreciee depuis iOS 14) n'a plus lieu d'etre.
    private func statutLoc() -> CLAuthorizationStatus {
        return gestionnaireLoc.authorizationStatus
    }

    private func demanderPosition() {
        DispatchQueue.main.async {
            switch self.statutLoc() {
            case .notDetermined:
                self.locDemandee = true
                self.gestionnaireLoc.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                self.locDemandee = true
                self.gestionnaireLoc.requestLocation()
            default:
                self.renvoyerErreurPosition("refuse")
            }
        }
    }

    private func renvoyerPosition(_ l: CLLocation) {
        let js = "if(window.__alaeLocOK)window.__alaeLocOK(\(l.coordinate.latitude),\(l.coordinate.longitude));"
        DispatchQueue.main.async { self.webView.evaluateJavaScript(js, completionHandler: nil) }
    }

    private func renvoyerErreurPosition(_ raison: String) {
        let propre = raison.replacingOccurrences(of: "'", with: " ")
        let js = "if(window.__alaeLocErr)window.__alaeLocErr('\(propre)');"
        DispatchQueue.main.async { self.webView.evaluateJavaScript(js, completionHandler: nil) }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last else { return }
        print("[ALAE] position native obtenue")
        renvoyerPosition(l)
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        print("[ALAE] position native indisponible : \(error.localizedDescription)")
        renvoyerErreurPosition(error.localizedDescription)
    }

    func locationManager(_ m: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        guard locDemandee else { return }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: m.requestLocation()
        case .denied, .restricted: renvoyerErreurPosition("refuse")
        default: break
        }
    }

    // MARK: - JS → Swift bridge
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        // 07/09 — POSITION NATIVE. Avant, le HTML appelait navigator.geolocation :
        // dans une WKWebView file:// WebKit affiche SA fenetre, qui montre
        // "/private/var/containers/.../Misbaha-Standalone.html" au lieu du nom de
        // l'app, et la reaffiche a chaque appel. On passe par CoreLocation : iOS
        // montre sa fenetre standard, une seule fois, avec le nom de l'app.
        if type == "location" {
            demanderPosition()
            return
        }

        // Le HTML signale que son intro vient de se terminer : on retient l'instant
        // cote natif pour qu'un rechargement apres plantage saute l'intro et le Dou'a.
        if type == "bootAt" {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.bootAtKey)
            return
        }

        // La page renvoie son localStorage complet a chaque modification. On le garde
        // ici : c'est la seule copie qui survit a un redemarrage (voir loadView()).
        if type == "store" {
            if let data = body["data"] as? String {
                UserDefaults.standard.set(data, forKey: Self.storeKey)
            }
            return
        }

        // 24/10 : chaque dhikr compte. Ecriture atomique immediate du compteur.
        if type == "dhikrStore" {
            if let data = body["data"] as? String, !data.isEmpty {
                if let f = Self.dhikrFile { try? data.write(to: f, atomically: true, encoding: .utf8) }
                UserDefaults.standard.set(data, forKey: Self.dhikrKey)
            }
            return
        }

        // 28/10 : une serie de 33 terminee — ReviewManager decide s'il demande une note.
        // 28/10 : l'utilisateur choisit l'icone de l'app (Reglages). nil = icone principale.
        if type == "setIcon" {
            let nom = body["name"] as? String
            let cible: String? = (nom == nil || nom == "" || nom == "AppIcon") ? nil : nom
            guard UIApplication.shared.supportsAlternateIcons,
                  UIApplication.shared.alternateIconName != cible else { return }
            UIApplication.shared.setAlternateIconName(cible) { e in
                if let e = e { print("[Icône] erreur : \(e.localizedDescription)") }
            }
            return
        }

        // 29/10 : serie de jours + rappels intelligents (StreakManager.swift).
        if type == "streakSync" {
            StreakManager.recevoir(body)
            return
        }

        // 29/10 : serie de 3 jours ou objectif du jour atteint -> fenetre de note Apple.
        if type == "reviewMoment" {
            ReviewManager.momentFort(in: view.window?.windowScene)
            return
        }

        if type == "roundDone" {
            ReviewManager.serieTerminee(in: view.window?.windowScene)
            return
        }

        // 28/10 : dernier jour d'un defi reussi (ex. 30e jour d'Istighfar).
        if type == "challengeDone" {
            ReviewManager.defiTermine(in: view.window?.windowScene)
            return
        }

        // 28/10 : « Noter ALAE » — ouvre la fiche App Store sur l'ecriture d'un avis.
        if type == "openURL" {
            if let s = body["url"] as? String, let u = URL(string: s),
               u.scheme == "https" || u.scheme == "itms-apps" {
                UIApplication.shared.open(u)
            }
            return
        }

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

        // 14/10 : rappels des adhkar du matin et du soir (ALAE).
        if type == "adhkarReminders" {
            ViewController.memoriserAdhkar(body)
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                DispatchQueue.main.async { ViewController.planifierAdhkar() }
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

    // MARK: - Rappels adhkar matin / soir (14/10)
    private static let cleAdhkar = "alae.adhkarRappels"

    static func memoriserAdhkar(_ body: [String: Any]) {
        var d: [String: Any] = [:]
        for k in ["matin", "soir", "jumua"] { if let v = body[k] as? [String: Any] { d[k] = v } }
        if let t = body["textes"] as? [String: String] { d["textes"] = t }
        UserDefaults.standard.set(d, forKey: cleAdhkar)
    }

    static func planifierAdhkar() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["alae-adhkar-matin", "alae-adhkar-soir", "alae-jumua-kahf", "alae-jumua-salat"])
        guard let d = UserDefaults.standard.dictionary(forKey: cleAdhkar) else { return }
        let textes = d["textes"] as? [String: String] ?? [:]
        for k in ["matin", "soir"] {
            guard let r = d[k] as? [String: Any], (r["enabled"] as? Bool) == true,
                  let h = r["hour"] as? Int, let m = r["minute"] as? Int else { continue }
            let c = UNMutableNotificationContent()
            c.title = textes[k + "Titre"] ?? (k == "matin" ? "أذكار الصباح" : "أذكار المساء")
            c.body = textes[k + "Corps"] ?? ""
            c.sound = .default
            c.userInfo = ["genre": "adhkar", "route": "adhkar"]
            var dc = DateComponents(); dc.hour = h; dc.minute = m
            center.add(UNNotificationRequest(identifier: "alae-adhkar-\(k)", content: c,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)))
        }
        // 19/10 : rappels du vendredi (ALAE) — jeudi apres le Maghrib : Al-Kahf ; vendredi matin : salawat.
        // Repetes chaque semaine ; l'heure du jeudi est recalculee par l'app a chaque ouverture.
        if let j = d["jumua"] as? [String: Any], (j["enabled"] as? Bool) == true {
            let rappels: [(id: String, cle: String, jour: Int, h: Int, m: Int)] = [
                ("alae-jumua-kahf",  "kahf",  5, j["kahfHour"] as? Int ?? 19,  j["kahfMinute"] as? Int ?? 0),
                ("alae-jumua-salat", "salat", 6, j["salatHour"] as? Int ?? 10, j["salatMinute"] as? Int ?? 0)
            ]
            for r in rappels {
                let c = UNMutableNotificationContent()
                c.title = textes[r.cle + "Titre"] ?? (r.cle == "kahf" ? "سُورَةُ الكَهْف" : "جُمُعَة مُبَارَكَة")
                c.body = textes[r.cle + "Corps"] ?? ""
                c.sound = .default
                c.userInfo = ["genre": "jumua", "route": "compteur"]
                if r.cle == "salat" { c.categoryIdentifier = AlaeNotifDelegate.categorieSalawat }
                var dc = DateComponents(); dc.weekday = r.jour; dc.hour = r.h; dc.minute = r.m
                center.add(UNNotificationRequest(identifier: r.id, content: c,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)))
            }
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
        // 14/10 : la ligne du dessus efface TOUT, y compris les rappels d'adhkar :
        // on les repose aussitot (2 notifications, repetees chaque jour).
        ViewController.planifierAdhkar()
        // 29/10 : idem pour les rappels de serie (sinon effaces a chaque recalcul des horaires).
        StreakManager.planifier()

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
