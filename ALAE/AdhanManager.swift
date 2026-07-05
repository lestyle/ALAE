//
//  AdhanManager.swift
//  ALAE — lecture de l'adhan COMPLET à l'heure de chaque prière
//
//  Technique (comme les vraies apps d'adhan) :
//   • une session audio en catégorie .playback (autorise l'audio en arrière-plan)
//   • un lecteur "keep-alive" qui joue un silence en boucle → garde l'app vivante
//     en arrière-plan pour que le minuteur puisse déclencher l'adhan à l'heure
//   • à l'heure exacte de chaque prière → lecture de adhan-<reciter>.mp3 (complet)
//
//  ⚠️ Limite iOS honnête : si l'utilisateur FERME l'app en la balayant
//     (force-quit), iOS coupe l'audio d'arrière-plan → l'adhan complet ne se
//     jouera pas. Dans ce cas seule la notification (≤30s) sonne. C'est une
//     limite d'Apple, aucune app ne la contourne.
//
//  PRÉREQUIS XCODE (voir ADHAN-COMPLET-XCODE.md) :
//   1. Signing & Capabilities → + Capability → Background Modes → cocher
//      "Audio, AirPlay, and Picture in Picture".
//   2. Ajouter au bundle : silence.caf + les adhan-<reciter>.mp3 (complets).
//

import Foundation
import AVFoundation
import UIKit

final class AdhanManager: NSObject {

    static let shared = AdhanManager()

    private var adhanPlayer: AVAudioPlayer?
    private var keepAlivePlayer: AVAudioPlayer?
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

        startKeepAlive()      // garde l'app vivante en arrière-plan
        scheduleRemainingToday()
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
        guard let url = Bundle.main.url(forResource: "silence", withExtension: "caf") else {
            print("[Adhan] silence.caf introuvable dans le bundle")
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

    func playAdhan() {
        // mp3 complet en priorité, sinon .caf si présent.
        let url = Bundle.main.url(forResource: "adhan-\(reciter)", withExtension: "mp3")
               ?? Bundle.main.url(forResource: "adhan-\(reciter)", withExtension: "caf")
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
