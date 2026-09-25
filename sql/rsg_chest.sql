CREATE TABLE IF NOT EXISTS `rsg_chests` (
    `id`         INT(11)      NOT NULL AUTO_INCREMENT,
    `owner`      VARCHAR(50)  NOT NULL,             -- citizenid du propriétaire
    `owner_name` VARCHAR(100) DEFAULT NULL,
    `type`       VARCHAR(50)  NOT NULL,             -- clé de Config.Chests
    `model`      VARCHAR(100) NOT NULL,
    `coords`     LONGTEXT     NOT NULL,             -- json {x,y,z}
    `rotation`   LONGTEXT     NOT NULL,             -- json {x,y,z}
    `code`       VARCHAR(64)  NOT NULL,             -- SHA-256 du code (jamais envoyé au client)
    `salt`       VARCHAR(32)  DEFAULT NULL,             -- sel propre au coffre
    `slots`      INT(11)      NOT NULL DEFAULT 20,
    `weight`     INT(11)      NOT NULL DEFAULT 100000,
    `shared`     LONGTEXT     DEFAULT NULL,             -- accès partagés (json)
    `last_search` INT(11)     NOT NULL DEFAULT 0,       -- dernière perquisition (unix)
    `broken_until` INT(11)    NOT NULL DEFAULT 0,       -- coffre dynamité ouvert jusqu'à (unix)
    `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `rsg_chests_logs` (
    `id`        INT(11)      NOT NULL AUTO_INCREMENT,
    `chest_id`  INT(11)      NOT NULL,
    `citizenid` VARCHAR(50)  DEFAULT NULL,
    `name`      VARCHAR(100) DEFAULT NULL,
    `job`       VARCHAR(50)  DEFAULT NULL,
    `action`    VARCHAR(32)  NOT NULL,              -- place, open, failed_code, search, seize, lockpick_*, dynamite, warrant_*, abandoned...
    `details`   VARCHAR(255) DEFAULT NULL,
    `date`      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `chest_id` (`chest_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `rsg_chests_warrants` (
    `id`          INT(11)      NOT NULL AUTO_INCREMENT,
    `target_type` VARCHAR(10)  NOT NULL,               -- chest / citizen
    `target`      VARCHAR(50)  NOT NULL,               -- id du coffre ou citizenid
    `target_name` VARCHAR(100) DEFAULT NULL,
    `reason`      VARCHAR(255) DEFAULT NULL,
    `issued_by`   VARCHAR(50)  DEFAULT NULL,
    `issued_name` VARCHAR(100) DEFAULT NULL,
    `job`         VARCHAR(50)  DEFAULT NULL,
    `expires_at`  INT(11)      NOT NULL,               -- unix
    `revoked`     TINYINT(1)   NOT NULL DEFAULT 0,
    `uses`        INT(11)      NOT NULL DEFAULT 0,
    `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `target` (`target_type`, `target`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `rsg_chests_evidence` (
    `id`          INT(11)      NOT NULL AUTO_INCREMENT,  -- n° de scellé (stash rsgchest_evidence_<id>)
    `chest_id`    INT(11)      NOT NULL,
    `owner`       VARCHAR(50)  DEFAULT NULL,
    `owner_name`  VARCHAR(100) DEFAULT NULL,
    `warrant_id`  INT(11)      DEFAULT NULL,
    `seized_by`   VARCHAR(50)  DEFAULT NULL,
    `seized_name` VARCHAR(100) DEFAULT NULL,
    `job`         VARCHAR(50)  DEFAULT NULL,
    `items`       INT(11)      NOT NULL DEFAULT 0,
    `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `chest_id` (`chest_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Mise à jour d'une ancienne installation (fait automatiquement au démarrage sous MariaDB) :
-- ALTER TABLE `rsg_chests` ADD COLUMN `shared` LONGTEXT DEFAULT NULL;
-- ALTER TABLE `rsg_chests` ADD COLUMN `last_search` INT(11) NOT NULL DEFAULT 0;
-- ALTER TABLE `rsg_chests` ADD COLUMN `broken_until` INT(11) NOT NULL DEFAULT 0;
-- ALTER TABLE `rsg_chests` ADD COLUMN `salt` VARCHAR(32) DEFAULT NULL;
