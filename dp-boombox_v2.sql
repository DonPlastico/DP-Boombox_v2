-- =======================================================
-- DP-Boombox_v2 | BASE DE DATOS PRINCIPAL (FULL) (Con cosas de otros scripts)
-- =======================================================

CREATE TABLE IF NOT EXISTS `dp_preferences` (
  `citizenid` varchar(50) NOT NULL,
  `menu_top` varchar(20) DEFAULT '14.537%',
  `menu_left` varchar(20) DEFAULT '62.5%',
  `menu_scale` INT DEFAULT 90,
  `inventory_position` varchar(20) DEFAULT 'bottom',
  `move_while_open` INT DEFAULT 0,
  PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `dp_preferences` ADD COLUMN `ui_sounds` INT DEFAULT 1;
ALTER TABLE `dp_preferences` ADD COLUMN `boombox_move_open` INT DEFAULT 0;
ALTER TABLE `dp_preferences` ADD COLUMN `boombox_top` varchar(20) DEFAULT NULL;
ALTER TABLE `dp_preferences` ADD COLUMN `boombox_left` varchar(20) DEFAULT NULL;