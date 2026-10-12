set sql_log_bin=0;
create user IF NOT EXISTS '{{ UK_HEALTH_USER }}'@'localhost' IDENTIFIED WITH 'mysql_native_password' by  '{{ UK_HEALTH_PASSWD }}';
create user IF NOT EXISTS '{{ CKDBA_USER }}'@'{{ admin_db_host }}' IDENTIFIED WITH 'mysql_native_password' by  '{{ CKDBA_PASS }}';
create user IF NOT EXISTS '{{ CKDBA_USER }}'@'192.%' IDENTIFIED WITH 'mysql_native_password' by  '{{ CKDBA_PASS }}';
create user IF NOT EXISTS '{{ CKDBA_USER }}'@'localhost' IDENTIFIED WITH 'mysql_native_password' by  '{{ CKDBA_PASS }}';
create user IF NOT EXISTS '{{ BACKUP_USER }}'@'localhost' IDENTIFIED WITH 'mysql_native_password' by  '{{ BACKUP_PASS }}';
create user IF NOT EXISTS '{{ REPL_USER }}'@'10.%' IDENTIFIED WITH 'mysql_native_password' by  '{{ REPL_PASS }}';
create user IF NOT EXISTS '{{ REPL_USER }}'@'192.%' IDENTIFIED WITH 'mysql_native_password' by  '{{ REPL_PASS }}';
create user IF NOT EXISTS '{{ METRICS_USER }}'@'localhost' IDENTIFIED WITH 'mysql_native_password' by  '{{ METRICS_PASS }}';
create user IF NOT EXISTS '{{ SPLUNK_DB_USER }}'@'10.%' IDENTIFIED WITH 'mysql_native_password' by  '{{ SPLUNK_DBA_PASS }}';
create user IF NOT EXISTS '{{ SPLUNK_DB_USER }}'@'192.%' IDENTIFIED WITH 'mysql_native_password' by  '{{ SPLUNK_DBA_PASS }}';
create user IF NOT EXISTS '{{ SPLUNK_DB_USER }}'@'localhost' IDENTIFIED WITH 'mysql_native_password' by  '{{ SPLUNK_DBA_PASS }}';

{% if deploy_admin_db != 'no'  %}
create user IF NOT EXISTS 'toolsuser'@'10.%' IDENTIFIED WITH 'mysql_native_password' by  '{{ TOOL_USER_PASS }}';
create user IF NOT EXISTS 'toolsuser'@'192.%' IDENTIFIED WITH 'mysql_native_password' by  '{{ TOOL_USER_PASS }}';
create user IF NOT EXISTS 'toolsuser'@'localhost' IDENTIFIED WITH 'mysql_native_password' by  '{{ TOOL_USER_PASS }}';
{% endif %}


{% if ( (is_mysql57|bool and true)  or  (is_mysql56|bool and true)  or  (is_mysql55|bool and true) or (is_mariadb|bool and true) ) %}
grant replication slave, replication client on *.* to '{{REPL_USER}}'@'%'  identified by '{{ REPL_PASS }}'  ;
grant replication slave, replication client on *.* to '{{REPL_USER}}'@'10.%'  identified by '{{ REPL_PASS }}'  ;
grant replication slave, replication client on *.* to '{{REPL_USER}}'@'192.%'  identified by '{{ REPL_PASS }}'  ;
GRANT PROCESS, REPLICATION CLIENT ON *.* TO '{{ UK_HEALTH_USER }}'@'localhost'  identified by '{{ UK_HEALTH_PASSWD }}'  ;
GRANT ALL on *.* to '{{ CKDBA_USER }}'@'{{ admin_db_host }}'  identified by '{{ CKDBA_PASS }}'   WITH GRANT OPTION;
GRANT ALL on *.* to '{{ CKDBA_USER }}'@'192.%'  identified by '{{ CKDBA_PASS }}'   WITH GRANT OPTION;
GRANT ALL on *.* to '{{ CKDBA_USER }}'@'localhost'  identified by '{{ CKDBA_PASS }}'   WITH GRANT OPTION;
GRANT SELECT, PROCESS ON *.* TO '{{ SPLUNK_DB_USER }}'@'10.%'  identified by '{{ SPLUNK_DBA_PASS }}'  ;
GRANT SELECT, PROCESS ON *.* TO '{{ SPLUNK_DB_USER }}'@'192.%' identified by '{{ SPLUNK_DBA_PASS }}'  ;
GRANT SELECT, PROCESS ON *.* TO '{{ SPLUNK_DB_USER }}'@'localhost' identified by '{{ SPLUNK_DBA_PASS }}'  ;

{% if deploy_admin_db != 'no'  %}
GRANT SELECT, INSERT, UPDATE, DELETE ON `ckadmin`.*  TO 'toolsuser'@'10.%'  identified by '{{ TOOL_USER_PASS }}'  ;
GRANT SELECT, INSERT, UPDATE, DELETE ON `ckadmin`.*  TO 'toolsuser'@'192.%' identified by '{{ TOOL_USER_PASS }}'  ;
GRANT SELECT, INSERT, UPDATE, DELETE ON `ckadmin`.*  TO 'toolsuser'@'localhost' identified by '{{ TOOL_USER_PASS }}'  ;
{% endif %}

GRANT PROCESS ON *.* TO '{{ METRICS_USER }}'@'localhost' identified by '{{ METRICS_PASS }}'   ;
GRANT SELECT, RELOAD, PROCESS, SUPER, LOCK TABLES, REPLICATION SLAVE, REPLICATION CLIENT, SHOW VIEW ON *.* TO '{{ BACKUP_USER }}'@'localhost'  identified by '{{ BACKUP_PASS }}'  ;
{% else %}
grant replication slave, replication client on *.* to '{{REPL_USER}}'@'10.%';
grant replication slave, replication client on *.* to '{{REPL_USER}}'@'192.%';
GRANT PROCESS, REPLICATION CLIENT ON *.* TO '{{ UK_HEALTH_USER }}'@'localhost';
GRANT ALL on *.* to '{{ CKDBA_USER }}'@'{{ admin_db_host }}' WITH GRANT OPTION;
GRANT ALL on *.* to '{{ CKDBA_USER }}'@'192.%' WITH GRANT OPTION;
GRANT ALL on *.* to '{{ CKDBA_USER }}'@'localhost' WITH GRANT OPTION;
GRANT SELECT, PROCESS ON *.* TO '{{ SPLUNK_DB_USER }}'@'10.%';
GRANT SELECT, PROCESS ON *.* TO '{{ SPLUNK_DB_USER }}'@'192.%';
GRANT SELECT, PROCESS ON *.* TO '{{ SPLUNK_DB_USER }}'@'localhost';

{% if deploy_admin_db != 'no'  %}
GRANT SELECT, INSERT, UPDATE, DELETE ON `ckadmin`.*  TO 'toolsuser'@'10.%'    ;
GRANT SELECT, INSERT, UPDATE, DELETE ON `ckadmin`.*  TO 'toolsuser'@'192.%'  ;
GRANT SELECT, INSERT, UPDATE, DELETE ON `ckadmin`.*  TO 'toolsuser'@'localhost'  ;
{% endif %}

GRANT PROCESS ON *.* TO '{{ METRICS_USER }}'@'localhost';
GRANT SELECT, RELOAD, PROCESS, SUPER, LOCK TABLES, REPLICATION SLAVE, REPLICATION CLIENT, SHOW VIEW ON *.* TO '{{ BACKUP_USER }}'@'localhost';
{% endif %}
flush privileges;

