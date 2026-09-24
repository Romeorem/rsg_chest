Config = {}

Config.Debug = false

---------------------------------------------------------------------
-- Types de coffres (1 item utilisable = 1 type de coffre)
-- Liste des props : https://redm.info/props  |  https://spooni.pages.dev/props
-- Si un modèle n'existe pas dans le jeu, un avertissement s'affiche en F8
-- et le placement est refusé : remplacez simplement le nom du modèle.
---------------------------------------------------------------------
Config.Chests = {
    medium = {
        item   = 'chest_medium',
        label  = 'Coffre',
        model  = 'p_chestmedburied01x',
        slots  = 30,
        weight = 150000,
    },
    small = {
        item   = 'chest_small',
        label  = 'Petit coffre',
        model  = 'p_chest01x',
        slots  = 15,
        weight = 50000,       -- en grammes
    },
    trunk = {
        item   = 'chest_trunk',
        label  = 'Malle de voyage',
        model  = 'p_trunk02x',
        slots  = 25,
        weight = 100000,
    },
    large = {
        item   = 'chest_large',
        label  = 'Grande malle',
        model  = 'p_trunk04x',
        slots  = 40,
        weight = 200000,
    },
    strongbox = {
        item   = 'chest_strongbox',
        label  = 'Coffre-fort',
        model  = 'p_strongbox_muddy_01x',
        slots  = 10,
        weight = 30000,
    },
}

Config.MaxChestsPerPlayer = 3      -- 0 = illimité
Config.MinDistanceBetween  = 2.0   -- distance mini entre deux coffres
Config.SpawnDistance       = 60.0  -- distance d'affichage des props
Config.InteractDistance    = 1.8   -- distance d'interaction
Config.PickupRequireEmpty  = true  -- le coffre doit être vide pour être ramassé

-- Zones interdites (villes, banques, ...)
Config.BlacklistZones = {
    -- { coords = vector3(-308.5, 775.8, 118.7), radius = 60.0, label = 'Valentine' },
}

---------------------------------------------------------------------
-- Code
---------------------------------------------------------------------
Config.Code = {
    Length      = 4,     -- nombre de chiffres = nombre de molettes du cryptex (3 à 8)
    UseNui      = true,  -- true = interface cryptex (N°05), false = fenêtre texte ox_lib
    Salt        = 'change_moi_rsg_chest', -- changez cette valeur sur votre serveur
    MaxAttempts = 3,     -- essais avant blocage
    LockTime    = 120,   -- secondes de blocage après trop d'essais
    NotifyOwnerOnFail = true,
}

---------------------------------------------------------------------
-- Interaction : 'prompt' (natif RedM, sans dépendance) ou 'target'
---------------------------------------------------------------------
Config.Interaction = 'prompt'
Config.TargetResource = 'rsg-target'    -- 'rsg-target' ou 'ox_target'
Config.PromptKey = 0x760A9C6F           -- G

---------------------------------------------------------------------
-- Placement (mode gizmo)
---------------------------------------------------------------------
Config.Placement = {
    MaxDistance  = 6.0,        -- distance max entre le joueur et le coffre
    MoveStep     = 0.01,       -- déplacement fin par frame
    RotateStep   = 1.0,        -- rotation par frame (degrés)
    FastMultiplier = 5.0,      -- avec SHIFT
    PlaceDuration  = 5000,     -- durée de l'installation (ms)

    -- Gizmo externe optionnel (ex: port RedM de object_gizmo).
    -- S'il est démarré, il est lancé après le pré-placement pour un réglage 3 axes.
    ExternalGizmo = {
        enabled  = false,
        resource = 'object_gizmo',
        export   = 'useGizmo',  -- doit retourner { position = vec3, rotation = vec3 }
    },

    Keys = {
        Confirm    = 0xC7B5340A, -- ENTER
        Cancel     = 0x156F7119, -- BACKSPACE
        RotLeft    = 0xDE794E3E, -- Q
        RotRight   = 0xCEFD9220, -- E
        Forward    = 0x6319DB71, -- FLÈCHE HAUT
        Backward   = 0x05CA7C52, -- FLÈCHE BAS
        Left       = 0xA65EBAB4, -- FLÈCHE GAUCHE
        Right      = 0xDEB34313, -- FLÈCHE DROITE
        Up         = 0x446258B6, -- PAGE UP
        Down       = 0x3C3DD371, -- PAGE DOWN
        Lock       = 0x760A9C6F, -- G (fige/libère le suivi caméra)
        Ground     = 0xE30CD707, -- R (poser au sol)
        Fast       = 0x8FFC75D6, -- SHIFT
    },
}

---------------------------------------------------------------------
-- Perquisition (forces de l'ordre)
---------------------------------------------------------------------
Config.Perquisition = {
    -- job = grade minimum
    Jobs = {
        vallaw  = 0,
        rholaw  = 0,
        blklaw  = 0,
        strlaw  = 0,
        stdenlaw = 0,
        sheriff = 0,
        marshal = 0,
    },
    AllowJobTypeLeo = true,   -- autorise aussi tout job de type 'leo'
    RequireOnDuty   = true,
    Duration        = 10000,  -- durée de la fouille (ms)
    NotifyOwner     = true,   -- prévient le propriétaire s'il est connecté

    CanSeize        = true,   -- saisie (suppression) du coffre
    SeizeMinGrade   = 1,
    SeizeRequireEmpty = false, -- si false, le contenu est détruit avec le coffre
    SeizeGiveItem   = false,  -- donne l'item du coffre à l'agent

    -- Règles
    MinOfficersNearby = 2,    -- agents en service à proximité (agent qui fouille inclus)
    OfficersRadius    = 20.0,
    Cooldown          = 1800, -- secondes entre deux fouilles d'un même coffre
}

---------------------------------------------------------------------
-- Mandats de perquisition
---------------------------------------------------------------------
Config.Warrant = {
    Required        = true,   -- pas de fouille sans mandat valide
    SeizeRequiresWarrant = true,
    IssueMinGrade   = 2,      -- grade minimum pour délivrer / révoquer un mandat
    DefaultHours    = 24,
    MaxHours        = 72,
    SingleUse       = false,  -- true = le mandat est consommé à la première fouille
}

---------------------------------------------------------------------
-- Partage des coffres (sans code)
---------------------------------------------------------------------
Config.Sharing = {
    Enabled        = true,
    Max            = 10,      -- nombre d'accès par coffre
    OwnerNoCode    = true,    -- le propriétaire ouvre sans code
    NearbyDistance = 5.0,     -- le joueur ajouté doit être à côté du propriétaire
    AllowGang      = true,    -- partager avec tout un gang
    AllowJob       = true,    -- partager avec tout un job (ranch, commerce...)
}

---------------------------------------------------------------------
-- Crochetage (mini-jeu sur les molettes du cryptex)
---------------------------------------------------------------------
Config.Lockpick = {
    Enabled        = true,
    Item           = 'lockpick',
    LawCanLockpick = false,
    Wheels         = 4,       -- molettes à crocheter
    TimeLimit      = 45,      -- secondes
    MinSecondsPerWheel = 1.0, -- anti-triche : durée mini par molette
    BreakChance    = 35,      -- % de casse du crochet à chaque erreur
    MaxFails       = 4,       -- casse garantie après X erreurs
    BreakOnSuccessChance = 15, -- % de casse même en cas de réussite
    ChestCooldown  = 300,     -- secondes entre deux tentatives sur un même coffre
    AlertChance    = 60,      -- % d'alerter la loi au début du crochetage
    NotifyOwner    = true,
}

---------------------------------------------------------------------
-- Dynamite
---------------------------------------------------------------------
Config.Dynamite = {
    Enabled       = true,
    Item          = 'dynamite',
    LawCanUse     = false,
    PlantDuration = 6000,     -- ms
    Fuse          = 10,       -- secondes avant l'explosion
    ExplosionType = 25,       -- type d'explosion RedM
    AlertOnPlant  = false,    -- alerte dès la pose (sinon à l'explosion)
    OpenTime      = 600,      -- secondes pendant lesquelles le coffre éventré est ouvert à tous
    RemoveAfter   = true,     -- le coffre (et ce qu'il reste dedans) disparaît ensuite
}

---------------------------------------------------------------------
-- Alertes envoyées aux forces de l'ordre
---------------------------------------------------------------------
Config.Alerts = {
    BlipTime    = 120,        -- secondes
    BlipRadius  = 60.0,       -- zone approximative affichée sur la carte
    ServerEvent = nil,        -- ex: 'mon_dispatch:server:alert' (reçoit coords, message)
}

---------------------------------------------------------------------
-- Coffres abandonnés
---------------------------------------------------------------------
Config.Abandon = {
    Enabled        = true,
    Days           = 30,      -- propriétaire non connecté depuis X jours
    DeleteIfNoCharacter = true, -- personnage supprimé
    CheckEveryHours = 6,
}

Config.LogsLimit = 25
Config.Webhook = ''           -- webhook Discord (vide = désactivé)

---------------------------------------------------------------------
-- Textes
---------------------------------------------------------------------
Config.Text = {
    prompt_group    = 'Coffre',
    prompt_interact = 'Interagir',
    menu_open       = 'Ouvrir (code)',
    menu_open_desc  = 'Entrer le code pour ouvrir le coffre',
    menu_change     = 'Changer le code',
    menu_pickup     = 'Ramasser le coffre',
    menu_search     = 'Perquisitionner',
    menu_search_desc = 'Fouiller le coffre sans code (forces de l\'ordre)',
    menu_seize      = 'Saisir le coffre',
    menu_logs       = 'Historique',
    input_code      = 'Code',
    input_confirm   = 'Confirmer le code',
    input_old       = 'Ancien code',
    input_new       = 'Nouveau code',
    title_new       = 'Définir le code du coffre',
    nui_validate    = 'Valider',
    nui_next        = 'Suivant',
    nui_reset       = 'Remettre',
    nui_cancel      = 'Annuler',
    nui_help        = 'Molette / ▲▼ pour tourner · chiffres du clavier · Entrée pour valider · Échap pour annuler',
    nui_step        = 'Étape %d / %d',
    placing         = 'Installation du coffre...',
    searching       = 'Perquisition en cours...',
    placement_help  = '[ENTRÉE] Valider  [RETOUR] Annuler  \n[Q/E] Rotation  [FLÈCHES] Déplacer  \n[PG↑/PG↓] Hauteur  [R] Sol  [G] Figer  [SHIFT] Rapide',
    code_mismatch   = 'Les codes ne correspondent pas.',
    code_invalid    = 'Le code doit contenir %d chiffres.',
    placed          = 'Coffre installé.',
    wrong_code      = 'Code incorrect. (%d essai(s) restant(s))',
    locked          = 'Serrure bloquée, réessayez dans %d secondes.',
    code_changed    = 'Code modifié.',
    picked_up       = 'Coffre ramassé.',
    not_empty       = 'Le coffre doit être vide.',
    too_far         = 'Trop loin.',
    too_close       = 'Trop proche d\'un autre coffre.',
    blacklisted     = 'Impossible de poser un coffre ici.',
    max_reached     = 'Vous avez atteint la limite de coffres (%d).',
    no_item         = 'Vous n\'avez pas cet objet.',
    not_allowed     = 'Vous n\'êtes pas autorisé.',
    not_owner       = 'Ce coffre ne vous appartient pas.',
    invalid_model   = 'Modèle de coffre invalide, contactez un admin.',
    cancelled       = 'Annulé.',
    searched_owner  = 'Votre coffre (#%d) est en train d\'être perquisitionné !',
    fail_owner      = 'Quelqu\'un essaie de forcer votre coffre (#%d) !',
    seized          = 'Coffre saisi.',
    seize_confirm   = 'Saisir définitivement ce coffre ?',
    seize_confirm_d = 'Le coffre sera retiré et son contenu détruit.',
    no_logs         = 'Aucun historique.',
    already_placing = 'Vous êtes déjà en train de placer un objet.',

    -- partage
    menu_open_shared = 'Ouvrir',
    menu_open_shared_d = 'Vous avez accès à ce coffre',
    menu_access     = 'Gérer les accès',
    access_title    = 'Accès au coffre',
    access_add_player = 'Ajouter un joueur proche',
    access_add_gang = 'Ajouter mon gang (%s)',
    access_add_job  = 'Ajouter mon métier (%s)',
    access_remove   = 'Retirer l\'accès',
    access_none_near = 'Aucun joueur à proximité.',
    access_added    = 'Accès ajouté.',
    access_removed  = 'Accès retiré.',
    access_exists   = 'Cet accès existe déjà.',
    access_max      = 'Nombre maximum d\'accès atteint (%d).',
    access_player   = 'Joueur',
    access_gang     = 'Gang',
    access_job      = 'Métier',

    -- mandats
    menu_warrant    = 'Délivrer un mandat',
    warrant_title   = 'Mandat de perquisition',
    warrant_target  = 'Cible',
    warrant_t_chest = 'Ce coffre (#%d)',
    warrant_t_owner = 'Le propriétaire (tous ses coffres)',
    warrant_t_citizen = 'Citoyen (ID joueur ou citizenid)',
    warrant_citizen = 'ID joueur ou citizenid',
    warrant_reason  = 'Motif',
    warrant_hours   = 'Durée (heures)',
    warrant_issued  = 'Mandat #%d délivré.',
    warrant_revoked = 'Mandat révoqué.',
    warrant_valid   = 'Mandat #%d valide',
    warrant_none    = 'Aucun mandat valide',
    warrant_list    = 'Mandats en cours',
    warrant_revoke  = 'Révoquer',
    warrant_empty   = 'Aucun mandat en cours.',
    warrant_bad_target = 'Cible introuvable.',
    no_warrant      = 'Un mandat valide est nécessaire.',
    not_enough_officers = 'Il faut au moins %d agents sur place.',
    search_cooldown = 'Ce coffre a déjà été fouillé, réessayez dans %d min.',

    -- crochetage
    menu_lockpick   = 'Crocheter',
    menu_lockpick_d = 'Nécessite un crochet',
    lockpick_title  = 'Crochetage',
    lockpick_help   = 'Tournez la molette jusqu\'au déclic, puis bloquez (Espace). ← → pour changer de molette.',
    lockpick_lock   = 'Bloquer',
    lockpick_slip   = 'Le crochet a glissé...',
    lockpick_broken = 'Votre crochet s\'est cassé.',
    lockpick_success = 'La serrure cède.',
    lockpick_timeout = 'Trop lent, la serrure s\'est refermée.',
    lockpick_cooldown = 'La serrure a déjà été forcée récemment, réessayez dans %d s.',
    lockpick_owner  = 'Quelqu\'un crochète votre coffre (#%d) !',

    -- dynamite
    menu_dynamite   = 'Poser de la dynamite',
    menu_dynamite_d = 'Fait sauter la serrure, très bruyant',
    dynamite_plant  = 'Pose de la dynamite...',
    dynamite_lit    = 'Mèche allumée ! Éloignez-vous (%d s).',
    dynamite_countdown = 'Explosion dans %d s',
    dynamite_armed  = 'De la dynamite est déjà posée.',
    menu_loot       = 'Fouiller le coffre éventré',
    menu_loot_d     = 'La serrure a sauté',
    chest_destroyed = 'Le coffre (#%d) a été détruit.',

    -- alertes
    alert_lockpick  = 'Tentative d\'effraction sur un coffre signalée.',
    alert_dynamite  = 'Explosion signalée ! Un coffre a été dynamité.',
    alert_blip      = 'Alerte : coffre',
    need_item       = 'Il vous faut : %s.',
}
