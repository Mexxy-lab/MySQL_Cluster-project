#!/usr/bin/env bash

db_os_user_homedir="{{ db_os_user_homedir }}"
profile_file="{{ db_os_user_homedir }}/.profile"
overwrite_db="{{ mysql_db_overwrite }}"
db_user="{{ db_os_user }}"
db_group="{{ dbadmin_group }}"


function modify_sys {
    find /usr/local/lib64  -type d -exec chmod 755 {} +
    # change disk io scheduler to noop...
    for x in `ls -d /sys/block/sd*`; do  if test -f $x/queue/scheduler; then echo 'cfq'  >  $x/queue/scheduler; fi done

    ## Set swappiness to 1 for Linux kernel versions 2.6.32 and above
    ## and to 0 for versions less than 2.6.32

    LINUX_KERNEL_VERSION=$( uname -r | cut -d '.' -f1,2,3 --output-delimiter='' | cut -d '-' -f1)

    if test $LINUX_KERNEL_VERSION -ge 2632 && ! sysctl -a | grep -P 'vm\.swappiness\s*=\s*1\b' ; then
        if grep -P 'vm\.swappiness\s*=' /etc/sysctl.conf; then
            if grep -P 'vm\.swappiness\s*=\s*1\b' /etc/sysctl.conf; then
                echo good > /dev/null;
            else
                perl -p -i -e 's/vm\.swappiness\s*=\s*.*/vm.swappiness = 1/'   /etc/sysctl.conf
                # now reload sysctl.conf file:
                sysctl -e -p
            fi
        else
            echo 'vm.swappiness = 1'  >> /etc/sysctl.conf
            sysctl -e -p
        fi
    elif test $LINUX_KERNEL_VERSION -lt 2632 &&  ! sysctl -a | grep -P 'vm\.swappiness\s*=\s*0\b'; then
        if grep -P 'vm\.swappiness\s*=' /etc/sysctl.conf; then
            if grep -P 'vm\.swappiness\s*=\s*0\b' /etc/sysctl.conf; then
                echo good > /dev/null;
            else
                perl -p -i -e 's/vm\.swappiness\s*=\s*.*/vm.swappiness = 0/'   /etc/sysctl.conf
                # now reload sysctl.conf file:
                sysctl -e -p
            fi
        else
            echo 'vm.swappiness = 0'  >> /etc/sysctl.conf
            sysctl -e -p
        fi
    fi
}

function install_perl_mod {
    export PERL_MM_USE_DEFAULT=1        # Accept Defaults
    cd ${db_os_user_homedir}/.tmp
    tar -xzvf MIME-Lite-3.030.tar.gz
    cd MIME-Lite-3.030
    perl Makefile.PL
    make
    make test
    make install
    if test $? -eq 0; then
        cd
        rm -f ${db_os_user_homedir}/.tmp/MIME-Lite-3.030.tar.gz
        touch ${db_os_user_homedir}/.tmp/perl_mod_installed_do_not_remove.txt
    fi
}

function set_up_mysql_dirs_misc {
    . ${profile_file}
    mkdir -p ${DATADIR}   &&  chown -R ${db_user}:${db_group}  ${DATADIR}       && chmod 755 ${DATADIR}
    {% if deploy_using_ck_dir_structure != 'no'  %}
        mkdir -p ${BINARY_LOG_DIR} &&  chown -R ${db_user}:${db_group}  ${BINARY_LOG_DIR}       && chmod 755  ${BINARY_LOG_DIR}
        mkdir -p ${RELAY_LOG_DIR} &&  chown -R ${db_user}:${db_group}  ${RELAY_LOG_DIR}       && chmod 755  ${RELAY_LOG_DIR}
        mkdir -p ${GENERAL_LOG_DIR} &&  chown -R ${db_user}:${db_group}  ${GENERAL_LOG_DIR}       && chmod 755  ${GENERAL_LOG_DIR}
        mkdir -p ${SLOW_LOG_DIR} &&  chown -R ${db_user}:${db_group}  ${SLOW_LOG_DIR}       && chmod 755  ${SLOW_LOG_DIR}
        mkdir -p {{ tmpdir }} &&  chown -R ${db_user}:${db_group}  {{ tmpdir }}       && chmod 755  {{ tmpdir }}
    {% endif %}
    mkdir -p ${CFG_LOC}   &&  chown -R ${db_user}:${db_group}  ${CFG_LOC}       && chmod 755 ${CFG_LOC}
    mkdir -p ${LOG_LOC}   &&  chown -R ${db_user}:${db_group}  ${LOG_LOC}       && chmod 755 ${LOG_LOC}
    mkdir -p ${ARCH_LOC}   &&  chown -R ${db_user}:${db_group}  ${ARCH_LOC}     && chmod 755 ${ARCH_LOC}
    mkdir -p ${INNO_LOC}   &&  chown -R ${db_user}:${db_group}  ${INNO_LOC}     && chmod 755 ${INNO_LOC}
    mkdir -p ${TMP_LOC}   &&  chown -R ${db_user}:${db_group}   ${TMP_LOC}      && chmod 755 ${TMP_LOC}
    mkdir -p ${BIN_LOC}   &&  chown -R ${db_user}:${db_group}   ${BIN_LOC}      && chmod 755 ${BIN_LOC}
    mkdir -p ${CERT_LOC}   &&  chown -R ${db_user}:${db_group}  ${CERT_LOC}
    mkdir -p ${BACKUP_LOC}   &&  chown -R ${db_user}:${db_group}  ${BACKUP_LOC} && chmod 755    ${BACKUP_LOC}
    mkdir -p ${HOMEDIR}/${INSTANCE_NAME}/create   &&  chown -R ${db_user}:${db_group}   ${HOMEDIR}/${INSTANCE_NAME}/create       && chmod 755 ${HOMEDIR}/${INSTANCE_NAME}
    mkdir -p ${HOMEDIR}/${INSTANCE_NAME}/release   &&  chown -R ${db_user}:${db_group}  ${HOMEDIR}/${INSTANCE_NAME}/release
    if echo "${overwrite_db}" | grep YES; then
        rm -rf ${DATADIR}/*
        rm -rf ${CFG_LOC}/*
        rm -rf ${LOG_LOC}/*
        rm -rf ${ARCH_LOC}/*
        rm -rf ${INNO_LOC}/*
        rm -rf ${TMP_LOC}/*
        rm -rf ${BIN_LOC}/*
        rm -rf ${BACKUP_LOC}/*
    fi
}


function start_mysql_5_7_or_latest {
    . ${profile_file}
    # Check that the mysql system databases(mysql and performance_schema) exists:
    if [[ ! -d ${DATADIR}/mysql ]] || [[ !  -d ${DATADIR}/performance_schema ]]  ;  then
        nohup mysqld --defaults-file=${CNF_FILE} --basedir={{basedir}} --datadir=${DATADIR} --initialize
        nohup mysqld --defaults-file=${CNF_FILE} >> ${LOG_LOC}/startup_{{sid}}.log 2>&1 &
        sleep 25
        passwd=`grep 'temporary password' $ERR_LOG | sed -e 's/^.* //' | tail -1`
        timeout 46 mysql -uroot -p${passwd} -S ${SOCKET_FILE} --connect-expired-password -e "alter user root@localhost identified by '${passwd}';"
        timeout 15 mysql -uroot -p${passwd} -S ${SOCKET_FILE}  -BNse "show plugins" 2>/dev/null   | grep -i 'auth_socket' > /dev/null 2>&1 || timeout 15 mysql -uroot -p${passwd} -S ${SOCKET_FILE}  -BNse "INSTALL PLUGIN auth_socket SONAME 'auth_socket.so'" > /dev/null 2>&1
        timeout 15 mysql -uroot -p${passwd} -S ${SOCKET_FILE}  -BNse "alter user  'root'@'localhost' identified  with 'auth_socket'" 2>/dev/null
        timeout 46 mysqladmin -uroot -S ${SOCKET_FILE}   "shutdown"
        sleep 5;
        {% if (  ansible_distribution == "CentOS" and ansible_distribution_major_version >= "7" )  %}
        systemctl enable {{ lc_sid }} >> /tmp/enable_and_start_mysql_service;
        systemctl status {{ lc_sid }} >>  /tmp/enable_and_start_mysql_service;
        systemctl start {{ lc_sid }} >>  /tmp/enable_and_start_mysql_service;
        {% endif %}
    fi
    if [[  -d ${DATADIR}/mysql ]] && [[  -d ${DATADIR}/performance_schema ]]; then
        if [[ -e $PID_FILE ]]; then
            if ps -p $( cat $PID_FILE ) > /dev/null ; then
                echo "MySQL instance is running"   > /dev/null 2>&1;
                cat $PID_FILE  > /dev/null 2>&1;
             else
                nohup mysqld --defaults-file=${CNF_FILE} >> ${LOG_LOC}/startup_{{sid}}.log 2>&1 &
                sleep 45
             fi
        else
             nohup mysqld --defaults-file=${CNF_FILE} >> ${LOG_LOC}/startup_{{sid}}.log 2>&1 &
             sleep 45
        fi
    fi
}

function start_mysql_5_6_or_earlier {
    . ${profile_file}

    # Initialize the MariaDB system databases if this is a new datadir.
    # Do not start mysqld here. The offbziip1 systemd service owns
    # the MariaDB process and is responsible for starting/stopping it.
    if [[ ! -d ${DATADIR}/mysql ]] || [[ ! -d ${DATADIR}/performance_schema ]]; then
        mysql_install_db --datadir=${DATADIR} --defaults-file=${CNF_FILE}
    fi
}

function load_mysql_time_zone_data {
    . ${profile_file}
    timeout 46 mysql_tzinfo_to_sql /usr/share/zoneinfo > /tmp/tz.sql
    timeout 46 mysql -uroot  -S ${SOCKET_FILE} -e "use mysql;  set sql_log_bin=0; source /tmp/tz.sql;"  && rm /tmp/tz.sql
    # mysql -uroot -S ${SOCKET_FILE} -D mysql < /tmp/tz.sql
}


function change_mysql_5_7_or_latest_root_pass {
    . ${profile_file}
    passwd=`grep 'temporary password' $ERR_LOG | sed -e 's/^.* //' | tail -1`
    if timeout 46 mysql -uroot  -S ${SOCKET_FILE} -e "select @@version" > /dev/null 2>&1 ; then
        # echo "This is re-run - No need to change the root pass" > /dev/null 2>&1;
        rm /tmp/db.chg.root.pwd*.sql

    else
        # echo "This is a fresh install - lets change the pass";
        timeout 46 mysql --connect-expired-password  -uroot -p${passwd} < /tmp/db.chg.root.pwd2.sql &&   rm /tmp/db.chg.root*.pwd.sql
    fi

}

function change_mysql_5_6_or_earlier_root_pass {
    . ${profile_file}
    if timeout 46 mysql -uroot  -S ${SOCKET_FILE} -e "select @@version" > /dev/null 2>&1 ; then
        # echo "This is re-run - No need to change the root pass" > /dev/null 2>&1;
        timeout 46 mysql -uroot  -S ${SOCKET_FILE}  < /tmp/db.chg.root.pwd.sql  && rm /tmp/db.chg.root.pwd.sql

    else
        # echo "This is a fresh install - lets change the pass" > /dev/null 2>&1;
        timeout 46 mysql -uroot -S ${SOCKET_FILE} < /tmp/db.chg.root.pwd.sql  &&     rm /tmp/db.chg.root.pwd.sql
    fi

}


function update_mysql_instance_owner_profile_file {
    sed -i 's/alias myroot.*/alias myroot="mysql -c -uroot -p`cat ${CFG_LOC}\/.pswd` -S ${SOCKET_FILE} -hlocalhost" /'   ${profile_file}
}

function secure_mysql_instance {
    . ${profile_file}
    timeout 46 mysql -uroot  -S ${SOCKET_FILE} -e "set sql_log_bin=0; DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
    # drop test database
    timeout 46 mysql -uroot  -S ${SOCKET_FILE} -e "set sql_log_bin=0; DROP database IF EXISTS test"
    timeout 46 mysql -uroot  -S ${SOCKET_FILE} -e "set sql_log_bin=0; DELETE FROM mysql.user WHERE User=''"
    timeout 46 mysql -uroot  -S ${SOCKET_FILE} -e "set sql_log_bin=0; DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'"
    timeout 46 mysql -uroot  -S ${SOCKET_FILE} -e "set sql_log_bin=0; FLUSH PRIVILEGES"
}

function create_requisite_mysql_users {
    . ${profile_file}
    if timeout 15 mysql -uroot  -S ${SOCKET_FILE}  -BNse "show variables like 'version_comment'" 2>/dev/null  |  grep -i 'percona' > /dev/null 2>&1 ; then
            if  timeout 15 mysql -uroot  -S ${SOCKET_FILE}  -BNse "show variables like 'version'" 2>/dev/null  |  grep -i '5.7' > /dev/null 2>&1 ; then
               timeout 15 mysql -uroot  -S ${SOCKET_FILE}  -BNse "show plugins" 2>/dev/null   | grep -i 'auth_socket' > /dev/null 2>&1 || timeout 15 mysql -uroot  -S ${SOCKET_FILE}  -BNse "INSTALL PLUGIN auth_socket SONAME 'auth_socket.so'" > /dev/null 2>&1
               timeout 11 mysql -f -uroot  -S ${SOCKET_FILE} < /tmp/db.create.users.sql   &&     rm /tmp/db.create.users.sql
               timeout 11 mysql -f -uroot  -S ${SOCKET_FILE} < /tmp/ck_db.create.users.sql   &&     rm /tmp/ck_db.create.users.sql
               timeout 11 mysql -f -uroot  -S ${SOCKET_FILE} < /tmp/db.create.socket.users.sql   &&     rm /tmp/db.create.socket.users.sql
            fi
    fi

    if [[ -f "/tmp/opsdb.sql" ]] &&   [[ ! -f ${db_os_user_homedir}/.do_not_remove_ckadmin_db_created.txt ]]; then
        timeout 11 mysql -f -uroot  -S ${SOCKET_FILE} < /tmp/opsdb.sql    && touch ${db_os_user_homedir}/.do_not_remove_ckadmin_db_created.txt     &&     rm /tmp/opsdb.sql
    fi
    if [[ -f "/tmp/opsdb2.sql" ]] &&   [[ ! -f ${db_os_user_homedir}/.do_not_remove_ckadmin_db_populated.txt ]]; then
        timeout 11 mysql -f -uroot  -S ${SOCKET_FILE} < /tmp/opsdb2.sql     && touch  ${db_os_user_homedir}/.do_not_remove_ckadmin_db_populated.txt   &&     rm /tmp/opsdb2.sql
    fi
    timeout 11 mysql -f -uroot  -S ${SOCKET_FILE} < /tmp/db.create.socket.users.sql   &&     rm /tmp/db.create.socket.users.sql
    timeout 11 mysql -f -uroot  -S ${SOCKET_FILE} < /tmp/db.create.users.sql          &&     rm /tmp/db.create.users.sql
    timeout 11 mysql -f -uroot  -S ${SOCKET_FILE} < /tmp/ck_db.create.users.sql       &&     rm /tmp/ck_db.create.users.sql
    timeout 11 mysql -f -uroot  -S ${SOCKET_FILE} < /tmp/db_deploy_dba_objects.sql    &&     rm /tmp/db_deploy_dba_objects.sql
    for x in `timeout 11 mysql -f -uroot -S ${SOCKET_FILE} -D  mysql  -BNse " select concat('\\\`', user, '\\\`',  '@',  '\\\`' , host,  '\\\`') from mysql.user where user !='root'"`; do timeout 11 mysql -f -uroot -S ${SOCKET_FILE} -D  mysql  -BNse  "set sql_log_bin=0; grant  execute on procedure dba_audit.simpleproc  to  $x;"; done

}

function shutdown_mysql {
  . ${profile_file}
  timeout 46 mysqladmin -uroot  -S ${SOCKET_FILE}   "shutdown"
}


if echo $1 | grep -i modify_sys ; then
    modify_sys
    exit $?
fi

if echo $1 | grep -i install_perl_mod ; then
    install_perl_mod
    exit $?
fi

if echo $1 | grep -i set_up_mysql_dirs_misc ; then
    set_up_mysql_dirs_misc
    exit $?
fi


if echo $1 | grep -i start_mysql_5_7_or_latest ; then
    start_mysql_5_7_or_latest
    exit $?
fi

if echo $1 | grep -i start_mysql_5_6_or_earlier ; then
    start_mysql_5_6_or_earlier
    exit $?
fi

if echo $1 | grep -i load_mysql_time_zone_data ; then
    load_mysql_time_zone_data
    exit $?
fi

if echo $1 | grep -i change_mysql_5_7_or_latest_root_pass ; then
    change_mysql_5_7_or_latest_root_pass
    exit $?
fi
if echo $1 | grep -i change_mysql_5_6_or_earlier_root_pass ; then
    change_mysql_5_6_or_earlier_root_pass
    exit $?
fi


if echo $1 | grep -i update_mysql_instance_owner_profile_file ; then
    update_mysql_instance_owner_profile_file
    exit $?
fi

if echo $1 | grep -i secure_mysql_instance ; then
    secure_mysql_instance
    exit $?
fi

if echo $1 | grep -i create_requisite_mysql_users; then
    create_requisite_mysql_users
    exit $?
fi

if echo $1 | grep -i install_perl_unsafe_signals; then
    install_perl_unsafe_signals
    exit $?
fi

if echo $1 | grep -i install_crypt_blowfish; then
    install_crypt_blowfish
    exit $?
fi

if echo $1 | grep -i install_mysql_backup_package; then
    install_mysql_backup_package
    exit $?
fi

if echo $1 | grep -i finalize_install_mysql_bckup_pkg; then
    finalize_install_mysql_bckup_pkg
    exit $?
fi

if echo $1 | grep -i shutdown_mysql; then
    shutdown_mysql
    exit $?
fi

