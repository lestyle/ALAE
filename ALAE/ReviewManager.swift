import UIKit
import StoreKit

/// Demande de note App Store — ALAE.
/// L'app est en UIKit + WKWebView : pas de @AppStorage (reserve aux vues SwiftUI),
/// on passe par UserDefaults. Le JS envoie { type: "roundDone" } a chaque serie terminee.
enum ReviewManager {
    private static let d = UserDefaults.standard
    private static let kRounds  = "alae.review.completedRounds"
    private static let kFirst   = "alae.review.firstLaunch"
    private static let kVersion = "alae.review.lastReviewVersion"

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// A appeler une fois au lancement (viewDidLoad) : enregistre la date d'installation.
    static func noterPremierLancement() {
        if d.double(forKey: kFirst) == 0 {
            d.set(Date().timeIntervalSince1970, forKey: kFirst)
        }
    }

    static func shouldAsk() -> Bool {
        noterPremierLancement()
        let jours = (Date().timeIntervalSince1970 - d.double(forKey: kFirst)) / 86400
        return d.integer(forKey: kRounds) >= 3      // au moins 3 series terminees
            && jours >= 2                            // installee depuis 2 jours
            && d.string(forKey: kVersion) != version // une seule fois par version
    }

    static func serieTerminee(in scene: UIWindowScene?) {
        d.set(d.integer(forKey: kRounds) + 1, forKey: kRounds)
        guard shouldAsk(), let scene = scene else { return }
        demander(in: scene)
    }

    /// Fin d'un defi : l'engagement est prouve (7 a 40 jours), on ne garde que
    /// la regle « une fois par version ».
    static func defiTermine(in scene: UIWindowScene?) {
        guard d.string(forKey: kVersion) != version, let scene = scene else { return }
        demander(in: scene)
    }

    /// 29/10 : serie de 3 jours ou objectif atteint. Installee depuis 2 jours minimum,
    /// une fois par version.
    static func momentFort(in scene: UIWindowScene?) {
        noterPremierLancement()
        let jours = (Date().timeIntervalSince1970 - d.double(forKey: kFirst)) / 86400
        guard jours >= 2, d.string(forKey: kVersion) != version, let scene = scene else { return }
        demander(in: scene)
    }

    /// Apple affiche la fenetre au plus 3 fois par an et peut decider de ne rien montrer.
    private static func demander(in scene: UIWindowScene) {
        d.set(version, forKey: kVersion)
        // Attendre la fin de l'animation des 33 (colombes, petales…).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            AppStore.requestReview(in: scene) // iOS 16+ (cible minimum 16.2) — fonction moderne
        }
    }
}
