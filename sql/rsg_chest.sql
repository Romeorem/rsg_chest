CREATE TABLE IF NOT EXISTS `rsg_chests` (
    `id`         INT(11)      NOT NULL AUTO_INCREMENT,
    `owner`      VARCHAR(50)  NOT NULL,             -- citizenid du propriétaire
    `owner_name` VARCHAR(100) DEFAULT NULL,
    `type`       VARCHAR(50)  NOT NULL,             -- clé de Config.Chests
    `model`      VARCHAR(100) NOT NULL,
    `coords`     LONGTEXT     NOT NULL,             -- json {x,y,z}
    `rotation`   LONGTEXT     NOT NULL,             -- json {x,y,z}
    `code`       VARCHAR(64)  NOT NULL,             -- code haché (jamais envoyé au client)
    `slots`      INT(11)      NOT NULL DEFAULT 20,
    `weight`     INT(11)      NOT NULL DEFAULT 100000,
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
    `action`    VARCHAR(32)  NOT NULL,              -- place / open / failed_code / change_code / pickup / search / seize / admin_delete
    `details`   VARCHAR(255) DEFAULT NULL,
    `date`      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `chest_id` (`chest_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
