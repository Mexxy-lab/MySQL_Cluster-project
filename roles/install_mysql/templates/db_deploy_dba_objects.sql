-- Key Database objects used be the DBA team

-- disable binlog
set sql_log_bin=0;
create database IF NOT EXISTS dbadb;
use dbadb;

CREATE TABLE IF NOT EXISTS `sid_info`(`sid` varchar(30) NOT NULL, PRIMARY KEY (`sid`) );
replace into sid_info values('{{ sid }}');

CREATE TABLE IF NOT EXISTS `latency` (
  `server_name` varchar(30) NOT NULL,
  `time_stamp` datetime NOT NULL,
  PRIMARY KEY (`server_name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

replace into  dbadb.latency values ( SUBSTRING_INDEX(@@hostname,'.',1) , now());


delimiter $$

DROP EVENT IF EXISTS `event_update_latency` $$
CREATE DEFINER=`{{db_os_user}}`@`localhost` EVENT `event_update_latency` ON SCHEDULE EVERY 1 MINUTE STARTS '2016-03-01 20:00:26' ON COMPLETION PRESERVE ENABLE COMMENT 'update the latency table for that server' DO BEGIN
 replace into dbadb.latency values (SUBSTRING_INDEX(@@hostname,'.',1), UTC_TIMESTAMP());
--  UPDATE dbadb.latency
--     SET time_stamp = UTC_TIMESTAMP()
--   WHERE SUBSTRING_INDEX(server_name,'.',1) =SUBSTRING_INDEX(@@hostname,'.',1);
END

$$

-- ALTER DEFINER='dbadmin'@'%' EVENT event_update_latency  ENABLE $$

DROP PROCEDURE IF EXISTS `sp_generate_add_partitions` $$
CREATE DEFINER=`{{db_os_user}}`@`localhost` PROCEDURE `sp_generate_add_partitions`(
    IN i_db VARCHAR(64),
    IN i_tablename VARCHAR(64),
    IN i_min_part_name  CHAR(10),
    IN i_part_name CHAR(10),
    IN i_date_function VARCHAR(20),
    IN i_date_col VARCHAR(64)
)
BEGIN

    SELECT MAX(partition_name)
    FROM information_schema.partitions
    WHERE table_schema=i_db
      AND table_name=i_tablename
      AND partition_name NOT LIKE 'p_m%'
    INTO @curr_max_part;

    IF (i_min_part_name > @curr_max_part) THEN
        SET @curr_max_part:=i_min_part_name;
    END IF;

    SET @date_length:=LENGTH(SUBSTRING(@curr_max_part FROM 3));

    IF (@date_length = 8) THEN
       SET @new_max_day:=STR_TO_DATE(SUBSTRING(i_part_name FROM 3),'%Y%m%d');
       SET @curr_max_day:=STR_TO_DATE(SUBSTRING(@curr_max_part FROM 3),'%Y%m%d');
       SET @nextday:=@curr_max_day + INTERVAL 1 DAY;


       IF (@nextday >= @new_max_day) THEN
          BEGIN

           SELECT "# No partitions to add.";
           SELECT "";
          END;
       ELSE
          BEGIN
            SELECT CONCAT('USE ',i_db,';');
            SELECT CONCAT('ALTER TABLE ', i_db, '.', i_tablename, ' REORGANIZE PARTITION p_max INTO (');
            SET @stmt1:=CONCAT('SET @todays_nextday:=', i_date_function, '(@nextday + INTERVAL 1 DAY)');

            PREPARE stmt1 FROM @stmt1;
            WHILE @nextday < @new_max_day DO

               EXECUTE stmt1;
               SELECT CONCAT("PARTITION p_",REPLACE(@nextday,'-','') , " VALUES LESS THAN (", @todays_nextday, ") ENGINE = INNODB,");
               SET @nextday:= @nextday + INTERVAL 1 DAY;
           END WHILE;
           DEALLOCATE PREPARE stmt1;
           SELECT 'PARTITION p_max VALUES LESS THAN MAXVALUE ENGINE = INNODB);';
          END;
       END IF;
    ELSE
       IF (@date_length = 6) THEN
          SET @new_max_day:=DATE_FORMAT(STR_TO_DATE(SUBSTRING(i_part_name FROM 3),'%Y%m'),'%Y-%m-01');
          SET @curr_max_day:=DATE_FORMAT(STR_TO_DATE(SUBSTRING(@curr_max_part FROM 3),'%Y%m'),'%Y-%m-01');
          SET @nextday:=@curr_max_day + INTERVAL 1 MONTH;

          IF (@nextday >= @new_max_day) THEN
             BEGIN
              SELECT "";
              SELECT "# No partitions to create.";
              SELECT "";
             END;
          ELSE
             BEGIN

              SELECT CONCAT('USE ',i_db,';');
              SELECT CONCAT('ALTER TABLE ', i_db, '.', i_tablename, ' REORGANIZE PARTITION p_max INTO (');
              SET @stmt1:=CONCAT('SET @todays_nextday:=', i_date_function, '(@nextday + INTERVAL 1 MONTH)');

              PREPARE stmt1 FROM @stmt1;
              WHILE @nextday < @new_max_day DO

                EXECUTE stmt1;
                SELECT CONCAT("PARTITION p_", LEFT(REPLACE(@nextday,'-',''),6) , " VALUES LESS THAN (", @todays_nextday, ") ENGINE = INNODB,");
                SET @nextday:= @nextday + INTERVAL 1 MONTH;
              END WHILE;
              DEALLOCATE PREPARE stmt1;
              SELECT 'PARTITION p_max VALUES LESS THAN MAXVALUE ENGINE = INNODB);';
         END;
      END IF;
       ELSE
      select 'SELECT "1. Table is not Partitioned,";';
      select 'SELECT "          or";';
      select 'SELECT "2. Partitions are not formatted as p_yyyymm or p_yyyymmdd";';
       END IF;
     END IF;
END

$$

DROP PROCEDURE IF EXISTS `sp_generate_drop_partitions` $$
CREATE DEFINER=`{{db_os_user}}`@`localhost` PROCEDURE `sp_generate_drop_partitions`(
    IN i_db VARCHAR(64),
    IN i_tablename VARCHAR(64),
    IN i_part_name CHAR(10)
)
BEGIN
  DECLARE done INT DEFAULT 0;
  DECLARE v_partname CHAR(10);
  DECLARE v_partlist CHAR(10);

  DECLARE part_cur CURSOR FOR
  SELECT partition_name
    FROM information_schema.partitions
   WHERE table_schema=i_db
     AND table_name=i_tablename
     AND partition_name < i_part_name
     AND (partition_name  REGEXP 'p_[0-9]{4}' OR
          partition_name  REGEXP 'p_[0-9]{6}' OR
          partition_name  REGEXP 'p_[0-9]{8}')
   ORDER BY partition_name DESC;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
  OPEN part_cur;
  SET @v_partlist:=NULL;
  REPEAT
    FETCH part_cur INTO v_partname;
    IF NOT done THEN
       SET @v_partlist:=CONCAT_WS(',' , v_partname, @v_partlist);

    END IF;
   UNTIL done END REPEAT;

   IF ISNULL(@v_partlist) THEN
      SELECT CONCAT('# No partitions to drop. We were looking for partitions <="', i_part_name, '". Please verify.');
   ELSE
      SELECT CONCAT('USE ',i_db,';');
      SELECT CONCAT("alter table ", i_db, '.', i_tablename, " drop partition ", @v_partlist, ";");
   END IF;

END
$$

DROP PROCEDURE IF EXISTS `sp_generate_partitions` $$
CREATE DEFINER=`{{db_os_user}}`@`localhost` PROCEDURE `sp_generate_partitions`(
 --   IN i_db VARCHAR(20),
 --   IN i_tablename VARCHAR(20),
    IN i_start_part CHAR(10),
    IN i_interval CHAR(5), -- DAY or MONTH
    IN i_num SMALLINT,
    IN i_date_function VARCHAR(20),
    IN i_date_col VARCHAR(64)

)
BEGIN
    -- call sp_generate_partitions ('2011-01-01','DAY',15,'UNIX_TIMESTAMP','h_action_timestamp')
    -- construct dates out of current max partition and new max partition
    SET @start_part:=STR_TO_DATE(i_start_part, '%Y-%m-%d');    -- '2010-06-01',
    IF (UPPER(i_interval) = "MONTH") THEN
       SET @start_part:=DATE_FORMAT(@start_part, '%Y%m01'); -- '2010-04-01'
       SET @nextday:=@start_part + INTERVAL 0 DAY;
       SELECT CONCAT('/*!50100 PARTITION BY RANGE (', i_date_function, '(',i_date_col, ')) (');
       SELECT 'PARTITION p_min VALUES LESS THAN (0) ENGINE = InnoDB,';
       SET @stmt1:=CONCAT('SET @todays_nextday:=', i_date_function, '(@nextday + INTERVAL 1 MONTH)');
       #SELECT @stmt1;
       PREPARE stmt1 FROM @stmt1;
       WHILE i_num > 0 DO
         -- SET @todays_nextday:=TO_DAYS(@nextday + INTERVAL 1 MONTH);
         -- pass date function and column name and use prepared statement for this
         EXECUTE stmt1;
         -- SET @todays_nextday:=unix_timestamp(@nextday + INTERVAL 1 MONTH);
         -- select i_num, @start_part, @nextday,   @todays_nextday;
         SELECT CONCAT("PARTITION p_",REPLACE(SUBSTRING(@nextday,1,7) ,'-','') , " VALUES LESS THAN (", @todays_nextday, ") ENGINE = INNODB,");
         SET @nextday:= @nextday + INTERVAL 1 MONTH;
         SET i_num:=i_num - 1;
       END WHILE;
       DEALLOCATE PREPARE stmt1;
       SELECT 'PARTITION p_max VALUES LESS THAN MAXVALUE ENGINE = INNODB) */;';
    ELSE
       IF (UPPER(i_interval) = "DAY") THEN
          SET @start_part:=DATE_FORMAT(@start_part, '%Y%m%d'); -- '2010-04-01'
          SET @nextday:=@start_part + INTERVAL 0 DAY;
          SELECT CONCAT('/*!50100 PARTITION BY RANGE (', i_date_function, '(',i_date_col, ')) (');
          SELECT 'PARTITION p_min VALUES LESS THAN (0) ENGINE = InnoDB,';
          SET @stmt1:=CONCAT('SET @todays_nextday:=', i_date_function, '(@nextday + INTERVAL 1 DAY)');
          #SELECT @stmt1;
          WHILE i_num > 0 DO
             PREPARE stmt1 FROM @stmt1;
             EXECUTE stmt1;
             -- select i_num, @start_part, @nextday,   @todays_nextday;
             SELECT CONCAT("PARTITION p_",REPLACE(SUBSTRING(@nextday,1,10) ,'-','') , " VALUES LESS THAN (", @todays_nextday, ") ENGINE = INNODB,");
             SET @nextday:= @nextday + INTERVAL 1 DAY;
             SET i_num:=i_num - 1;
          END WHILE;
          DEALLOCATE PREPARE stmt1;
          SELECT 'PARTITION p_max VALUES LESS THAN MAXVALUE ENGINE = INNODB) */;';
       ELSE
          SELECT "Incorrect interval ", i_interval;
       END IF;
     END IF;
END
$$

DROP PROCEDURE IF EXISTS `sp_list_partitioned_tables_nc` $$
CREATE DEFINER=`{{db_os_user}}`@`localhost` PROCEDURE `sp_list_partitioned_tables_nc`()
BEGIN
  DECLARE exists_cursor_rows INT DEFAULT 1;
  DECLARE v_db VARCHAR(64) DEFAULT '-' COLLATE utf8_general_ci;
  DECLARE v_cur_db VARCHAR(64) DEFAULT '-';
  DECLARE v_tbl VARCHAR(64) DEFAULT '-' COLLATE utf8_general_ci;
  --
  DECLARE db_table_cur CURSOR FOR
   SELECT table_schema, table_name
     FROM information_schema.partitions
    GROUP BY 1,2
   HAVING COUNT(*) >1 ;
  --
  DECLARE CONTINUE HANDLER FOR SQLSTATE '02000' SET exists_cursor_rows = 0;
  --
  OPEN db_table_cur;
  FETCH db_table_cur INTO v_db, v_tbl;
  SET @sqlmode=@@sql_mode;
  SET @@sql_mode='';
  WHILE exists_cursor_rows
  DO
    IF v_cur_db <> v_db THEN
       SELECT '';
       SELECT CONCAT("- Database : ",v_db);
       SELECT '';
       SELECT CONCAT (RPAD('Table Name',64,' '),
                      RPAD('Partition Expression',40,' '),
                      RPAD('Min Partition',15,' '),
                      RPAD('Max Partition',15,' ')
                    );
       SELECT CONCAT (RPAD(REPEAT('-',10),64,' '),
                      RPAD(REPEAT('-',20),40,' '),
                      RPAD(REPEAT('-',13),15,' '),
                      RPAD(REPEAT('-',13),15,' ')
                    );
    END IF;
    --
    SELECT DISTINCT partition_expression
      INTO @partition_expression
      FROM information_schema.partitions
     WHERE BINARY table_schema=v_db AND BINARY table_name=v_tbl;
    --
    SELECT DISTINCT SUBSTRING(partition_expression, LOCATE('(', partition_expression) + 1, LOCATE(')', partition_expression) - LOCATE('(', partition_expression) -1)
      INTO @date_col
      FROM information_schema.partitions
     WHERE BINARY table_schema= BINARY v_db
       AND BINARY table_name= BINARY v_tbl
       AND BINARY partition_ordinal_position= BINARY 2;
    --
    SELECT MIN(partition_name),MAX(partition_name)
      INTO @min_partition, @max_partition
      FROM information_schema.partitions
     WHERE BINARY table_schema=BINARY v_db
       AND BINARY table_name=BINARY v_tbl
       AND partition_name NOT IN ('p_0','p_max','p_min')
       AND (partition_name  REGEXP 'p_[0-9]{4}' OR
            partition_name  REGEXP 'p_[0-9]{6}' OR
            partition_name  REGEXP 'p_[0-9]{8}');
    --
    SELECT CONCAT (RPAD(v_tbl,64,' '),
                   RPAD(@partition_expression,40,' '),
                   RPAD(@min_partition,15,' '),
                   RPAD(@max_partition,15,' ')
                   );
    SET v_cur_db:=v_db;
    SET exists_cursor_rows = 1;
    FETCH db_table_cur INTO v_db, v_tbl;
  END WHILE;
  SELECT '';
CLOSE db_table_cur;
SET @@sql_mode=@sqlmode;
END
$$

DROP PROCEDURE IF EXISTS `sp_purge_target_db_target_table_template` $$

CREATE DEFINER=`{{db_os_user}}`@`localhost` PROCEDURE `sp_purge_target_db_target_table_template`(i_maxdate DATETIME, i_sleep_interval SMALLINT)
BEGIN
  SET @rowcount = 0;
  SET @delete_limit = DATE_FORMAT(NOW() - INTERVAL 15 DAY, "%Y-%m-%d");
  SET @max_run_time = NOW() + INTERVAL 8 HOUR;
  SET sql_log_bin=0;
  REPEAT
    DELETE LOW_PRIORITY QUICK FROM target_db.target_table WHERE date_added < i_maxdate AND date_added < @delete_limit
    LIMIT 500;
    SET @rowcount=ROW_COUNT();
    SET @vsleep=SLEEP(i_sleep_interval);
  UNTIL (@rowcount=0 OR TIMESTAMPDIFF(MINUTE, NOW(), @max_run_time) <= 0)
  END REPEAT;
END
$$

delimiter ;

set sql_log_bin=0;
CREATE DATABASE if not exists `dba_audit`;
use dba_audit
show tables;

-- drop table if exists `ip_range`;
CREATE TABLE if not exists `ip_range` (
  `ip_check_id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `user_name` char(16) COLLATE utf8_bin NOT NULL,
  `ip_version` enum('4','6') COLLATE utf8_bin DEFAULT NULL,
  `low_range_char` varchar(32) COLLATE utf8_bin NOT NULL,
  `high_range_char` varchar(32) COLLATE utf8_bin NOT NULL,
  `low_range` varbinary(16) NOT NULL,
  `high_range` varbinary(16) NOT NULL,
  PRIMARY KEY (`ip_check_id`),
  KEY `ix_uname_range` (`user_name`,`low_range`,`high_range`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin COMMENT='user ip ranges';

-- drop table if exists `login_procedure`;
CREATE TABLE if not exists `login_procedure` (
  `user_name` char(16) COLLATE utf8_bin NOT NULL,
  `max_connections` int(11) NOT NULL,
  `audit_flag` bit(1) NOT NULL DEFAULT b'0',
  `ip_check` bit(1) NOT NULL DEFAULT b'0',
  `select_limit` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`user_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin COMMENT='user auditing';


-- drop table if exists `violation_log`;
CREATE TABLE if not exists `violation_log`(
  `log_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_name` char(16) COLLATE utf8_bin NOT NULL,
  `hostname` varchar(150) COLLATE utf8_bin NOT NULL,
  `source_ip` varchar(150) COLLATE utf8_bin NOT NULL,
  `date_added` datetime NOT NULL,
  PRIMARY KEY (`log_id`,`date_added`),
  KEY `ix_user_name` (`user_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin COMMENT='user ip violations'
/*!50100 PARTITION BY RANGE (to_days(date_added))
(PARTITION p_min VALUES LESS THAN (0) ENGINE = InnoDB,
 PARTITION p_20180730 VALUES LESS THAN (737271) ENGINE = InnoDB,
 PARTITION p_20180731 VALUES LESS THAN (737272) ENGINE = InnoDB,
 PARTITION p_20180801 VALUES LESS THAN (737273) ENGINE = InnoDB,
 PARTITION p_20180802 VALUES LESS THAN (737274) ENGINE = InnoDB,
 PARTITION p_20180803 VALUES LESS THAN (737275) ENGINE = InnoDB,
 PARTITION p_20180804 VALUES LESS THAN (737276) ENGINE = InnoDB,
 PARTITION p_20180805 VALUES LESS THAN (737277) ENGINE = InnoDB,
 PARTITION p_20180806 VALUES LESS THAN (737278) ENGINE = InnoDB,
 PARTITION p_20180807 VALUES LESS THAN (737279) ENGINE = InnoDB,
 PARTITION p_20180808 VALUES LESS THAN (737280) ENGINE = InnoDB,
 PARTITION p_20180809 VALUES LESS THAN (737281) ENGINE = InnoDB,
 PARTITION p_20180810 VALUES LESS THAN (737282) ENGINE = InnoDB,
 PARTITION p_20180811 VALUES LESS THAN (737283) ENGINE = InnoDB,
 PARTITION p_20180812 VALUES LESS THAN (737284) ENGINE = InnoDB,
 PARTITION p_20180813 VALUES LESS THAN (737285) ENGINE = InnoDB,
 PARTITION p_20180814 VALUES LESS THAN (737286) ENGINE = InnoDB,
 PARTITION p_20180815 VALUES LESS THAN (737287) ENGINE = InnoDB,
 PARTITION p_20180816 VALUES LESS THAN (737288) ENGINE = InnoDB,
 PARTITION p_20180817 VALUES LESS THAN (737289) ENGINE = InnoDB,
 PARTITION p_max VALUES LESS THAN MAXVALUE ENGINE = InnoDB) */
 ;


-- Live Copy
delimiter $$
drop PROCEDURE if exists dba_audit.simpleproc \G
CREATE DEFINER=`{{db_os_user}}`@`localhost` PROCEDURE dba_audit.simpleproc (OUT set_select_limit bigint Unsigned)
proc_label:begin
    DECLARE user_host varchar(150);
    DECLARE ip_check_a BIT;
    DECLARE count_holder INT(11);
    DECLARE select_limit_count bigint(20);
    DECLARE user_name01 varchar(150);

    select SUBSTRING_INDEX(user(),'@', -1) into user_host ;
    select SUBSTRING_INDEX(user(),'@', 1) into user_name01 ;
    select ip_check, select_limit into ip_check_a, select_limit_count from dba_audit.login_procedure  where user_name =  user_name01  LIMIT 1;

    if ip_check_a = 1 and ip_check_a IS NOT NULL then
        select 1 into count_holder  from dba_audit.ip_range where INET6_ATON(user_host) between low_range and high_range and user_name=user_name01 LIMIT 1;
        if  ISNULL(count_holder) then
            insert into dba_audit.violation_log (  user_name, hostname, source_ip, date_added) values(SUBSTRING_INDEX(user(),'@', 1), substring(@@global.hostname from 1 for 150),  SUBSTRING_INDEX(user(),'@', -1), now() );
            kill CONNECTION_ID();
        end if;
    end if;

SET set_select_limit=IF((SELECT CASE WHEN ifnull(select_limit_count, 0) > 0 THEN 1 ELSE 0 END),  select_limit_count,  18446744073709551615);

end $$
delimiter ;