#!/bin/bash
# =============================================================================
# 
# WARNING! THIS FILE IS MANAGED BY SALT! 
#  
# Any edits to this file will be lost next time salt runs. 
# If you need to modify this file for any reason please contact ops team. 
# operations@creditkarma.com 
# =============================================================================

# This script should be used to collect MySQL stats like processlist, innodb status and global status.
script_name=$(basename $0);
lock_file="/tmp/script_${script_name}.lock"

remove_lock_file(){
    rm  -f ${lock_file}
}

# by checking if script's lock file exists
if [ -e  ${lock_file} ]; then
  echo "script [${script_name}] is already running with lock file: [${lock_file}]";
  exit 0;
else
# create a lock file
  touch ${lock_file};
fi

trap remove_lock_file INT TERM EXIT

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"
. ${PARAMETER_FILE}

re='^[0-9]+$'

if [[ $1 = '' ]]; then
    typeset time_increment=59
elif [[ ! $1 =~ $re ]]; then
    echo $1
    echo "Invalid argument"
    exit 1
else
    typeset time_increment=$1
fi

LOGDIR=/var/log/mysql_stats

[ ! -d $LOGDIR ] && mkdir $LOGDIR

typeset timer=0
typeset cycle_end=59

while (($timer<$cycle_end))
do

    {% if  ( mysqld_multi_running )   -%}
    cat /etc/my.cnf|grep -i ^port|awk '{print $3}'|while read port                                                                                                                                                                                                             
    
    do

      HOST=`hostname`
      host_info=`timeout 4 mysql -h ${LOCAL_OPSDB} -u $METRICS_USER -p$METRICS_PASSWD -NB -e"select concat(instanceName, ':' ,socket) from ckadmin.host_info where fqdn = '$HOST' and port = '$port'"`
              
      socket=`echo $host_info | cut -d':' -f2`
      instance=`echo $host_info | cut -d':' -f1`

      timeout 4 mysql -u $METRICS_USER -p$METRICS_PASSWD -S $socket -NB -e"show processlist" > $LOGDIR/`date "+%Y%m%d_%H%M%S"`_${HOST}_${instance}_processlist.out

    if [[ $timer = 0 ]]; then

      timeout 4 mysql -u $METRICS_USER -p$METRICS_PASSWD -S $socket -NB -e"show engine innodb status\G" > $LOGDIR/`date "+%Y%m%d_%H%M%S"`_${HOST}_${instance}_innodb_status.out
      timeout 4 mysql -u $METRICS_USER -p$METRICS_PASSWD -S $socket -NB -e"show global status" > $LOGDIR/`date "+%Y%m%d_%H%M%S"`_${HOST}_${instance}_global_status.out

        [ $? -ne 0 ] && echo "Error occurred while fetching data " && exit 1

    fi

    done

    {%- else %}
      port="3306"
      HOST=`hostname`
      host_info=`timeout 4 mysql -h ${LOCAL_OPSDB} -u $METRICS_USER -p$METRICS_PASSWD -NB -e"select concat(instanceName, ':' ,socket) from ckadmin.host_info where fqdn = '$HOST' and port = '$port'"`
              
      socket=`echo $host_info | cut -d':' -f2`
      instance=`echo $host_info | cut -d':' -f1`

      timeout 4 mysql -u $METRICS_USER -p$METRICS_PASSWD -S $socket -NB -e"show processlist" > $LOGDIR/`date "+%Y%m%d_%H%M%S"`_${HOST}_${instance}_processlist.out

    if [[ $timer = 0 ]]; then

      timeout 4 mysql -u $METRICS_USER -p$METRICS_PASSWD -S $socket -NB -e"show engine innodb status\G" > $LOGDIR/`date "+%Y%m%d_%H%M%S"`_${HOST}_${instance}_innodb_status.out
      timeout 4 mysql -u $METRICS_USER -p$METRICS_PASSWD -S $socket -NB -e"show global status" > $LOGDIR/`date "+%Y%m%d_%H%M%S"`_${HOST}_${instance}_global_status.out

        [ $? -ne 0 ] && echo "Error occurred while fetching data " && exit 1

    fi

    {%- endif %}

    timer=$((timer+time_increment))
    if (($timer>=$cycle_end)); then
        break
    fi

    sleep $time_increment

done

# Deleting older log files.
find $LOGDIR -name "*.out" -mtime 0.5 | xargs gzip -f -q
find $LOGDIR -name "*.gz" -mtime 2 -exec rm {} \;
