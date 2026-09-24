# rsg_chest — Coffres à code & perquisition (RSG Core / RedM)

Coffres posables avec **code secret**, placement type **gizmo**, sauvegarde **SQL**, et **perquisition** pour les forces de l'ordre.

## Fonctionnalités
- Item utilisable → placement du prop fantôme qui suit la caméra, avec axes X/Y/Z affichés
  - `Q/E` rotation · `Flèches` déplacement fin · `PgUp/PgDn` hauteur · `R` poser au sol · `G` figer · `SHIFT` rapide · `ENTRÉE` valider · `RETOUR` annuler
  - Gizmo externe optionnel (`Config.Placement.ExternalGizmo`) pour un réglage 3 axes complet
- Code défini à la pose (haché côté serveur, jamais envoyé au client)
- Anti-bruteforce : X essais puis serrure bloquée, propriétaire prévenu
- Propriétaire : changer le code, ramasser le coffre (vide), voir l'historique
- Forces de l'ordre (jobs + grade configurables, en service) :
  - **Perquisitionner** : fouille sans code (barre de progression vérifiée côté serveur)
  - **Saisir** : retire le coffre (grade minimum configurable)
  - **Historique** : toutes les actions (pose, ouvertures, codes faux, fouilles…)
- Logs SQL + webhook Discord optionnel
- Interaction via prompt natif RedM ou `rsg-target` / `ox_target`
- Commandes admin : `/chestnearest`, `/chestdelete [id]`

## Dépendances
`rsg-core`, `rsg-inventory`, `ox_lib`, `oxmysql`

## Installation
1. Placer le dossier `rsg_chest` dans `resources/[rsg]`.
2. Importer `sql/rsg_chest.sql`.
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
