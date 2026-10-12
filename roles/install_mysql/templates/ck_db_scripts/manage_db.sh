#!/bin/bash
# =============================================================================
# 
# WARNING! THIS FILE IS MANAGED BY SALT! 
#  
# Any edits to this file will be lost next time salt runs. 
# If you need to modify this file for any reason please contact ops team. 
# operations@creditkarma.com 
# =============================================================================
###############################################################################
#
# Auther : Ashok Jivani
# Purpose: This script should be used to check/modify certain global variables,  
#          START SLAVE, STOP SLAVE, skip binlogs, skip transactions, 
#          move slaves under their grand parents, create user etc. on given
#          list of database servers. 
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"
COMMON_FUNC_FILE="${SCRIPT_DIR}/common_functions.sh"

. ${PARAMETER_FILE}
. ${COMMON_FUNC_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
HOST_FILE=/tmp/${SCRIPT_NAME}_hostfile.$$
LOG_FILE=/tmp/${SCRIPT_NAME}_log.$$
ERR_FILE=/tmp/${SCRIPT_NAME}_err.$$

#---------------------------------------------------------------------- help --
help(){
  echo '''
  This script should be used to check/modify certain global variables,  
  START SLAVE, STOP SLAVE, skip binlogs, skip transactions,
  move slaves under their grand parents, create user etc. on given list
  of database servers.

  Usage:
  
  $SCRIPT_NAME.sh -d <DATA_CENTER> -g <SHARD_GROUP>

    Required:
        -d or --data-center                    Data Center code (ie. ckw, rs)
        -g or --group                          Group (ie. mono, tkdb, fldb, fodb, budb, ipdb)

    Optional:
        -n or --instance-number                filter by instance_number. (ie 1,2,3 or 1-3,5-9)
        -h or --hostname                       filter by Hostname (ie mdb001.iad1, fodb9.sjc1)
        --set                                  Set Global Variables (ie. read_only=on )
        --show                                 Show Global Variables (ie. read_only, thread_handling)
        --stop-slave                           To stop slave(s)
        --start-slave                          To start slave(s)
        --skip-transactions                    To skip transactions on slave(s) using pt-slave-restart
        --skip-binlog-file                     To skip 1 binlog file on slave(s)
        --fix-repl-on-gtid-crashed-slave       After restarting mysql on crashed slave, When SHOW SLAVE STATUS shows dup key error. This option helps fix the slave
        --change-repl-to-auto-position         On GTID based slave, to change position based replication to auto (master_auto_position=1).
        --move-under-grand-parent              To move slave(s) under it(their) grand parent
        -f or --file                           SQL file path (ie filename, /path/filename)
        -e or --error-num                      Comma separated Error Numbers. Default 1062,1032
        -t or --run-time                       Run time in seconds. Default 5 seconds          

    Example:
  
      To set READ_ONLY:
        $SCRIPT_NAME.sh -d ckw -g budb -n 1-8 --set read_only=on
  
      To show READ_ONLY:
        $SCRIPT_NAME.sh -d ckw -g budb -n 1-8 --show read_only
  
      To start slave:
        $SCRIPT_NAME.sh -d ckw -g budb -n 1-8 --start-slave
  
      To run SQLs like CREATE USER or set parameters through file:
        $SCRIPT_NAME.sh -d ckw -g budb -n 1-8 -f filename.sql
  
      To skip transaction(s):
        $SCRIPT_NAME.sh -d ckw -g budb -n 1-8 --skip-transactions [ --error-num 1062,1032 | --run-time 10 ]
  
      To skip binary log file:
        $SCRIPT_NAME.sh -d ckw -g budb -n 1-8 --skip-binlog-file
  
      To move host to its grand parent
        $SCRIPT_NAME.sh -d ckw -g budb -n 1-8 --move-under-grand-parent
  
      To fix replication isues on crashed slave
        $SCRIPT_NAME.sh -d ckw -g budb -n 1-8 --fix-repl-on-gtid-crashed-slave
  
      To change replicaiton to auto_position=1
        $SCRIPT_NAME.sh -d ckw -g budb -n 1-8 --change-replication-to-auto-position
  '''
}

#-------------------------------------------------------------- process_args --
process_args() {
  
  options=$@
  # An array with all the arguments
  args=($options)
  [[ $args == "--help" || $args == "" ]] && help && exit 1

  QRY=""
  JOB=""
  for arg in $options
  do
     if [[ ${args[$i]:0:1} == "-" && ${args[$i+1]:0:1} != "-" ]]
     then
        case ${args[$i]} in
             -d | --data-center )                     V_DATA_CENTER=${args[$i+1]};;
             -g | --group )                           V_GROUP=${args[$i+1]};;
             -n | --instance-number )                 V_INSTANCE_NUMBER=${args[$i+1]};;
             -h | --hostname )                        V_HOSTNAME=${args[$i+1]};;
             -f | --file )                            V_SQL_FILE=${args[$i+1]};; 
             --set )                                  V_SET_GLOBAL=${args[$i+1]};; 
             --show )                                 V_SHOW_GLOBAL=${args[$i+1]};;
             --get-gtid-set )                         V_GET_GTID_SET="Y";;
             --set-gtid-set )                         V_SET_GTID_SET="Y";;
             --stop-slave )                           V_STOP_SLAVE="Y";;
             --start-slave )                          V_START_SLAVE="Y";; 
             --skip-transactions )                    V_SKIP_TRX="Y";;
             --skip-binlog-file )                     V_SKIP_BINLOG="Y";;
             --move-under-grand-parent )              V_MOVE_SLAVE="Y";;
             --fix-repl-on-gtid-crashed-slave )       V_FIX_REPL_ON_GTID_CRASHED_SLAVE="Y";;
             --change-repl-to-auto-position )         V_CHANGE_REPL_TO_AUTO_POSITION="Y";;
             -e | --error-num )                       V_ERROR_NUM=${args[$i+1]};; 
             -t | --run-time )                        V_RUNTIME=${args[$i+1]};;
             *)                                       echo "Invalid option '${args[$i]}'" && exit 1;;
        esac
        i=$(($i+2))
    else
          case ${args[$i]} in
             --get-gtid-set )                         V_GET_GTID_SET="Y";;
             --set-gtid-set )                         V_SET_GTID_SET="Y";;
             --stop-slave )                           V_STOP_SLAVE="Y";;
             --start-slave )                          V_START_SLAVE="Y";; 
             --skip-transactions )                    V_SKIP_TRX="Y";;
             --skip-binlog-file )                     V_SKIP_BINLOG="Y";;
             --move-under-grand-parent )              V_MOVE_SLAVE="Y";;
             --fix-repl-on-gtid-crashed-slave )       V_FIX_REPL_ON_GTID_CRASHED_SLAVE="Y";;
             --change-repl-to-auto-position )         V_CHANGE_REPL_TO_AUTO_POSITION="Y";;
          esac
          i=$(($i+1))
    fi
  done

  [ -z "${V_DATA_CENTER}" ] && echo "Please specify 'Data Center' for -d option. See --help for help" && exit 1
  [ -z "${V_GROUP}" ] && echo "Please specify 'Group' for -g option. See --help for help" && exit 1
  [ -z "${V_ERROR_NUM}" ] && V_ERROR_NUM="1062,1032"
  [ -z "${V_RUNTIME}" ] && V_RUNTIME=5
 
  RANGE=""
  [ ! -z "${V_DATA_CENTER}" ] && DCENTERS=`echo $V_DATA_CENTER | sed "s/,/','/g"` && RANGE="where dataCenter in ('$DCENTERS')"
  [ ! -z "${V_GROUP}" ] && GRPS=`echo $V_GROUP | sed "s/,/','/g"` && RANGE="$RANGE and groupName in ('$GRPS')"
  [ ! -z "${V_INSTANCE_NUMBER}" ] && RANGE="$RANGE and shardNumber in (`echo $V_INSTANCE_NUMBER | awk 'BEGIN { RS=","; FS="-"; ORS="" } NR > 1 { print "," } NF > 1  { for (i=$1; i<$2; ++i) { print i "," } print $2; next } { print $1 }'`)"
  [ ! -z "${V_HOSTNAME}" ] && HOSTS=`echo $V_HOSTNAME | sed "s/,/','/g"` && RANGE="$RANGE and hostname in ('$HOSTS')"

  mysql -NB -e"select concat(fqdn, \":\", port) from $ADMIN_SCHEMA.$ADMIN_TABLE $RANGE" > $HOST_FILE
  [ ! -s $HOST_FILE ] && echo "Please check if 'Data Center' and/or 'Shard Group' is valid." && exit 1

  # Checking that only one input job is given.
  JOB_CNT=0
  [[ ! -z "${V_SET_GLOBAL}" ]] && QRY="set global ${V_SET_GLOBAL};" && JOB_CNT=$(( JOB_CNT+1 ))
  [[ "${V_SET_GLOBAL}" == 'read_only'* ]] && QRY="flush tables with read lock; $QRY unlock tables;" 
  [[ ! -z "${V_SHOW_GLOBAL}" ]] && QRY="show global variables like '${V_SHOW_GLOBAL}';" && JOB_CNT=$(( JOB_CNT+1 ))
  [[ ! -z "${V_SQL_FILE}" ]] && QRY=`cat $V_SQL_FILE` && JOB_CNT=$(( JOB_CNT+1 ))
  [[ ! -z "${V_GET_GTID_SET}" ]] && JOB="Get GTID_EXECUTED;" && JOB_CNT=$(( JOB_CNT+1 ))
  [[ ! -z "${V_SET_GTID_SET}" ]] && JOB="Set GTID_PURGED;" && JOB_CNT=$(( JOB_CNT+1 ))
  [[ ! -z "${V_STOP_SLAVE}" ]] && QRY="stop slave;" && JOB_CNT=$(( JOB_CNT+1 ))
  [[ ! -z "${V_START_SLAVE}" ]] && QRY="start slave;" && JOB_CNT=$(( JOB_CNT+1 ))
  [[ ! -z "${V_SKIP_TRX}" ]] && JOB="Execute pt-slave-start" && JOB_CNT=$(( JOB_CNT+1 ))
  [[ ! -z "${V_SKIP_BINLOG}" ]] && JOB="Skip current binlog file" && JOB_CNT=$(( JOB_CNT+1 ))
  [[ ! -z "${V_MOVE_SLAVE}" ]] && JOB="Move slave under its grand parent." && JOB_CNT=$(( JOB_CNT+1 ))
  [[ ! -z "${V_FIX_REPL_ON_GTID_CRASHED_SLAVE}" ]] && JOB="Fix replication after slave crash on GTID based replication." && JOB_CNT=$(( JOB_CNT+1 ))
  [[ ! -z "${V_CHANGE_REPL_TO_AUTO_POSITION}" ]] && JOB="Change replication to master_auto_position=1" && JOB_CNT=$(( JOB_CNT+1 ))

  [ $JOB_CNT -ne 1 ] && echo "Please specify only one action. See --help for help" && exit 1
  
  return 0
}

#---------------------------------------------------------------- func_query --
func_query() { 

  H_FQDN=$1
  H_PORT=$2
  
  TMP_ERR=/tmp/${SCRIPT_NAME}_tmperr_${H_FQDN}_${H_PORT}.$$
  TMP_LOG=/tmp/${SCRIPT_NAME}_tmplog_${H_FQDN}_${H_PORT}.$$

  if [ ! -z "${V_SQL_FILE}" ]
  then
      mysql -vvv -u$USER -p$PASSWD -h$H_FQDN -P$H_PORT < $V_SQL_FILE 2>/dev/null > $TMP_LOG
      [ $? -ne 0 ] && echo "Error occurred during executing SQL on '$H_FQDN : $H_PORT'" > $TMP_ERR && break
  fi
  if [ ! -z "${V_SHOW_GLOBAL}" ]
  then
      VAL=`mysql -u$USER -p$PASSWD -h$H_FQDN -P$H_PORT -NB -e"select concat('$H_FQDN', ':', '$H_PORT', ':', variable_name,':', variable_value) from information_schema.global_variables where variable_name like '${V_SHOW_GLOBAL}'" 2>/dev/null`
      [ $? -ne 0 ] && echo "Error occurred during executing SQL on '$H_FQDN : $H_PORT'" > $TMP_ERR && break
      if [ "$VAL" != "" ] 
      then
          echo "$VAL" > $TMP_LOG
      else
          cat /dev/null > $TMP_LOG
      fi
  else
      mysql -vvv -u$USER -p$PASSWD -h$H_FQDN -P$H_PORT -e"$QRY" 2>/dev/null > $TMP_LOG
      [ $? -ne 0 ] && echo "Error occurred during executing SQL on '$H_FQDN : $H_PORT'" > $TMP_ERR && break
  fi
}

#--------------------------------------------------------- func_get_gtid_set --
func_get_gtid_set() {

  S_FQDN=$1
  S_PORT=$2                                                                                                                                                                  
  TMP_LOG=/tmp/${SCRIPT_NAME}_log_${S_FQDN}_${S_PORT}
  mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"STOP SLAVE;" 2>/dev/null
  sleep 2
  GTID_EXECUTED=$(mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -NB -e"select @@global.gtid_executed;" 2>/dev/null | sed 's/\\n//g')

  echo "STOP SLAVE; SET GLOBAL GTID_PURGED='$GTID_EXECUTED';" > $TMP_LOG
}

#--------------------------------------------------------- func_set_gtid_set --
func_set_gtid_set() {

  S_FQDN=$1
  S_PORT=$2
  TMP_LOG=/tmp/${SCRIPT_NAME}_log_${S_FQDN}_${S_PORT}
  mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT < $TMP_LOG 2>/dev/null
  sleep 2
  mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"START SLAVE;" 2>/dev/null
} 

#------------------------------------------------------------- func_skip_trx --
func_skip_transactions() {

  S_FQDN=$1
  S_PORT=$2
  TMP_ERR=/tmp/${SCRIPT_NAME}_tmperr_${S_FQDN}_${S_PORT}.$$
  TMP_LOG=/tmp/${SCRIPT_NAME}_tmplog_${S_FQDN}_${S_PORT}.$$
 
  mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"SHOW SLAVE STATUS\G" 2>/dev/null > $TMP_LOG
  [ $? -ne 0 ] && echo "Error occurred while executing SHOW SLAVE STATUS on '$S_FQDN:$S_PORT'" > $TMP_ERR && break
  SLAVE_IO_RUNNING=`cat $TMP_LOG |grep "Slave_IO_Running" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
  SLAVE_SQL_RUNNING=`cat $TMP_LOG |grep "Slave_SQL_Running:" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
  if [ "$SLAVE_IO_RUNNING" == "Yes" ] && [ "$SLAVE_SQL_RUNNING" == "No" ] 
  then 
      # checking if GTID is not enabled.
      GTID=`mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -NB -e"select count(1) from (select @@global.gtid_mode='ON' as gtid) a where a.gtid=1;" 2>/dev/null`
      [ $? -ne 0 ] && echo "[Error] - Error occurred during executing check if GTID is enabled or not on '$S_FQDN:$S_PORT'" > $TMP_ERR && break
      if [ $GTID -eq 1 ]
      then
          # For GTID Enabled servers fetching r/w master's SERVER_UUID 
          while true 
          do
              M_HOSTINFO=`cat $TMP_LOG | grep "Master_Host" |cut -d":" -f2 | sed -e 's/^ *//' -e 's/ *$//'`
              M_PORT=`cat $TMP_LOG | grep "Master_Port" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
              IS_RW=`mysql -u$USER -p$PASSWD -h$M_HOSTINFO -P$M_PORT -NB -e"select count(1) from (select @@global.read_only='OFF' as read_only) a where a.read_only=1;" 2>/dev/null`
              [ $? -ne 0 ] && echo "Error occurred while checking READ_ONLY=OFF on '$M_HOSTINFO:$M_PORT'" > $TMP_ERR && break
              if [ $IS_RW -eq 1 ]
              then
                  SERVER_UUID=`mysql -u$USER -p$PASSWD -h$M_HOSTINFO -P$M_PORT -NB -e"select @@global.server_uuid" 2>/dev/null`
                  [ $? -ne 0 ] && echo "Error occurred while executing query on '$M_HOSTINFO:$M_PORT'" > $TMP_ERR && break
                  /usr/bin/pt-slave-restart --user=$USER --password=$PASSWD --host=$S_FQDN --port=$S_PORT --error-numbers=$V_ERROR_NUM --run-time=$V_RUNTIME --master-uuid=$SERVER_UUID > $TMP_LOG    
                  break
              else
                  mysql -u$USER -p$PASSWD -h$M_HOSTINFO -P$M_PORT -e"SHOW SLAVE STATUS\G" 2>/dev/null > $TMP_LOG
                  [ $? -ne 0 ] && echo "Error occurred while executing SHOW SLAVE STATUS on '$M_HOSTINFO:$M_PORT'" > $TMP_ERR && break
              fi
          done
      else
          /usr/bin/pt-slave-restart --user=$USER --password=$PASSWD --host=$S_FQDN --port=$S_PORT --error-numbers=$V_ERROR_NUM --run-time=$V_RUNTIME > $TMP_LOG
      fi
  else
      cat /dev/null > $TMP_LOG
  fi    
}

#---------------------------------------------------------- func_skip_binlog --
func_skip_binlog_file() {
  
  S_FQDN=$1
  S_PORT=$2
  TMP_ERR=/tmp/${SCRIPT_NAME}_tmperr_${S_FQDN}_${S_PORT}.$$
  TMP_LOG=/tmp/${SCRIPT_NAME}_tmplog_${S_FQDN}_${S_PORT}.$$

  mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"SHOW SLAVE STATUS\G" 2>/dev/null > $TMP_LOG
  [ $? -ne 0 ] && echo "Error occurred while executing SHOW SLAVE STATUS on '$S_FQDN:$S_PORT'" > $TMP_ERR && break                                                       

  if [ `cat $TMP_LOG | grep "Last_IO_Errno: 1236" |wc -l` -eq 1 ]
  then
      GTID=`mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -NB -e""select count(1) from (select @@global.gtid_mode='ON' as gtid) a where a.gtid=1; 2>/dev/null`
      [ $? -ne 0 ] && echo "Error occurred while checking if GTID is enabled on '$S_FQDN:$S_PORT'" > $TMP_ERR && break

      if [ $GTID -eq 1 ]
      then
          # restart slave
          mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"STOP SLAVE; START SLAVE;" 2>/dev/null
          [ $? -ne 0 ] && echo "Error occurred while restarting slave on '$S_FQDN:$S_PORT'" > $TMP_ERR && break    
          echo "Slave restarted on '$S_FQDN:$S_PORT'" > $TMP_LOG
      else
          CURR_LOG_FILE=`cat $TMP_LOG |grep "Relay_Master_Log_File:" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
          FILE_PREFIX=`echo $CURR_LOG_FILE |cut -d"." -f1`
          FILE_POSTFIX=`echo $CURR_LOG_FILE |cut -d"." -f2 |bc`
          FILE_POSTFIX=$(( FILE_POSTFIX + 1 ))
          FILE_POSTFIX=`printf "%06d" $FILE_POSTFIX`
   
          CMD="STOP SLAVE; CHANGE MASTER TO MASTER_LOG_FILE='$FILE_PREFIX.$FILE_POSTFIX', MASTER_LOG_POS=120; START SLAVE;"

cat > $TMP_LOG << EOL 
mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -NB -e"$CMD" 2>/dev/null
if [ \$? -eq 0 ] 
then
    echo "[Info] CHANGE MASTER executed on '$S_FQDN:$S_PORT'"  
else
    echo "Error occurred while executing CHANGE MASTER on '$S_FQDN:$S_PORT'"
fi
EOL
      fi
  else
      cat /dev/null > $TMP_LOG
  fi    
}
#---------------------------------------- func_move_slave_under_grand_parent --
func_move_slave_under_grand_parent() {
 
  S_FQDN=$1
  S_PORT=$2
  TMP_ERR=/tmp/${SCRIPT_NAME}_tmperr_${S_FQDN}_${S_PORT}.$$
  TMP_LOG=/tmp/${SCRIPT_NAME}_tmplog_${S_FQDN}_${S_PORT}.$$

  mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"SHOW SLAVE STATUS\G" 2>/dev/null > $TMP_LOG
  [ $? -ne 0 ] && echo "Error occurred while executing SHOW SLAVE STATUS on '$S_FQDN:$S_PORT'" > $TMP_ERR && break

  CM_HOSTINFO=`cat $TMP_LOG | grep "Master_Host:" |cut -d":" -f2 | sed -e 's/^ *//' -e 's/ *$//'`
  CM_PORT=`cat $TMP_LOG | grep "Master_Port:" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`

  GTID=`mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -NB -e"select count(1) from (select @@global.gtid_mode='ON' as gtid) a where a.gtid=1;" 2>/dev/null`

  if [ $GTID -eq 1 ]
  then
      mysql -u$USER -p$PASSWD -h$CM_HOSTINFO -P$CM_PORT -e"SHOW SLAVE STATUS\G" 2>/dev/null > $TMP_LOG
      [ $? -ne 0 ] && echo "Error occurred while executing STOP SLAVE on '$CM_HOSTINFO:$CM_PORT'" > $TMP_ERR && break
      
      NM_HOSTINFO=`cat $TMP_LOG | grep "Master_Host:" |cut -d":" -f2 | sed -e 's/^ *//' -e 's/ *$//'`
      NM_PORT=`cat $TMP_LOG | grep "Master_Port:" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`

      V_POSITION="MASTER_AUTO_POSITION=1"
      
  else
      mysql -u$USER -p$PASSWD -h$CM_HOSTINFO -P$CM_PORT -e"STOP SLAVE; SHOW MASTER STATUS\G" 2>/dev/null > $TMP_LOG
      [ $? -ne 0 ] && echo "Error occurred while executing STOP SLAVE on '$CM_HOSTINFO:$CM_PORT'" > $TMP_ERR && break

      CM_FILE=`cat $TMP_LOG | grep "File:" |cut -d":" -f2 | sed -e 's/^ *//' -e 's/ *$//'`
      CM_POS=`cat $TMP_LOG | grep "Position:" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      
      mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"SHOW SLAVE STATUS\G" 2>/dev/null > $TMP_LOG
      [ $? -ne 0 ] && echo "Error occurred while executing SHOW SLAVE STATUS on '$S_FQDN:$S_PORT'" > $TMP_ERR && break
      
      S_FILE=`cat $TMP_LOG | grep "Relay_Master_Log_File" |cut -d":" -f2 | sed -e 's/^ *//' -e 's/ *$//'`
      S_POS=`cat $TMP_LOG | grep "Exec_Master_Log_Pos:" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`

      # Checking if slave is caught up before generating CHANGE MASTER command.
      if [[ `echo ${CM_FILE}_${CM_POS} | sed 's/\.//'` == `echo ${S_FILE}_${S_POS} |sed 's/\.//'` ]] 
      then
          mysql -u$USER -p$PASSWD -h$CM_HOSTINFO -P$CM_PORT -e"SHOW SLAVE STATUS\G" 2>/dev/null > $TMP_LOG
          [ $? -ne 0 ] && echo "Error occurred while executing STOP SLAVE on '$CM_HOSTINFO:$CM_PORT'" > $TMP_ERR && break

          NM_HOSTINFO=`cat $TMP_LOG | grep "Master_Host:" |cut -d":" -f2 | sed -e 's/^ *//' -e 's/ *$//'`
          NM_PORT=`cat $TMP_LOG | grep "Master_Port:" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
          NM_FILE=`cat $TMP_LOG | grep "Relay_Master_Log_File" |cut -d":" -f2 | sed -e 's/^ *//' -e 's/ *$//'`
          NM_POS=`cat $TMP_LOG | grep "Exec_Master_Log_Pos:" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
          V_POSITION="MASTER_LOG_FILE='$NM_FILE', MASTER_LOG_POS=$NM_POS"
      else 
          echo "[Error] '$S_FQDN:$S_PORT' is not caught up." > $TMP_ERR && break
      fi
  fi
  
  CMD="STOP SLAVE; CHANGE MASTER TO MASTER_HOST='$NM_HOSTINFO', MASTER_PORT=$NM_PORT, MASTER_USER='$REPL_USER', MASTER_PASSWORD='$REPL_PASSWD', $V_POSITION; START SLAVE;"
cat > $TMP_LOG << EOL                                                                                                                                            
  mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -NB -e"$CMD" 2>/dev/null
  if [ \$? -eq 0 ] 
  then
      echo "[Info] 'CHANGE MASTER executed on '$S_FQDN:$S_PORT'. Please check and Don't forget to START SLAVE on '$CM_HOSTINFO:$CM_PORT'"  
  else
      echo "Error occurred while executing CHANGE MASTER on '$S_FQDN:$S_PORT'"
  fi
EOL
}

#---------------------------------------------- change_repl_to_auto_position --
func_change_repl_to_auto_position() {
  
  S_FQDN=$1
  S_PORT=$2
  TMP_ERR=/tmp/${SCRIPT_NAME}_tmperr_${S_FQDN}_${S_PORT}.$$
  TMP_LOG=/tmp/${SCRIPT_NAME}_tmplog_${S_FQDN}_${S_PORT}.$$

  # Make sure that the slave is not intermediate master.

  IS_INTERMEDIATE_MASTER=$(mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -NB -e"SHOW SLAVE HOSTS" 2>/dev/null | wc -l)
  [ $? -ne 0 ] && echo "Error occured during executing 'SHOW SLAVE HOSTS' on '$S_FQDN:$S_PORT" > $TMP_ERR && break 

  [ $IS_INTERMEDIATE_MASTER -gt 0 ] && echo "'$S_FQDN($S_PORT)' has $IS_INTERMEDIATE_MASTER slave(s) under it. Please relocate slave(s) and re-run the script with --change-repl-to-auto-position option." > $TMP_ERR && break 
  
  # checking if GTID is not enabled.
  GTID=`mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -NB -e"select count(1) from (select @@global.gtid_mode='ON' as gtid) a where a.gtid=1;" 2>/dev/null`
  [ $? -ne 0 ] && echo "[Error] - Error occurred during executing check if GTID is enabled or not on '$S_FQDN:$S_PORT'" > $TMP_ERR && break
  if [ $GTID -eq 1 ]
  then
 
      # Make sure that the replication is working                                                                                                                    
      mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"SHOW SLAVE STATUS\G" 2>/dev/null > $TMP_LOG
      [ $? -ne 0 ] && echo "Error occurred while executing SHOW SLAVE STATUS on '$S_FQDN:$S_PORT'" > $TMP_ERR && break
             
      SLAVE_IO_RUNNING=`cat $TMP_LOG |grep "Slave_IO_Running" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      SLAVE_SQL_RUNNING=`cat $TMP_LOG |grep "Slave_SQL_Running:" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      AUTO_POSITION=`cat $TMP_LOG |grep "Auto_Position:" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      if [ "$SLAVE_IO_RUNNING" == "Yes" ] && [ "$SLAVE_SQL_RUNNING" == "Yes" ] && [ "$AUTO_POSITION" == "0" ]
      then
          # Convert back to GTID based replication.
          mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"STOP SLAVE\G" 2>/dev/null > $TMP_LOG
          [ $? -ne 0 ] && echo "Error occurred while executing STOP SLAVE on '$S_FQDN:$S_PORT'" > $TMP_ERR && break
                  
          S_GTID_EXECUTED=$(mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -NB -e"select @@global.gtid_executed;" 2>/dev/null | sed 's/\\n//g')
          [ $? -ne 0 ] && echo "Error occured during executing 'SELECT GTID_EXECUTED' on '$S_FQDN:$S_PORT" > $TMP_FILE && exit 1 
                 
          IFS=',' read -r -a SLAVE_SET <<< "$S_GTID_EXECUTED"
          PURGE_SET=""
          for i in "${!SLAVE_SET[@]}"
          do
              UUID=`echo ${SLAVE_SET[i]} | cut -d ':' -f1`
              if [ `echo ${SLAVE_SET[i]} |cut -d ':' -f2- |grep ':' |wc -l` -eq 1 ] 
              then
                  TRX=`echo ${SLAVE_SET[i]} |cut -d ':' -f2,3  |cut -d '-' -f1,3`
                  PURGE_SET="$PURGE_SET,$UUID:$TRX"
              else
                  PURGE_SET="$PURGE_SET,${SLAVE_SET[i]}"
              fi 
          done
          PURGE_SET=$(echo $PURGE_SET |sed "s/^,//") 
              
          # Start replication with auto_position=1
          mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"STOP SLAVE; RESET SLAVE; RESET MASTER; SET GLOBAL GTID_PURGED='$PURGE_SET'; CHANGE MASTER TO MASTER_AUTO_POSITION=1; START SLAVE;" 2>/dev/null > $TMP_LOG
          [ $? -ne 0 ] && echo "Error occurred while trying to start slave with MASTER_AUTO_POSITION=1 on '$S_FQDN:$S_PORT'" > $TMP_ERR && break
          echo "Rplication started with MASTER_AUTO_POSITION=1 on '$S_FQDN:$S_PORT'" > $TMP_LOG 
      else
          cat /dev/null > $TMP_LOG
          echo "Replication is broken on '$S_FQDN:$S_PORT' after starting as position based" > $TMP_ERR
      fi
  else
      cat /dev/null > $TMP_LOG
      echo "Looks like GTID is not enabled on '$S_FQDN:$S_PORT'" > $TMP_ERR 
  fi

}
#-------------------------------------------- fix_repl_on_gtid_crashed_slave --
func_fix_repl_on_gtid_crashed_slave() {

  S_FQDN=$1
  S_PORT=$2
  TMP_ERR=/tmp/${SCRIPT_NAME}_tmperr_${S_FQDN}_${S_PORT}.$$
  TMP_LOG=/tmp/${SCRIPT_NAME}_tmplog_${S_FQDN}_${S_PORT}.$$

  # checking if GTID is not enabled.
  GTID=`mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -NB -e"select count(1) from (select @@global.gtid_mode='ON' as gtid) a where a.gtid=1;" 2>/dev/null`
  [ $? -ne 0 ] && echo "[Error] - Error occurred during executing check if GTID is enabled or not on '$S_FQDN:$S_PORT'" > $TMP_ERR && break
  if [ $GTID -eq 1 ]
  then
      mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"SHOW SLAVE STATUS\G" 2>/dev/null > $TMP_LOG
      [ $? -ne 0 ] && echo "Error occurred while executing SHOW SLAVE STATUS on '$S_FQDN:$S_PORT'" > $TMP_ERR && break
      SLAVE_IO_RUNNING=`cat $TMP_LOG |grep "Slave_IO_Running" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      SLAVE_SQL_RUNNING=`cat $TMP_LOG |grep "Slave_SQL_Running:" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      M_FILE=`cat $TMP_LOG |grep "Relay_Master_Log_File:" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      M_POS=`cat $TMP_LOG |grep "Exec_Master_Log_Pos:" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      SHOW_SLAVE_STATUS_AT=`echo "${M_FILE}_${M_POS}"`  

      if [ "$SLAVE_IO_RUNNING" == "Yes" ] && [ "$SLAVE_SQL_RUNNING" == "No" ]
      then 
          # Fetching slave's latest executed binlog position from mysql.slave_relay_log_info table
          SLAVE_RELAY_LOG_INFO_AT=`mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -NB -e"select concat(Master_log_name, '_', Master_log_pos) from mysql.slave_relay_log_info" 2>/dev/null`
          [ $? -ne 0 ] && echo "[Error] - Error occurred during querying mysql.slave_relay_log_info table on '$S_FQDN:$S_PORT'" > $TMP_ERR && break
      
          MFILE=`echo $SLAVE_RELAY_LOG_INFO_AT | cut -d '_' -f1`
          MPOS=`echo $SLAVE_RELAY_LOG_INFO_AT | cut -d '_' -f2`
          
          #echo "$MFILE : $MPOS Setting Position based replicaiton"
          mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"STOP SLAVE; CHANGE MASTER TO MASTER_LOG_FILE='$MFILE', MASTER_LOG_POS=$MPOS, MASTER_AUTO_POSITION=0; START SLAVE;" 2>/dev/null > $TMP_LOG
          [ $? -ne 0 ] && echo "Error occurred while starting position based replication on '$S_FQDN:$S_PORT'" > $TMP_ERR && break
              
          # Wait for few seconds 
          sleep 2
              
          # Change replication to master_auto_position=1
          func_change_repl_to_auto_position $S_FQDN $S_PORT
      fi
  else   
      cat /dev/null > $TMP_LOG 
      cat /dev/null > $TMP_ERR
  fi
}

#----------------------------------------------------------------- manage_db --
manage_db() {
  
  echo "" 
  echo "Job will be executed against following servers:"
  echo ""
  cat $HOST_FILE |awk -F: '{print $1":"($2)}'
  echo ""
  echo "-----------------------------------------------------------------"
  echo "Action: $QRY$JOB"
  echo "-----------------------------------------------------------------"
  echo ""
  echo "Do you want to contine(yes/no)?"
  read CONFIRM                                                                                                                                                                                
  [ "$CONFIRM" != "yes" ] && exit 1
 
  # notify mysql-change-log slack channel
  if [[ -z "${V_SKIP_BINLOG}" && -z "${V_MOVE_SLAVE}" && -z "${V_SHOW_GLOBAL}" ]] 
  then
      if [[ ! -z "${V_SQL_FILE}" && `cat $V_SQL_FILE |grep -i "password\|identified" |wc -l` -eq 0 ]] 
      then
          mysql_change_log "$SCRIPT_NAME.sh $options [command(s): `cat $V_SQL_FILE`]" 
      else
          mysql_change_log "$SCRIPT_NAME.sh $options"
      fi
  fi    
  # To run SQL file
  if [ "$QRY" != "" ]
  then
      FUNC="func_query"
  elif [[ ! -z "${V_SKIP_TRX}" ]]  
  then
      FUNC="func_skip_transactions"
  elif [[ ! -z "${V_SKIP_BINLOG}" ]]  
  then
      FUNC="func_skip_binlog_file"
  elif [[ ! -z "${V_MOVE_SLAVE}" ]]  
  then
      FUNC="func_move_slave_under_grand_parent"
  elif [[ ! -z "${V_FIX_REPL_ON_GTID_CRASHED_SLAVE}" ]]  
  then
      FUNC="func_fix_repl_on_gtid_crashed_slave"
  elif [[ ! -z "${V_CHANGE_REPL_TO_AUTO_POSITION}" ]]  
  then
      FUNC="func_change_repl_to_auto_position"
  elif [[ ! -z "${V_GET_GTID_SET}" ]]  
  then
      FUNC="func_get_gtid_set"
  elif [[ ! -z "${V_SET_GTID_SET}" ]]  
  then
      FUNC="func_set_gtid_set" 
  fi

  # Running given action in parallel
  while read LINE
  do
      FQDN=`echo $LINE | cut -d":" -f1`
      PORT=`echo $LINE | cut -d":" -f2`
      $FUNC $FQDN $PORT &
  done < $HOST_FILE
  wait
 
  while read LINE
  do
      H_FQDN=`echo $LINE | cut -d":" -f1`
      H_PORT=`echo $LINE | cut -d":" -f2`
      [ -f /tmp/${SCRIPT_NAME}_tmplog_${H_FQDN}_${H_PORT}.$$ ] && cat /tmp/${SCRIPT_NAME}_tmplog_${H_FQDN}_${H_PORT}.$$ >> $LOG_FILE
      [ -f /tmp/${SCRIPT_NAME}_tmperr_${H_FQDN}_${H_PORT}.$$ ] && cat /tmp/${SCRIPT_NAME}_tmperr_${H_FQDN}_${H_PORT}.$$ >> $ERR_FILE
  done < $HOST_FILE

  # Display Output
  
  # for Query
  if [ "$QRY" != "" ]
  then
      if [ -s $LOG_FILE ]
      then
          if [ ! -z "${V_SHOW_GLOBAL}" ]
          then
              sort -t':' -k3,4 $LOG_FILE
              echo ""
              echo "Summary:"
              echo " -----------------------------------------------"
              echo "|  variable:value                       | count |"
              echo " -----------------------------------------------"
              sort -t':' -k3,4 $LOG_FILE |cut -d ':' -f3,4 | uniq -c |  awk '{ printf "| %-35s   |  %4s |\n", $2,$1}'
              echo " -----------------------------------------------"
          else
              cat $LOG_FILE
          fi
      fi
      [ -s $LOG_FILE ] && echo "" ; echo "Output Logs available at : $LOG_FILE"
      [ -s $ERR_FILE ] && echo "Error logs available at : $ERR_FILE"  
  # For pt-slave-restart
  elif [[ ! -z "${V_SKIP_TRX}" || ! -z "${V_FIX_REPL_ON_GTID_CRASHED_SLAVE}" || ! -z "${V_CHANGE_REPL_TO_AUTO_POSITION=}" ]]
  then
      echo ""
      [ -s $LOG_FILE ] && cat $LOG_FILE && echo "" && echo "Output Logs available at : $LOG_FILE"
      [ -s $ERR_FILE ] && cat $ERR_FILE && echo "" && echo "Error logs available at : $ERR_FILE"

  # For skip BINLOG file
  elif [[ ! -z "${V_SKIP_BINLOG}" || ! -z "${V_MOVE_SLAVE}" ]]
  then
      if [ -s $LOG_FILE ] 
      then
         echo ""
         # add mysql-change-log code
         sed -i "1s/^/SCRIPT_DIR=\"\$( cd \"\$( dirname \"\${BASH_SOURCE[0]}\" )\" \&\& pwd )\"\nCOMMON_FUNC_FILE=\"\${SCRIPT_DIR}\/common_functions\.sh\"\n\. \${COMMON_FUNC_FILE}\nmysql_change_log ${SCRIPT_NAME}.sh ${options}\n/" $LOG_FILE
         echo "To run actual CHANGE_MASTER command(s), Execute: $LOG_FILE"
      fi
  fi

  if [[ ! -s $LOG_FILE && ! -s $ERR_FILE ]] 
  then
      echo ""
      if [ ! -z "${V_SHOW_GLOBAL}" ]
      then
          echo "Looks like '$V_SHOW_GLOBAL' is not matching any GLOBAL VARIABLE(s)'"
      else
          echo "Looks like none of the listed hosts need to run this command."
      fi
  fi    
  #rm -f /tmp/${SCRIPT_NAME}_tmp* $HOST_FILE

  return 0
}
#---------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  manage_db
  return 0
}

main $*
