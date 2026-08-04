//
//  ViewController.swift
//  ALAE — v12 (avec notifications + adhan)
//

import UIKit
import WebKit
import UserNotifications
import AVFoundation

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
        webView.allowsBackForwardNavigationGestures = false  // Désactive le swipe iOS "retour" qui sortait de l'app
        // Plein écran edge-to-edge : empêche iOS d'ajouter un encart de safe-area
        // (sinon barre sombre en haut/bas, le fond ne remplit pas tout l'écran).
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.verticalScrollIndicatorInsets = .zero
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.043, green: 0.051, blue: 0.063, alpha: 1.0)
        view = webView
    }

    // Overlay natif affiché pendant le chargement du HTML — disparaît en fondu dès que la page est prête
    private var splashOverlay: UIView?

    private func showSplash() {
        let bg = UIColor(red: 0.043, green: 0.051, blue: 0.063, alpha: 1.0)
        let gold = UIColor(red: 0.784, green: 0.725, blue: 0.357, alpha: 1.0)

        let overlay = UIView(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = bg

        // Halo doré derrière le texte
        let halo = UIView()
        halo.backgroundColor = UIColor(red: 0.784, green: 0.725, blue: 0.357, alpha: 0.08)
        halo.layer.cornerRadius = 80
        halo.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(halo)

        // Texte آلاء centré
        let label = UILabel()
        label.text = "آلاء"
        label.textColor = gold
        label.font = UIFont(name: "AmiriQuran", size: 56) ?? UIFont(name: "Amiri", size: 56) ?? UIFont.systemFont(ofSize: 56, weight: .thin)
        label.textAlignment = .center
        label.alpha = 1.0
        label.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(label)

        // Ligne dorée sous le texte
        let line = UIView()
        line.backgroundColor = gold.withAlphaComponent(0.3)
        line.layer.cornerRadius = 1
        line.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(line)

        NSLayoutConstraint.activate([
            halo.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            halo.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -10),
            halo.widthAnchor.constraint(equalToConstant: 160),
            halo.heightAnchor.constraint(equalToConstant: 160),

            label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -10),

            line.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            line.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 16),
            line.widthAnchor.constraint(equalToConstant: 48),
            line.heightAnchor.constraint(equalToConstant: 1.5)
        ])

        view.addSubview(overlay)
        splashOverlay = overlay

        // Pulsation douce du halo UNIQUEMENT — label reste stable
        UIView.animate(withDuration: 2.0, delay: 0, options: [.repeat, .autoreverse, .allowUserInteraction], animations: {
            halo.backgroundColor = UIColor(red: 0.784, green: 0.725, blue: 0.357, alpha: 0.18)
            halo.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        }, completion: nil)
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
        showSplash()
        if let url = Bundle.main.url(forResource: "Misbaha-Standalone", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        // Filet de sécurité — cache le splash après 4s max même si didFinish tarde
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.hideSplash()
        }
        UNUserNotificationCenter.current().delegate = (UIApplication.shared.delegate as? UNUserNotificationCenterDelegate)
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideSplash()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        hideSplash()
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

        if type == "updateNotifications" {
            handleUpdateNotifications(body)
        }
    }

    // MARK: - Notifications
    private func handleUpdateNotifications(_ body: [String: Any]) {
        let enabled    = body["enabled"] as? Bool ?? false
        let minutes    = body["minutesBefore"] as? Int ?? 5
        let reciter    = body["reciter"] as? String ?? "rouchi"
        let timings    = body["timings"] as? [String: String] ?? [:]
        let city       = body["city"] as? String ?? ""

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
                        let soundName = "adhan-\(reciter).caf"  // .caf or .mp3 in bundle
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
}
