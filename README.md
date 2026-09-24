# rsg_chest — Coffres à code & perquisition (RSG Core / RedM)

Coffres posables avec **code secret**, placement type **gizmo**, sauvegarde **SQL**, et **perquisition** pour les forces de l'ordre.

## Fonctionnalités
- Item utilisable → placement du prop fantôme qui suit la caméra, avec axes X/Y/Z affichés
  - `Q/E` rotation · `Flèches` déplacement fin · `PgUp/PgDn` hauteur · `R` poser au sol · `G` figer · `SHIFT` rapide · `ENTRÉE` valider · `RETOUR` annuler
  - Gizmo externe optionnel (`Config.Placement.ExternalGizmo`) pour un réglage 3 axes complet
- Interface **cryptex à molettes** en HTML (modèle N°05) pour poser, ouvrir, ramasser et changer le code
  - molette de la souris ou `▲▼` pour tourner, chiffres du clavier pour saisir, `←→` pour changer de molette, `Entrée` valider, `Échap` annuler
  - nombre de molettes = `Config.Code.Length` (4 par défaut) ; `Config.Code.UseNui = false` pour revenir à la fenêtre ox_lib
- Code défini à la pose (haché côté serveur, jamais envoyé au client)
- Anti-bruteforce : X essais puis serrure bloquée, propriétaire prévenu
- Propriétaire : changer le code, ramasser le coffre (vide), voir l'historique
- Forces de l'ordre (jobs + grade configurables, en service) :
  - **Perquisitionner** : fouille sans code (barre de progression vérifiée côté serveur)
  - **Saisir** : retire le coffre (grade minimum configurable)
  - **Historique** : toutes les actions (pose, ouvertures, codes faux, fouilles…)
- **Partage** : le propriétaire donne l'accès sans code à des joueurs proches, à tout son gang ou à tout son métier (ranch, commerce…)
- **Crochetage** (item `lockpick`) : mini-jeu sur les molettes du cryptex. Tournez jusqu'au déclic (la molette vibre), bloquez avec Espace.
  Une erreur fait glisser le crochet (la dernière molette se débloque) et peut le casser. Temps limité, alerte possible au shérif.
- **Dynamite** (item `dynamite`) : mèche de X secondes, explosion, alerte la loi. Le coffre éventré est ouvert à tous pendant X minutes puis détruit.
- **Mandats** : un grade supérieur délivre un mandat pour un coffre, pour le propriétaire (tous ses coffres) ou pour un citoyen.
  Sans mandat valide, pas de fouille ni de saisie. `/mandat` pour en délivrer, `/mandats` pour la liste et la révocation.
- **Règles de perquisition** : nombre minimum d'agents en service à proximité, délai entre deux fouilles d'un même coffre
- **Coffres abandonnés** : supprimés automatiquement si le propriétaire ne s'est pas connecté depuis X jours (`/chestclean` pour lancer à la main)
- Logs SQL + webhook Discord optionnel
- Interaction via prompt natif RedM ou `rsg-target` / `ox_target`
- Commandes admin : `/chestnearest`, `/chestdelete [id]`, `/chestclean`
- Alertes : zone approximative sur la carte + notification pour tous les agents en service. `Config.Alerts.ServerEvent` pour brancher votre propre dispatch.

## Dépendances
`rsg-core`, `rsg-inventory`, `ox_lib`, `oxmysql`

## Installation
1. Placer le dossier `rsg_chest` dans `resources/[rsg]`.
2. Importer `sql/rsg_chest.sql` (les tables sont aussi créées automatiquement au démarrage).
3. Copier le contenu de `install/items.lua` dans `rsg-core/shared/items.lua` (table `RSGShared.Items`).
4. Ajouter les images dans `rsg-inventory/html/images/`.
5. `ensure rsg_chest` dans le `server.cfg` (après `rsg-core`, `rsg-inventory`, `ox_lib`, `oxmysql`).

## Props
Modifier `model` dans `Config.Chests`. Listes de props :
- https://redm.info/props
- https://spooni.pages.dev/props

Si un modèle n'existe pas, un message rouge apparaît en F8 et le placement est refusé.

## Jobs de perquisition
`Config.Perquisition.Jobs = { vallaw = 0, ... }` (nom du job = grade minimum). `AllowJobTypeLeo` autorise aussi tout job de type `leo`.
