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
        model  = 'p_chestmedburied01x', -- p_chest01x ne se charge pas en jeu
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

-- Modèle utilisé si celui d'un coffre ne se charge pas (le coffre reste visible)
Config.FallbackModel = 'p_chestmedburied01x'

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
    SoundVolume = 0.5,   -- sons du cryptex (0 = coupé, 1 = max)
    Salt        = 'change_moi_rsg_chest', -- changez cette valeur sur votre serveur
    MaxAttempts = 3,     -- essais avant blocage
    LockTime    = 120,   -- secondes de blocage après trop d'essais
    NotifyOwnerOnFail = true,
    -- blocage du coffre entier (tous joueurs confondus, contre les multi-personnages)
    ChestMaxFails   = 10,  -- échecs...
    ChestFailWindow = 600, -- ...en X secondes
    ChestLockTime   = 900, -- durée du blocage (secondes)
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
    SeizeRequireEmpty = false, -- si false, le contenu part aux scellés (ou est détruit, voir Config.Evidence)
    SeizeGiveItem   = false,  -- donne l'item du coffre à l'agent

    -- Règles
    MinOfficersNearby = 2,    -- agents en service à proximité (agent qui fouille inclus)
    OfficersRadius    = 20.0,
    Cooldown          = 1800, -- secondes entre deux fouilles d'un même coffre
}

---------------------------------------------------------------------
-- Scellés : le contenu d'un coffre saisi est conservé comme pièce à conviction
---------------------------------------------------------------------
Config.Evidence = {
    Enabled   = true,         -- false = le contenu saisi est détruit
    MinGrade  = 0,            -- grade minimum pour consulter les scellés (/scelles)
    Slots     = 200,
    Weight    = 5000000,
    ListLimit = 30,
    -- lieux où les scellés se consultent (vide = partout)
    Locations = {
        -- { coords = vector3(-278.4, 805.3, 119.4), radius = 6.0 }, -- ex : bureau du shérif de Valentine
    },
}

---------------------------------------------------------------------
-- Admin
---------------------------------------------------------------------
Config.Admin = {
    Permission = 'admin',     -- permission RSG pour /chestadmin, /chestdelete, /chestnearest, /chestclean
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
-- Langue : 'fr' ou 'en' (fichiers dans locales/)
---------------------------------------------------------------------
Config.Locale = 'fr'
