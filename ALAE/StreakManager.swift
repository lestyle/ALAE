//
//  StreakManager.swift
//  ALAE
//
//  29/10 : series de jours (streaks) + rappels intelligents.
//  Notifications LOCALES (aucun serveur, aucun compte) : la page envoie l'etat
//  de la serie a chaque activite, on repose les rappels. Si l'utilisateur
//  revient avant l'heure, ils sont remplaces et ne partent jamais.
//

import Foundation
import UserNotifications

enum StreakManager {
    private static let cle = "alae.streak.dernier"
    private static let ids = ["alae-serie-danger", "alae-objectif", "alae-matin", "alae-retour-3", "alae-retour-7"]

    /// Message "streakSync" venu du HTML : { streak, today, goal, textes{...} }
    static func recevoir(_ body: [String: Any]) {
        var d = body
        d.removeValue(forKey: "type")
        UserDefaults.standard.set(d, forKey: cle)
        // 29/10 : serie partagee avec le widget (App Group). L'affichage se fera en 1.0.27.
        UserDefaults(suiteName: "group.com.alae.misbaha.ALAE.shared")?.set(d["streak"] as? Int ?? 0, forKey: "streakDays")
        planifier()
    }

    static func planifier() {
        guard let d = UserDefaults.standard.dictionary(forKey: cle) else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { reglages in
            switch reglages.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                poserTout(d)
            case .notDetermined:
                // Provisoire : livraison discrete, AUCUNE fenetre d'autorisation.
                // La vraie demande reste celle de l'adhan / des adhkar.
                center.requestAuthorization(options: [.alert, .sound, .badge, .provisional]) { ok, _ in
                    if ok { poserTout(d) }
                }
            default:
                break
            }
        }
    }

    private static func rappelMatinActif() -> Bool {
        guard let a = UserDefaults.standard.dictionary(forKey: "alae.adhkarRappels"),
              let m = a["matin"] as? [String: Any] else { return false }
        return (m["enabled"] as? Bool) == true
    }

    private static func poserTout(_ d: [String: Any]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)

        let serie = d["streak"] as? Int ?? 0
        let duJour = d["today"] as? Int ?? 0
        let objectif = d["goal"] as? Int ?? 100
        let fait = duJour > 0
        let t = d["textes"] as? [String: String] ?? [:]
        let cal = Calendar.current
        let now = Date()

        func a(_ jours: Int, _ h: Int, _ m: Int) -> Date? {
            guard let j = cal.date(byAdding: .day, value: jours, to: cal.startOfDay(for: now)) else { return nil }
            return cal.date(bySettingHour: h, minute: m, second: 0, of: j)
        }
        func poser(_ id: String, _ cle: String, _ date: Date?) {
            guard let titre = t[cle + "Titre"], let corps = t[cle + "Corps"],
                  let date = date, date > now.addingTimeInterval(60) else { return }
            let c = UNMutableNotificationContent()
            c.title = titre
            c.body = corps
            c.sound = .default
            c.threadIdentifier = "alae-serie"
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trig = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: c, trigger: trig))
        }

        // 1. Serie en danger : 20h30 le premier jour sans dhikr (22h30 si 20h30 est passe).
        if serie > 0 {
            if fait {
                poser("alae-serie-danger", "danger", a(1, 20, 30))
            } else if let s = a(0, 20, 30), s > now {
                poser("alae-serie-danger", "danger", s)
            } else {
                poser("alae-serie-danger", "danger", a(0, 22, 30))
            }
        }
        // 2. Objectif commence mais pas fini : 19h.
        if fait && duJour < objectif {
            poser("alae-objectif", "objectif", a(0, 19, 0))
        }
        // 3. Dhikr du matin, seulement si le rappel adhkar du matin n'est pas deja actif.
        if !rappelMatinActif() {
            poser("alae-matin", "matin", a(1, 7, 30))
        }
        // 4. Retour apres absence : J+3 (13:28) et J+7 (57:16) (annules des que l'app est rouverte).
        poser("alae-retour-3", "retour", a(3, 18, 0))
        poser("alae-retour-7", "retour7", a(7, 18, 0))
    }
}
