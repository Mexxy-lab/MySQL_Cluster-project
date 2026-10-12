set sql_log_bin=0;
INSTALL PLUGIN auth_socket SONAME 'auth_socket.so';
INSTALL PLUGIN auth_pam SONAME 'auth_pam.so';
INSTALL PLUGIN auth_pam_compat SONAME 'auth_pam_compat.so';
alter user  'root'@'localhost' identified  with 'auth_socket';
create user IF NOT EXISTS '{{db_os_user}}'@'localhost' identified with 'auth_socket';
create user IF NOT EXISTS '{{db_os_user}}'@'127.0.0.1' identified with 'auth_socket';
create user IF NOT EXISTS '{{db_os_user}}'@'localhost' identified with 'auth_socket';
create user IF NOT EXISTS '{{db_os_user}}'@'127.0.0.1' identified with 'auth_socket';
create user IF NOT EXISTS 'nrpe'@'localhost' identified with 'auth_socket';
create user IF NOT EXISTS 'nrpe'@'127.0.0.1' identified with 'auth_socket';
GRANT ALL PRIVILEGES ON *.* TO '{{db_os_user}}'@'localhost';
GRANT ALL PRIVILEGES ON *.* TO '{{db_os_user}}'@'127.0.0.1';
GRANT ALL PRIVILEGES ON *.* TO 'nrpe'@'localhost';
GRANT ALL PRIVILEGES ON *.* TO 'nrpe'@'127.0.0.1';

{% if ( (is_mysql57|bool and true)  or  (is_mysql56|bool and true)  or  (is_mysql55|bool and true) or (is_mariadb|bool and true) ) %}
UPDATE mysql.user SET plugin = 'auth_socket' WHERE User = 'root';
grant replication slave, replication client on *.* to '{{rep_user}}'@'%' identified by '{{rep_pass}}';
grant select on dbadb.* to '{{rep_user}}'@'%';
GRANT ALL PRIVILEGES ON *.* TO '{{db_os_user}}'@'localhost' identified with 'auth_socket';
GRANT ALL PRIVILEGES ON *.* TO '{{db_os_user}}'@'127.0.0.1' identified with 'auth_socket';
GRANT ALL PRIVILEGES ON *.* TO 'nrpe'@'localhost' identified with 'auth_socket';
GRANT ALL PRIVILEGES ON *.* TO 'nrpe'@'127.0.0.1' identified with 'auth_socket';
{% else %}
CREATE USER IF NOT EXISTS '{{rep_user}}'@'%' identified by '{{rep_pass}}';
ALTER USER  '{{rep_user}}'@'%'   IDENTIFIED WITH 'mysql_native_password' by '{{rep_pass}}';
grant replication slave, replication client on *.* to '{{rep_user}}'@'%';
grant select on dbadb.* to '{{rep_user}}'@'%';
{% endif %}
flush privileges;


