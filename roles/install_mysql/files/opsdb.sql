-- MySQL dump 10.13  Distrib 5.7.24-26, for Linux (x86_64)
--
-- Host: localhost    Database: ckadmin
-- ------------------------------------------------------
-- Server version	5.7.24-26-log

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;
/*!50717 SELECT COUNT(*) INTO @rocksdb_has_p_s_session_variables FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'performance_schema' AND TABLE_NAME = 'session_variables' */;
/*!50717 SET @rocksdb_get_is_supported = IF (@rocksdb_has_p_s_session_variables, 'SELECT COUNT(*) INTO @rocksdb_is_supported FROM performance_schema.session_variables WHERE VARIABLE_NAME=\'rocksdb_bulk_load\'', 'SELECT 0') */;
/*!50717 PREPARE s FROM @rocksdb_get_is_supported */;
/*!50717 EXECUTE s */;
/*!50717 DEALLOCATE PREPARE s */;
/*!50717 SET @rocksdb_enable_bulk_load = IF (@rocksdb_is_supported, 'SET SESSION rocksdb_bulk_load = 1', 'SET @rocksdb_dummy_bulk_load = 0') */;
/*!50717 PREPARE s FROM @rocksdb_enable_bulk_load */;
/*!50717 EXECUTE s */;
/*!50717 DEALLOCATE PREPARE s */;

--
-- Current Database: `ckadmin`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `ckadmin` ;

USE `ckadmin`;

--
-- Table structure for table `activeDatacenter`
--

-- DROP TABLE IF EXISTS `activeDatacenter`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE if not exists `activeDatacenter` (
  `activeDatacenter` varchar(10) NOT NULL,
  `autoTs` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB ;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `etlsource`
--

-- DROP TABLE IF EXISTS `etlsource`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE if not exists `etlsource` (
  `sourceType` varchar(60) NOT NULL,
  `hostName` varchar(60) NOT NULL,
  `dataCenter` varchar(10) NOT NULL,
  `autoTs` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`sourceType`,`hostName`,`dataCenter`)
) ENGINE=InnoDB ;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `host_info`
--

-- DROP TABLE IF EXISTS `host_info`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE if not exists `host_info` (
  `hostId` int(11) NOT NULL AUTO_INCREMENT,
  `hostName` varchar(50) DEFAULT NULL,
  `ipAddress` varchar(100) DEFAULT NULL,
  `groupName` varchar(30) DEFAULT NULL,
  `dataCenter` varchar(30) DEFAULT NULL,
  `instanceName` varchar(30) DEFAULT NULL,
  `port` smallint(6) DEFAULT NULL,
  `role` varchar(20) DEFAULT NULL,
  `isMaster` char(1) DEFAULT 'N',
  `shardNumber` smallint(6) DEFAULT '0',
  `socket` varchar(100) DEFAULT NULL,
  `fqdn` varchar(100) DEFAULT NULL,
  `datadir` varchar(100) DEFAULT NULL,
  `multiInstance` char(1) DEFAULT 'N',
  `consulMasterCandidate` tinyint(1) DEFAULT '0',
  `consulSlaveCandidate` tinyint(1) DEFAULT '0',
  PRIMARY KEY (`hostId`),
  UNIQUE KEY `host_port` (`fqdn`,`port`)
) ENGINE=InnoDB;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `host_user_info`
--

-- DROP TABLE IF EXISTS `host_user_info`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE if not exists `host_user_info` (
  `userId` int(11) NOT NULL AUTO_INCREMENT,
  `userName` varchar(16) NOT NULL,
  `userHost` varchar(60) NOT NULL,
  `targetHost` varchar(60) DEFAULT '',
  `isDefault` char(1) NOT NULL DEFAULT 'N',
  `groupName` varchar(30) DEFAULT NULL,
  `dataCenter` varchar(30) DEFAULT NULL,
  `privileges` varchar(150) DEFAULT 'SELECT',
  `objectName` varchar(60) DEFAULT '*.*',
  `password` varchar(100) NOT NULL,
  `createdTs` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updatedTs` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`userId`),
  UNIQUE KEY `user` (`userName`,`userHost`,`groupName`,`dataCenter`,`objectName`,`targetHost`)
) ENGINE=InnoDB ;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `scan_binlogs_gcp`
--

-- DROP TABLE IF EXISTS `scan_binlogs_gcp`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE if not exists `scan_binlogs_gcp` (
  `eventId` int(11) NOT NULL AUTO_INCREMENT,
  `eventHost` varchar(100) NOT NULL,
  `eventPort` varchar(100) NOT NULL,
  `eventInstanceName` varchar(100) NOT NULL,
  `eventGtid` varchar(100) DEFAULT NULL,
  `eventStatement` text,
  `autoTs` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`eventId`),
  UNIQUE KEY `eventGtid` (`eventGtid`),
  KEY `autoTs` (`autoTs`)
) ENGINE=InnoDB;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `schema_hvault`
--

-- DROP TABLE IF EXISTS `schema_hvault`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE if not exists `schema_hvault` (
  `schemaName` varchar(255) NOT NULL DEFAULT '',
  `hvaultnamespace` varchar(255) DEFAULT NULL,
  `createdTs` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updatedTs` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`schemaName`)
) ENGINE=InnoDB ;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `schema_info`
--

-- DROP TABLE IF EXISTS `schema_info`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE if not exists `schema_info` (
  `schemaName` varchar(255) NOT NULL DEFAULT '',
  `serviceName` varchar(255) DEFAULT NULL,
  `numOfschema` int(10) unsigned DEFAULT '1024',
  `isSharded` char(1) DEFAULT 'Y',
  `role` varchar(20) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `createdTs` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updatedTs` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`schemaName`)
) ENGINE=InnoDB ;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `schema_info_us`
--

-- DROP TABLE IF EXISTS `schema_info_us`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE if not exists `schema_info_us` (
  `schemaName` varchar(255) NOT NULL DEFAULT '',
  `serviceName` varchar(255) DEFAULT NULL,
  `numOfschema` int(10) unsigned DEFAULT '1024',
  `isSharded` char(1) DEFAULT 'Y',
  `role` varchar(20) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `createdTs` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updatedTs` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`schemaName`)
) ENGINE=InnoDB ;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `snapshot_catalog`
--

-- DROP TABLE IF EXISTS `snapshot_catalog`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE if not exists `snapshot_catalog` (
  `snapId` int(11) NOT NULL AUTO_INCREMENT,
  `backupHost` varchar(50) NOT NULL,
  `backupPort` smallint(6) NOT NULL,
  `masterHost` varchar(50) NOT NULL,
  `masterPort` smallint(6) NOT NULL,
  `dataCenter` varchar(30) NOT NULL,
  `role` varchar(20) NOT NULL,
  `binlog_file` varchar(100) NOT NULL COMMENT 'Current binary log',
  `binlog_file_pos` bigint(20) unsigned NOT NULL COMMENT 'Current binary log position',
  `master_log_read` varchar(100) NOT NULL COMMENT 'The name of the master binary log currently being read from the master.',
  `master_log_pos_read` bigint(20) unsigned NOT NULL COMMENT 'The master log position of the last read event.',
  `relay_log` varchar(100) NOT NULL COMMENT 'The name of the current relay log file.',
  `relay_log_pos` bigint(20) NOT NULL COMMENT 'The relay log position of the last executed event.',
  `relay_master_log` varchar(100) NOT NULL COMMENT 'The name of the master binary log file from which the events in the relay log file were read.',
  `exec_master_log_pos` bigint(20) NOT NULL COMMENT 'The master log position of the last executed event.',
  `Retrieved_Gtid_Set` text,
  `Executed_Gtid_Set` text,
  `slave_io_running` varchar(3) NOT NULL,
  `slave_sql_running` varchar(3) NOT NULL,
  `autoTs` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `Status` tinyint(1) DEFAULT '1',
  PRIMARY KEY (`snapId`),
  KEY `autoTs` (`autoTs`),
  KEY `backupHost` (`backupHost`)
) ENGINE=InnoDB  COMMENT='Catalog of MySQL backups using storage snapsnots. It contains metadata needed for PITR';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `snapshot_catalog_gcp`
--

-- DROP TABLE IF EXISTS `snapshot_catalog_gcp`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE if not exists `snapshot_catalog_gcp` (
  `snapId` int(11) NOT NULL AUTO_INCREMENT,
  `dataCenter` varchar(30) NOT NULL,
  `snapshotName` varchar(100) NOT NULL,
  `snapshotHost` varchar(50) NOT NULL,
  `snapshotPort` smallint(6) NOT NULL,
  `snapshotHostBinlogFile` varchar(100) NOT NULL COMMENT 'The binary log file of the snapshot host',
  `snapshotHostBinlogPosition` bigint(20) NOT NULL COMMENT 'The binary log position of the snapshot host.',
  `snapshotHostExecutedGtidSet` text,
  `masterHost` varchar(50) NOT NULL,
  `masterPort` smallint(6) NOT NULL,
  `masterLogFile` varchar(100) NOT NULL COMMENT 'Current binary log file of master',
  `execMasterLogPos` bigint(20) NOT NULL COMMENT 'The master log position of the last executed event.',
  `createdAt` datetime NOT NULL,
  `autoTs` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `status` varchar(20) DEFAULT NULL,
  PRIMARY KEY (`snapId`),
  KEY `createdTs` (`createdAt`),
  KEY `autoTs` (`autoTs`),
  KEY `comp_idx1` (`snapshotHost`,`snapshotPort`)
) ENGINE=InnoDB;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `snapshot_host_map`
--

-- DROP TABLE IF EXISTS `snapshot_host_map`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE if not exists `snapshot_host_map` (
  `fqdn` varchar(100) NOT NULL DEFAULT '',
  `ipAddress` varchar(30) DEFAULT NULL,
  `dataCenter` varchar(30) DEFAULT NULL,
  `groupName` varchar(30) NOT NULL DEFAULT 'budb',
  `shard` tinyint(1) DEFAULT '1',
  `app_consistent_ready` tinyint(1) DEFAULT '0',
  `vmax_admin` varchar(30) NOT NULL DEFAULT '10.99.200.64',
  `vmax_sid` smallint(6) NOT NULL DEFAULT '497',
  PRIMARY KEY (`fqdn`)
) ENGINE=InnoDB ;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `track_binlog_events`
--

-- DROP TABLE IF EXISTS `track_binlog_events`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE if not exists `track_binlog_events` (
  `eventId` int(11) NOT NULL AUTO_INCREMENT,
  `fqdn` varchar(100) NOT NULL,
  `port` smallint(6) NOT NULL,
  `binlog` varchar(100) NOT NULL,
  `previous_statement` text,
  `start_pos` int(11) DEFAULT NULL,
  `gtid_next` varchar(100) DEFAULT NULL,
  `end_pos` int(11) DEFAULT NULL,
  `statement` text,
  `status` tinyint(1) NOT NULL DEFAULT '1',
  `autoTs` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`eventId`),
  UNIQUE KEY `u_event` (`binlog`,`start_pos`),
  KEY `autoTs` (`autoTs`)
) ENGINE=InnoDB ;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `typed_address`
--

-- DROP TABLE IF EXISTS `typed_address`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE if not exists `typed_address` (
  `numericId` bigint(10) unsigned NOT NULL,
  `addressId` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `houseNum` varchar(10) DEFAULT NULL,
  `preDirectional` varchar(2) DEFAULT NULL,
  `streetName` varchar(27) DEFAULT NULL,
  `postDirectional` varchar(2) DEFAULT NULL,
  `streetType` varchar(5) DEFAULT NULL,
  `apt` varchar(128) DEFAULT NULL,
  `city` varchar(27) NOT NULL,
  `state` char(2) NOT NULL,
  `zip` char(5) NOT NULL,
  `addressType` enum('savings') NOT NULL,
  `verifiedBy` varchar(15) DEFAULT NULL,
  `verifiedTs` bigint(20) unsigned DEFAULT NULL,
  `addressLine1` varchar(128) DEFAULT NULL,
  `autoTs` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`numericId`,`addressId`),
  UNIQUE KEY `numericId` (`numericId`,`addressType`),
  KEY `addressId` (`addressId`),
  KEY `autoTs` (`autoTs`)
) ENGINE=InnoDB ;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_details`
--

-- DROP TABLE IF EXISTS `user_details`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE if not exists `user_details` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `user` varchar(255) NOT NULL,
  `host` varchar(255) NOT NULL,
  `cluster` varchar(255) DEFAULT NULL,
  `grants` text,
  `description` text,
  PRIMARY KEY (`id`),
  UNIQUE KEY `user` (`user`,`host`)
) ENGINE=InnoDB ;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_grants`
--

-- DROP TABLE IF EXISTS `user_grants`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE if not exists `user_grants` (
  `grantId` int(11) NOT NULL AUTO_INCREMENT,
  `groupName` varchar(50) DEFAULT NULL,
  `dataCenter` varchar(50) DEFAULT NULL,
  `grants` text,
  PRIMARY KEY (`grantId`)
) ENGINE=InnoDB ;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping events for database 'ckadmin'
--

--
-- Dumping routines for database 'ckadmin'
--
/*!50112 SET @disable_bulk_load = IF (@is_rocksdb_supported, 'SET SESSION rocksdb_bulk_load = @old_rocksdb_bulk_load', 'SET @dummy_rocksdb_bulk_load = 0') */;
/*!50112 PREPARE s FROM @disable_bulk_load */;
/*!50112 EXECUTE s */;
/*!50112 DEALLOCATE PREPARE s */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2020-01-30  9:46:09
