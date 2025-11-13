############################################################### 
########################### INIT DB ###########################
###############################################################
DROP DATABASE IF EXISTS `pubpeer_analytics`; # /!\ Comment this line
                                             # once database is 
                                             # initiated. /!\
CREATE DATABASE `pubpeer_analytics`;
USE `pubpeer_analytics`;
# data/database/history.sql is the simplest way to boot
# the database to a minimal "functional stage".
######################### END INIT DB #########################

######################### V 1 - 2025-03-31 16:30:00
# Created publication table.
CREATE TABLE `publication` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `pubpeer_id` bigint NOT NULL,
  `created` varchar(100) NOT NULL,
  `comments_total` int NOT NULL,
  `comments_updated` int NOT NULL DEFAULT 0,
  `has_author_response` int DEFAULT 0,
  `link_with_hash` varchar(300) NOT NULL,
  `title` varchar(300) NOT NULL,
  `updated` varchar(100) DEFAULT NULL,
  `creation_timestamp` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `pubpeer_id_unique` (`pubpeer_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
USE `pubpeer_analytics`$$
DELIMITER ;
CREATE TRIGGER `before_publication_insert` 
BEFORE INSERT ON `publication` 
FOR EACH ROW  
SET NEW.`creation_timestamp` = UNIX_TIMESTAMP();
ALTER TABLE `pubpeer_analytics`.`publication` 
ADD COLUMN `pubmed_id` VARCHAR(100) NULL AFTER `creation_timestamp`;
ALTER TABLE `pubpeer_analytics`.`publication` 
CHANGE COLUMN `title` `title` VARCHAR(1000) NOT NULL ;

# Created journal table.
CREATE TABLE `journal` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `pubpeer_id` bigint NOT NULL,
  `issn` varchar(100) DEFAULT NULL,
  `title` varchar(300) NOT NULL,
  `creation_timestamp` int DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
USE `pubpeer_analytics`$$
DELIMITER ;
CREATE TRIGGER `before_journal_insert` 
BEFORE INSERT ON `journal` 
FOR EACH ROW  
SET NEW.`creation_timestamp` = UNIX_TIMESTAMP();

# Created author table.
CREATE TABLE `author` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `pubpeer_id` bigint NOT NULL,
  `first_name` varchar(300) NOT NULL,
  `last_name` varchar(300) NOT NULL,
  `email` varchar(300) DEFAULT NULL,
  `creation_timestamp` int DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
USE `pubpeer_analytics`$$
DELIMITER ;
CREATE TRIGGER `before_author_insert` 
BEFORE INSERT ON `author` 
FOR EACH ROW  
SET NEW.`creation_timestamp` = UNIX_TIMESTAMP();

# Created journal_publication table.
CREATE TABLE `pubpeer_analytics`.`journal_publication` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `journal_id` BIGINT NOT NULL,
  `publication_id` BIGINT NOT NULL,
  `creation_timestamp` INT NOT NULL,
  PRIMARY KEY (`id`),
  INDEX `journal_publication_to_journal_idx` (`journal_id` ASC) VISIBLE,
  INDEX `journal_publication_to_publication_idx` (`publication_id` ASC) VISIBLE,
  CONSTRAINT `journal_publication_to_journal`
    FOREIGN KEY (`journal_id`)
    REFERENCES `pubpeer_analytics`.`journal` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `journal_publication_to_publication`
    FOREIGN KEY (`publication_id`)
    REFERENCES `pubpeer_analytics`.`publication` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION);
USE `pubpeer_analytics`$$
DELIMITER ;
CREATE TRIGGER `before_journal_publication_insert` 
BEFORE INSERT ON `journal_publication` 
FOR EACH ROW  
SET NEW.`creation_timestamp` = UNIX_TIMESTAMP();

# Created author_publication table.
CREATE TABLE `pubpeer_analytics`.`author_publication` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `author_id` BIGINT NOT NULL,
  `publication_id` BIGINT NOT NULL,
  `creation_timestamp` INT NOT NULL,
  PRIMARY KEY (`id`),
  INDEX `author_publication_to_author_idx` (`author_id` ASC) VISIBLE,
  INDEX `author_publication_to_publication_idx` (`publication_id` ASC) VISIBLE,
  CONSTRAINT `author_publication_to_author`
    FOREIGN KEY (`author_id`)
    REFERENCES `pubpeer_analytics`.`author` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `author_publication_to_publication`
    FOREIGN KEY (`publication_id`)
    REFERENCES `pubpeer_analytics`.`publication` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION);
USE `pubpeer_analytics`$$
DELIMITER ;
CREATE TRIGGER `before_author_publication_insert` 
BEFORE INSERT ON `author_publication` 
FOR EACH ROW  
SET NEW.`creation_timestamp` = UNIX_TIMESTAMP();

# Created pubmed_publication table.
CREATE TABLE `pubpeer_analytics`.`pubmed_publication` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `pubmed_id` VARCHAR(100) NOT NULL,
  `verified` INT NOT NULL DEFAULT 0,
  `creation_timestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `pubpeer_analytics`$$
DELIMITER ;
CREATE TRIGGER `before_pubmed_publication_insert` 
BEFORE INSERT ON `pubmed_publication` 
FOR EACH ROW  
SET NEW.`creation_timestamp` = UNIX_TIMESTAMP();
ALTER TABLE `pubpeer_analytics`.`pubmed_publication` 
ADD COLUMN `creation_date` VARCHAR(100) NOT NULL AFTER `pubmed_id`;
ALTER TABLE `pubpeer_analytics`.`pubmed_publication` 
ADD COLUMN `verification_timestamp` INT NULL AFTER `creation_timestamp`;
ALTER TABLE `pubpeer_analytics`.`pubmed_publication` 
ADD COLUMN `found` INT NOT NULL DEFAULT 0 AFTER `verified`,
CHANGE COLUMN `creation_timestamp` `creation_timestamp` INT NOT NULL AFTER `creation_date`;

