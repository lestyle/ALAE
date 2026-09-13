# ALAE — آلَاء

> Misbaha digitale & compagnon de prière pour iOS.

ALAE enveloppe une **misbaha interactive** (chapelet de dhikr) dans une esthétique
soie noire & or : horaires de prière exacts, **adhan en notification** avec le
réciteur de son choix, préavis réglable, widget, statistiques, et une bibliothèque
d'adhkar personnalisable.

---

## ✨ Fonctionnalités

- **Compteur de dhikr** : tap = +1 avec retour haptique et son de grain,
  glisser pour changer de dhikr, appui long pour réinitialiser,
  mode « yeux fermés » avec synthèse vocale arabe.
- **Bibliothèque d'adhkar** : textes classiques + dhikrs personnalisés
  (ajout, édition, favoris, persistance locale).
- **Adhan aux heures exactes** : calendrier de 14 jours mis en cache,
  planifié en notifications locales datées (pas de répétition quotidienne
  figée). **6 réciteurs** : hadioui, karaca, kouchi, kzabri, mecca, younes.
- **Préavis « X minutes avant »** avec son doux, réglable par l'utilisateur.
- **Widget (ALAEWidget2)** : horaires du jour, date hijri, ville,
  compteur du jour — partagés via App Group.
- **Statistiques** : séries (streaks), sessions, historique.
- **Thèmes** : gold, bordeaux, rose, nuit, bahrayn, koutoubia, amouage, copper,
  chacun avec trois crans de luminosité (nature, 70 %, 20 %).
- **Intro calligraphique** : Bismillah + verset d'Ar-Rahman (QPC),
  effet « or liquide » sur le mot آلَاء.

## 🏗️ Architecture

Coquille **Swift/UIKit native** autour d'une app **React 18** embarquée :

```
┌──────────────────────────── iOS (Swift) ───────────────────────────┐
│  ViewController (WKWebView)                                        │
│  ├─ Charge Misbaha-Standalone.html  ← l'app React, JSX via Babel   │
│  ├─ WKUserScript (atDocumentStart) : window.__alaeStore / BootAt   │
│  ├─ Pont JS ↔ Swift (messageHandlers.alae) :                       │
│  │   haptiques · partage · notifications · géoloc · widget         │
│  └─ AlaeAdhanPlayer  : adhan complet au tap (session .playback)    │
│                                                                    │
│  AppDelegate                                                       │
│  ├─ UNUserNotificationCenter.delegate = AlaeNotifDelegate          │
│  └─ AlaeReplanif.enregistrer()  → BGAppRefreshTask (12 h)          │
│                                                                    │
│  Widget ALAEWidget2 ← App Group « be.lestyle.alae.group »          │
└────────────────────────────────────────────────────────────────────┘
```

### Pourquoi React dans une WKWebView ?

L'interface (thèmes, animations, compteur, stats) itère vite en JSX,
tandis que les primitives natives restent en Swift : notifications exactes,
haptiques, géolocalisation, widget, audio en mode silencieux.

## 🔔 Système de notifications (le cœur de l'app)

iOS ne conserve que **64 notifications locales** en attente. ALAE :

1. Pose ~60 notifications **datées** (14 jours d'horaires = fenêtre glissante
   de ~6 jours : 5 prières × adhan + préavis par jour).
2. **Replanifie en arrière-plan** via `BGAppRefreshTask` (réveil ~12 h,
   rejoue le dernier payload mémorisé) + à chaque retour au premier plan.
3. Son de notification **≤ 30 s** (`adhan-<reciter>-notif.caf`) ; au tap,
   l'app joue le **MP3 complet** — même en mode silencieux (`.playback`).
4. Aucune requête réseau au démarrage : polices et scripts sont dans le bundle.
5. Toutes les dates sont calculées en **calendrier grégorien forcé**
   (`Calendar(identifier: .gregorian)`) : `Calendar.current` suit la locale
   de l'appareil et serait islamique sur les devices arabes.

### Résilience WebKit

- Le moteur WKWebView est tué par iOS en tâche de fond → au retour, la webview
  est rechargée (max 2×) sans relancer l'intro, grâce à `bootAt` persisté.
- Le `localStorage` d'une page `file://` a une origine opaque : chaque écriture
  est **miroirée dans UserDefaults** (`window.__alaeStore`) et réinjectée au
  démarrage — rien n'est perdu entre les rechargements.

## 🗂️ Structure du projet

```
ALAE/
├── ViewController.swift      # coquille : WebView, pont JS↔Swift, notifications
├── AppDelegate.swift         # délégué notifications + enregistrement BG task
├── SceneDelegate.swift       # cycle de vie, rechargement anti-plantage WebKit
├── Misbaha-Standalone.html   # l'app React complète (JSX compilé au vol)
├── ALAEWidget2/              # extension widget (SwiftUI)
├── assets/                   # images, masques, calligraphies
├── fonts/                    # Amiri, Amiri Quran, Aref Ruqaa,
│                             # Scheherazade New, Reem Kufi, QPC/QCF (coranique)
├── CormorantGaramond-*.ttf   # à la racine, pas dans fonts/
├── adhan-*.mp3               # adhans complets (lecture in-app)
├── adhan-*-notif.caf         # extraits ≤ 30 s (sons de notification)
└── ALAE.xcodeproj
```

## 🌐 Données

- **Horaires de prière** : API [aladhan.com](https://aladhan.com), méthode 3
  (Muslim World League), cache 14 jours, fuseau local.
- **Position** : `CLLocationManager` natif (pas `navigator.geolocation`,
  dont la bannière WebKit afficherait un chemin `file://`).
- **i18n** : ar / fr / en / nl (interface principalement arabe).

## ⚙️ Prérequis & build

- Xcode 15+, cible **iOS 16.2+**
- Capacité **Background Modes** : Background fetch + Background processing
- `Info.plist` → `BGTaskSchedulerPermittedIdentifiers` :
  `be.lestyle.alae.replanif`
- App Group : `be.lestyle.alae.group` (app + widget)

## 🔒 Sécurité

> ⚠️ Ne jamais commiter la clé `AuthKey_*.p8` (Apple Push/Notifier).
> La garder hors du dépôt et référencer les variables d'environnement
> dans les CI (ex. Codemagic).

## 🗺️ Pistes d'amélioration

- Prioriser l'adhan sur le préavis quand on approche du plafond de 64
  (aujourd'hui le plafond est fixé à 60 et coupe les deux indifféremment).
- Réinitialisation du compteur widget à minuit (côté extension).
- Le fallback quotidien (`repeats: true`) reste figé sur les horaires du jour :
  chemin secondaire, jamais atteint tant que l'API répond.

---

*ALAE — « يَا مُقَلِّبَ الْقُلُوبِ »*
