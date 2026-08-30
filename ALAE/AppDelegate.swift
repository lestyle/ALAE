//
//  AppDelegate.swift
//  ALAE
//
//  Created by Hicham Darif on 16/05/2026.
//

import UIKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Delegue de notifications : AlaeNotifDelegate (defini dans ViewController.swift)
        // gere l'affichage au premier plan ET le tap sur la banniere, qui joue l'adhan
        // complet. Pose ici, avant tout le reste : si l'app est lancee PAR un tap sur
        // une notification, iOS livre l'evenement avant que ViewController.viewDidLoad
        // ne soit passe, et l'adhan ne partirait pas.
        UNUserNotificationCenter.current().delegate = AlaeNotifDelegate.shared

        // Adhan : enregistrement de la tache de replanification en arriere-plan.
        // iOS ne garde que 64 notifications en attente ; sans ce reveil periodique
        // l'adhan s'eteint au bout d'une a deux semaines si l'app n'est pas ouverte.
        // DOIT etre appele avant la fin du lancement, sinon iOS leve une exception.
        AlaeReplanif.enregistrer()

        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
}
