# Vue « Résumé » — cahier des charges perso

Fork de [exelban/stats](https://github.com/exelban/stats). Ajout d'une vue personnelle
qui résume l'état de l'ordinateur (CPU / GPU / RAM) en un seul bouton de la barre de menus.

## Objectif

**Deux boutons** dans la barre de menus (un par page) :
- Bouton 1 « Résumé » → CPU / GPU / RAM en un coup d'œil.
- Bouton 2 « Tableau de bord » → tout ce que Stats a d'utile.

## Ce que je veux (cahier des charges)

### Boutons dans la barre de menus
- [x] **Deux icônes distinctes** : « Résumé » (compteur de vitesse) et
      « Tableau de bord » (grille).
- [x] Chaque icône s'affiche / se masque depuis les réglages.

### Page 1 — « Résumé » (CPU / GPU / RAM)
- [x] **Que des données texte, collées à gauche**, qui prennent toute la largeur
      (plus de jauge ni de graphe temps réel).
- [x] Pour chaque module : nom (en couleur) + `%` + chiffres (temp, cœurs, Go…).
- [x] **Top apps** : l'application la plus gourmande (CPU en %, RAM en Go),
      activable/désactivable dans les réglages.
- [x] **Bouton « Détails »** par module : ouvre la page complète officielle.
- [x] Modules affichés (CPU / GPU / RAM) choisis dans les réglages.

### Page 2 — tableau de bord complet
- [x] Une page qui résume **toutes** les infos intéressantes de l'ordinateur.
- [x] **En-tête système** : modèle du Mac · version macOS · nombre de cœurs · uptime.
- [x] **Même style / même UX pour toutes les sections** : chaque module (CPU/GPU/RAM
      inclus) est présenté via son « portal » officiel → cartes homogènes et alignées.
- [x] Grille de cartes sur **2 ou 3 colonnes** (au choix).

### Réglages — gérer les deux vues
- [x] Entrée **« Résumé »** dans la barre latérale des réglages de Stats
      (juste sous « Dashboard »), qui gère **tout** :
  - Icônes de la barre de menus (bouton 1 / bouton 2).
  - Page 1 : modules affichés + « app la plus gourmande ».
  - Page 2 : disposition (2/3 colonnes), infos système,
    et un interrupteur par section (module) pour ajouter / enlever une carte.
- Clés `Store.shared` : `resume_button1_visible`, `resume_button2_visible`,
  `resume_page1_<module>_visible`, `resume_page1_topapps`,
  `resume_dashboard_<module>_visible`, `resume_dashboard_columns`,
  `resume_dashboard_sysinfo`.

### Limite connue (données privées)
Réseau / Batterie / Capteurs / Bluetooth n'exposent pas leurs données en API
publique (`Battery_Usage` n'est même pas `public`). Impossible donc de faire des
cartes « maison » riches pour eux → on réutilise les `portals` officiels pour
**tous** les modules, ce qui donne en prime une UX homogène.

### Idées / à voir plus tard
- [ ] Choisir le nombre de « top apps » affichées (1, 2, 3…).
- [ ] Couleurs / icônes personnalisables.
- [ ] Réordonner les sections de la page 2 (glisser-déposer).

## Où c'est dans le code

Quasi tout est isolé pour limiter les conflits lors des mises à jour du projet officiel :
- `Stats/Views/CombinedView.swift` → classes `ResumeView` (2 boutons), `ResumePopup`,
  `ModuleSummaryRow`, `DashboardPopup`, `ResumeSettingsView`
  + l'enum `ResumeConfig` (tous les réglages) + imports `CPU`/`GPU`/`RAM`.
- `Stats/AppDelegate.swift` → une seule ligne : `internal var resumeView: ResumeView = ResumeView()`.
- `Stats/Views/Settings.swift` → 4 petits ajouts (commentés « ajout perso ») pour
  brancher l'entrée « Résumé » de la barre latérale sur `ResumeSettingsView`.
- `Kit/module/popup.swift` → le header du popup se redimensionne maintenant avec la
  fenêtre (titre recentré + boutons sur les côtés) pour les popups larges comme le
  « Tableau de bord ». Correctif générique, bénéficie aussi aux autres modules.
- Aucune modification des fichiers des modules : les valeurs sont lues via `DB.shared` (API publique).

## Tester

```bash
cd ~/Library/Mobile\ Documents/com~apple~CloudDocs/_PROG/Stats_perso
killall Stats 2>/dev/null                       # quitte le Stats installé
open "build/Build/Products/Debug/Stats.app"     # lance la version de test
```

Recompiler après une modif :

```bash
xcodebuild -scheme Stats -configuration Debug -derivedDataPath build \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
```

Revenir au Stats normal : `killall Stats 2>/dev/null && open /Applications/Stats.app`

## Workflow git

- Branche perso : `resume` (les modifs vivent ici, pas sur `master`).
- Remotes : `origin` = mon fork `gt26O/stats`, `upstream` = `exelban/stats` (officiel).

```bash
# Sauvegarder mes modifs sur mon fork
git push -u origin resume

# Récupérer une mise à jour du projet officiel
git fetch upstream
git rebase upstream/master
git push --force-with-lease origin resume

# Proposer ma fonctionnalité au projet officiel (optionnel)
gh pr create --repo exelban/stats --base master --head gt26O:resume
```

## Limitation connue

La page 2 et l'option native « Combined modules » de Stats partagent les mêmes vues
internes (`portal`) → éviter d'activer les deux en même temps.
