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
