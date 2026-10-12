grant select on *.* to 'spider_app'@'%' identified by password '*386F174CA1AC16D446BCE182F36B889E69519C27';
grant process on *.* to spider_app@'%';
grant REPLICATION CLIENT on *.* to spider_app@'%';
-- grant all on *.* to dbamaint@'%' identified by PASSWORD '*5E8900B051733DE278736A2C6AE68F8778E0505A';
grant all on *.* to dbadmin@'%' identified by PASSWORD '*501442BDF895DE8E2DAA6D003ED76A03BCFE0470' WITH GRANT OPTION; 
create database dbadb;
GRANT USAGE ON *.* TO 'lbmon'@'%' IDENTIFIED BY PASSWORD '*85505506CDEB293F2B41E11D54AD5F7F6E6700E0';
GRANT SELECT ON `dbadb`.* TO 'lbmon'@'%' ;
flush privileges;
