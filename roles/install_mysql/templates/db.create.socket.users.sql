-- location: /tmp/db.create.socket.users.sql
set sql_log_bin=0;
create user IF NOT EXISTS '{{db_os_user}}'@'localhost' identified with 'auth_socket';
create user IF NOT EXISTS '{{db_os_user}}'@'127.0.0.1' identified with 'auth_socket';
create user '{{db_os_user}}'@'localhost' identified with 'auth_socket';
create user '{{db_os_user}}'@'127.0.0.1' identified with 'auth_socket';
GRANT ALL PRIVILEGES ON *.* TO '{{db_os_user}}'@'localhost'   WITH GRANT OPTION;
GRANT PROXY ON ''@'' TO '{{db_os_user}}'@'localhost'    WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO '{{db_os_user}}'@'127.0.0.1'   WITH GRANT OPTION;
GRANT PROXY ON ''@'' TO '{{db_os_user}}'@'127.0.0.1'   WITH GRANT OPTION;
flush privileges;


