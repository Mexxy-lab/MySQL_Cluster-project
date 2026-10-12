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
# Purpose: This script should be used to build slaves of monolithic and shards
#          from one of the opsdb servers. 
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
DT=`date "+%Y-%m-%d_%H%M%S"`
HOST_FILE=/tmp/hostfile.$$
TMP_FILE=/tmp/tmpfile.$$
EMAIL_FILE=/tmp/emailfile.$$
STARTED_AT=`date +%s`

BUILD_TIME=`echo "$(( COMPLETED_AT - STARTED_AT ))"`

#---------------------------------------------------------------------- help --
help(){
  echo "" 
  echo "This script should be used to build a slave from given source."
  echo ""
  echo "Usage:"
  echo ""
  echo "sh $SCRIPT_NAME.sh < REQUIRED > [ OPTIONAL ]"
  echo ""
  echo "  Required:"
  echo "      --role        MySQL Role (ie. mono, shard, ticket, monovp)"
  echo "      --source      Source (Hostname,port,instance_type) (ie. fodb1.sjc1,3301,multi)"
  echo "      --target      Target (Hostname,port,instance_type) (ie. sdb17,3306,single)"
  echo "      --topology    Slave topology (ie. child, sibling)"
  echo ""
  echo "  Optional:"
  echo "      --memory      Memory required for Prepare phase. Default 16G (ie. 1G, 16G)"
  echo "      --compress    uses xtrabackup compression. Requires qpress installed on target server"
  echo ""
  echo "  Example:"
  echo ""
  echo "      sh $SCRIPT_NAME.sh --role mono --source mdb4.sjc1,3306,single --target mdb2.sjc1,3306,single --topology sibling --memory 8G"
  echo "      sh $SCRIPT_NAME.sh --role shard --source fldb3.sjc1,3305,multi --target fodb3.sjc1,3305,multi --topology child"
  echo ""
  exit 1
}

#--------------------------------------------------------------------- debug --

debug() {
  if [[ "$1" == "[Info]" && "$2" == "alert" ]] 
  then
      #cat $EMAIL_FILE | mail -s "Build_Slave COMPLETED on '$T_HOST($T_PORT)'." "$DBA_EMAIL,$SLACK_EMAIL"
      cat $EMAIL_FILE >> $DONE_LIST
      echo -e "$3"
      rm -f $TMP_FILE $HOST_FILE $EMAIL_FILE
  fi    
  if [ "$1" == "[Error]" ]
  then
      if [ "$3" == "alert" ]
      then
          echo "$2" | mail -s "Build_Slave FAILED on '$T_HOST($T_PORT)'." "$DBA_EMAIL,$SLACK_EMAIL"
      else
          echo "$2"
      fi
      echo "$2" >> $LOG_FILE
      rm -f $TMP_FILE $HOST_FILE $EMAIL_FILE
      echo "$T_HOST:($T_PORT):FAILED" >> $DONE_LIST
      exit 1

  fi
}

#-------------------------------------------------------------- process_args --
process_args() {

  options=$@

  # An array with all the arguments
  args=($options)

  [[ $args == "--help" || $args == "" ]] && help && exit 1

  i=0
  for arg in $options
  do
      if [[ ${args[$i]:0:1} == "-" && ${args[$i+1]:0:1} != "-" ]]
      then
          case ${args[$i]} in
            -r | --role )            V_ROLE=${args[$i+1]};;
            -s | --source )          V_SOURCE=${args[$i+1]};;
            -t | --target )          V_TARGET=${args[$i+1]};;
            --topology )             V_TOPOLOGY=${args[$i+1]};;
            --compress )             V_COMPRESS="Y";;
            -m | --memory )          V_MEMORY=${args[$i+1]};;   
            --use-ip )               V_USE_IP=${args[$i+1]};;   
             *)                      echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      fi
  done

  [ -z "${V_ROLE}" ] && debug "[Error]" "Please specify 'Role' for --role option. See --help for help"

  V_SOURCE_HOST=`echo $V_SOURCE | cut -d',' -f1`
  V_SOURCE_PORT=`echo $V_SOURCE | cut -d',' -f2`
  V_SOURCE_INSTANCE_TYPE=`echo $V_SOURCE | cut -d',' -f3`
  V_TARGET_HOST=`echo $V_TARGET | cut -d',' -f1`
  V_TARGET_PORT=`echo $V_TARGET | cut -d',' -f2`
  V_TARGET_INSTANCE_TYPE=`echo $V_TARGET | cut -d',' -f3`
  
  [ -z "${V_MEMORY}" ] && V_MEMORY=16G

  DEFAULTS_GROUP=""
  [ "$V_SOURCE_INSTANCE_TYPE" == "multi" ] && NUM=$(($V_SOURCE_PORT % 3300)) && DEFAULTS_GROUP="--defaults-group=mysqld$NUM"

  ADDITIONAL_FILTER=""
  [[ "${V_ROLE}" == "shard" ]] && ADDITIONAL_FILTER=" and t.instanceName = s.instanceName"
  $TOOLS_AUTH -NB -e"select concat(s.hostName, \":\", s.port, \":\", s.fqdn, \":\", s.socket, \":\", s.datadir, \":\", t.hostName, \":\", t.port, \":\", t.fqdn, \":\", t.socket, \":\", t.datadir) from $ADMIN_SCHEMA.$ADMIN_TABLE s, $ADMIN_SCHEMA.$ADMIN_TABLE t where s.role = t.role and s.fqdn='$V_SOURCE_HOST' and s.port='$V_SOURCE_PORT' and t.port='$V_TARGET_PORT' and t.fqdn='$V_TARGET_HOST' $ADDITIONAL_FILTER" 2>/dev/null > $HOST_FILE

  [ ! -s $HOST_FILE ] && debug "[Error]" "Please check if 'Data Center' and/or 'Shard Group' is valid."
  [[ `cat $HOST_FILE | wc -l` -ne 1 ]] && debug "[Error]" "More then one host found. Please check input parameters"
}

bootstrap(){
  
  while read LINE
  do
      S_HOST=`echo $LINE | cut -d":" -f1`
      S_PORT=`echo $LINE | cut -d":" -f2`
      S_FQDN=`echo $LINE | cut -d":" -f3`
      S_SOCKET=`echo $LINE | cut -d":" -f4`
      S_DATADIR=`echo $LINE | cut -d":" -f5`
      T_HOST=`echo $LINE | cut -d":" -f6`
      T_PORT=`echo $LINE | cut -d":" -f7`
      T_FQDN=`echo $LINE | cut -d":" -f8`
      T_SOCKET=`echo $LINE | cut -d":" -f9`
      T_DATADIR=`echo $LINE | cut -d":" -f10`

      $SOURCE_AUTH -h $S_FQDN -P$S_PORT -e"show slave status\G" > $TMP_FILE
      NM_FQDN=`cat $TMP_FILE | grep "Master_Host" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      NM_PORT=`cat $TMP_FILE | grep "Master_Port" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      
      NM_HOST=`$TOOLS_AUTH -NB -e"select fqdn from $ADMIN_SCHEMA.$ADMIN_TABLE where fqdn = '$NM_FQDN' group by hostName;" 2>/dev/null`

      [ "$NM_PORT" == "" ] && NM_PORT="-"
      [ "$NM_HOST" == "" ] && NM_HOST="-"

      if [ "$V_TOPOLOGY" == "child" ]
      then
          NM_PORT=$S_PORT
          NM_HOST=$S_HOST
          NM_FQDN=$S_FQDN
      fi
      
      # checking if Master has GTID enabled.
      GTID=`$SOURCE_AUTH -h$S_FQDN -P$S_PORT -NB -e"select count(1) from (select @@gtid_mode='ON' as gtid) a where a.gtid=1;" 2>/dev/null`
      if [ $GTID -eq 1 ] 
      then
          V_GTID="Y"
      else
      	  V_GTID="N"
      fi	  
  done < $HOST_FILE
  
  LOG_FILE=/tmp/${SCRIPT_NAME}_${S_HOST}_${T_PORT}_$DT.log
  [ -f $LOG_FILE ] && rm -f $LOG_FILE
 
  TARGET_SSH="ssh -n -o LogLevel=Error -o StrictHostKeyChecking=no $BKPUSER@$T_FQDN"
  SOURCE_SSH="ssh -n -o LogLevel=Error -o StrictHostKeyChecking=no $BKPUSER@$S_FQDN"
    
  echo "LOGS of this script are available at : $LOG_FILE"

  return 0
}

#---------------------------------------------------------- innobackup_phase --
innobackup_phase() {
  
  INCOMING_DIR="$T_DATADIR/incoming"
  TARGET_SCRIPT="/usr/local/bin/target_build_slave.sh"
  
  $TARGET_SSH "test -f $TARGET_SCRIPT"
  [ $? -ne 0 ] && debug "[Error]" "file $TARGET_SCRIPT does not exists on '$T_HOST'."
  
  [ -z "${T_PORT}" ] && debug "[Error]" "Variable 'T_PORT' is not set."
  [ -z "${T_DATADIR}" ] && debug "[Error]" "Variable 'T_DATADIR' is not set."
  [ -z "${V_TARGET_INSTANCE_TYPE}" ] && debug "[Error]" "Variable 'T_TARGET_INSTANCE_TYPE' is not set."

  [ `$SOURCE_SSH "pv -V |wc -l"` -eq 0 ] && debug "[Error]" "PV is not installed on $S_HOST. Please Check."
  [ `$TARGET_SSH "netstat -lnt |grep ':$T_PORT ' |wc -l"` -ge 1 ] && debug "[Error]" "Port $T_PORT on $T_HOST is in use. Please Check."

  # Checking if datadir mount exists.
  if [ "$V_ROLE" != "test" ] && [ "$V_ROLE" != "opsdb" ] && [ "$V_ROLE" != "servicedb" ]
  then
      $TARGET_SSH "grep -qs '$T_DATADIR' /proc/mounts"
      [ $? -ne 0 ] && debug "[Error]" "alert" "Mount $T_DATADIR does not exists'$T_HOST($T_PORT)'."
  else
      V_MEMORY=100M
  fi

  # Creating INCOMING_DIR on the target.
  $TARGET_SSH "sudo $TARGET_SCRIPT $T_DATADIR $T_PORT $V_TARGET_INSTANCE_TYPE $BKPUSER create_dirs"
  [ $? -ne 0 ] && debug "[Error]" "Failed to create INCOMING_DIR and TMP_DIR on '$T_HOST($T_PORT)'."
  
  $TARGET_SSH "test -d $INCOMING_DIR" 2>&1
  [ $? -ne 0 ] && debug "[Error]" "Incoming Directory $T_HOST:$INCOMING_DIR doesn't exists."

  $TARGET_SSH screen -m -d "sudo $TARGET_SCRIPT $T_DATADIR $T_PORT $V_TARGET_INSTANCE_TYPE $BKPUSER open_listener"

  S_DATASIZE=`$SOURCE_SSH "df -B1 $S_DATADIR |tr '\n' ' '" |awk '{print $10}'`

  echo "-----------------------------------------------------------------------" | tee -a $LOG_FILE
  echo  "`date "+%Y-%m-%d %H:%M:%S"` [Info] INNOBACKUP phase started on '$T_HOST($T_PORT)'." | tee -a $LOG_FILE
  echo "-----------------------------------------------------------------------" | tee -a $LOG_FILE

  if [ "$V_COMPRESS" = Y ]
  then
      $SOURCE_SSH -A "sudo innobackupex --user=$BACKUP_USER --password=$BACKUP_PASSWD --socket=$S_SOCKET $DEFAULTS_GROUP --slave-info --parallel=8 --compress --compress-threads=8 --stream=xbstream /tmp 2> $LOG_FILE | pv -i 3 -cN $T_HOST:$T_PORT -s $S_DATASIZE -f -W | ssh -o StrictHostKeyChecking=no $BKPUSER@$T_FQDN \"xbstream -x -C $INCOMING_DIR\" 2>&1"
  else
  # Old: SSH method
  $SOURCE_SSH -A "sudo innobackupex --user=$BACKUP_USER --password=$BACKUP_PASSWD --socket=$S_SOCKET $DEFAULTS_GROUP --slave-info --parallel=8 --stream=xbstream /tmp 2> $LOG_FILE | pv -i 3 -cN $T_HOST:$T_PORT -s $S_DATASIZE -f -W | ssh -o StrictHostKeyChecking=no $BKPUSER@$T_FQDN \"xbstream -x -C $INCOMING_DIR\" 2>&1"
 
  # New: nc method
  #$SOURCE_SSH -A "sudo innobackupex --user=$BACKUP_USER --password=$BACKUP_PASSWD --socket=$S_SOCKET $DEFAULTS_GROUP --slave-info --parallel=8 --stream=xbstream /tmp 2> $LOG_FILE | pv -i 3 -cN $T_HOST:$T_PORT -s $S_DATASIZE -f -W | nc -j $T_FQDN $T_PORT"
  fi 

  [ -z "$SOURCE_SSH \"tail -1 $LOG_FILE\" |grep 'completed OK!'" ] && debug "[Error]" "Innobackup phase Failed on '$S_HOST:$S_PORT'" "alert"

  INNOBACKUP_DONE_AT=`date +%s`
  INNOBACKUP_TIME=`echo "$(( INNOBACKUP_DONE_AT - STARTED_AT ))"`
  echo "Replication started: '$NM_HOST($NM_PORT)' -> '$T_HOST($T_PORT)'" > $EMAIL_FILE
  echo "-----------------------------------------------------------------------" | tee -a $LOG_FILE
  echo  "`date "+%Y-%m-%d %H:%M:%S"` [Info] INNOBACKUP phase completed on '$T_HOST:$T_PORT'." | tee -a $LOG_FILE
  echo "-----------------------------------------------------------------------" | tee -a $LOG_FILE

}

#-------------------------------------------------------------- prepare_phase --
prepare_phase() {
   echo "-----------------------------------------------------------------------" | tee -a $LOG_FILE
   echo  "`date "+%Y-%m-%d %H:%M:%S"` [Info] PREPARE phase started on '$T_HOST:$T_PORT'." | tee -a $LOG_FILE
   echo "-----------------------------------------------------------------------" | tee -a $LOG_FILE
 
   # Decompress only if --compress was used 
   if [ "$V_COMPRESS" = Y ]
   then 
        $TARGET_SSH "innobackupex --parallel=8 --decompress $INCOMING_DIR" 2>&1 | tee -a $LOG_FILE | tee -a $LOG_FILE
        [ -z "`tail -1 $LOG_FILE | grep 'completed OK!'`" ] && debug "[Error]" "Decompress phase FAILED on '$T_HOST:$T_PORT'." "alert"
   fi
   
   $TARGET_SSH "innobackupex --ibbackup=xtrabackup_55 --use-memory=$V_MEMORY --apply-log $INCOMING_DIR" 2>&1 | tee -a $LOG_FILE
   [ -z "`tail -1 $LOG_FILE | grep 'completed OK!'`" ] && debug "[Error]" "Prepare phase FAILED on '$T_HOST:$T_PORT'." "alert"
  
   PREPARE_DONE_AT=`date +%s`
   PREPARE_TIME=`echo "$(( PREPARE_DONE_AT - INNOBACKUP_DONE_AT ))"`
   echo "-----------------------------------------------------------------------" | tee -a $LOG_FILE
   echo  "`date "+%Y-%m-%d %H:%M:%S"` [Info] PREPARE phase completed on '$T_HOST:$T_PORT'." | tee -a $LOG_FILE
   echo "-----------------------------------------------------------------------" | tee -a $LOG_FILE
}

#-------------------------------------------------------------- slave_phase --
slave_phase() {

  echo "-----------------------------------------------------------------------" | tee -a $LOG_FILE
  echo  "`date "+%Y-%m-%d %H:%M:%S"` [Info] STARTING a slave on '$T_HOST:$T_PORT'." | tee -a $LOG_FILE
  echo "-----------------------------------------------------------------------" | tee -a $LOG_FILE

  NM_HOSTINFO=$NM_FQDN
  [ "$V_USE_IP" == "Y" ] && NM_HOSTINFO=$NM_IP

  # Executing CHANGE_MASTER Command on target server.
  if [ "$V_GTID" == "Y" ]
  then
      if [ "$V_TOPOLOGY" == "child" ] 
      then
          COORDINATE_FILE="$INCOMING_DIR/xtrabackup_binlog_info"
          $TARGET_SSH "test -f $COORDINATE_FILE"
          [ $? -ne 0 ] && debug "[Error]" "$COORDINATE_FILE file not found on '$T_HOST'"
          GTID_POS=`$TARGET_SSH "cat $COORDINATE_FILE" |tr '\n' ' '| awk '{for (i=3;i<=NF;i++) printf "%s", $i}'`
          GTID_PURGED_CMD="SET GLOBAL GTID_PURGED='$GTID_POS'"
      fi

      if [ "$V_TOPOLOGY" == "sibling" ]
      then
          COORDINATE_FILE="$INCOMING_DIR/xtrabackup_slave_info"
          $TARGET_SSH "test -f $COORDINATE_FILE"
          [ $? -ne 0 ] && debug "[Error]" "$COORDINATE_FILE file not found on '$T_HOST'"
          GTID_PURGED_CMD=`$TARGET_SSH "cat $COORDINATE_FILE" |tr '\n' ' '| awk '{for (i=1;i<=NF;i++) printf " %s", $i}' |cut -d ';' -f1`
      fi
      CHANGE_CMD=`echo "reset slave; reset master; $GTID_PURGED_CMD; CHANGE MASTER TO MASTER_HOST='$NM_FQDN', MASTER_USER='$REPL_USER', MASTER_PASSWORD='$REPL_PASSWD', MASTER_PORT=$NM_PORT, MASTER_AUTO_POSITION=1" | sed -e "s/' /'/g" -e "s/= /=/g"`
  else
  	  if [ "$V_TOPOLOGY" == "child" ] 
      then
          COORDINATE_FILE="$INCOMING_DIR/xtrabackup_binlog_info"
          $TARGET_SSH "test -f $COORDINATE_FILE"
          [ $? -ne 0 ] && debug "[Error]" "$COORDINATE_FILE file not found on '$T_HOST'"
          NM_FILE=`$TARGET_SSH "cat $COORDINATE_FILE" | awk -F" " '{ print $1}'`
          NM_POS=`$TARGET_SSH "cat $COORDINATE_FILE" | awk -F" " '{ print $2}'`
      fi

      if [ "$V_TOPOLOGY" == "sibling" ]
      then
          COORDINATE_FILE="$INCOMING_DIR/xtrabackup_slave_info"
          $TARGET_SSH "test -f $COORDINATE_FILE"
          [ $? -ne 0 ] && debug "[Error]" "$COORDINATE_FILE file not found on '$T_HOST'"
          NM_FILE=`$TARGET_SSH "cat $COORDINATE_FILE | cut -d ',' -f1 |cut -d'=' -f2 | sed 's/\x27//g'"`
          NM_POS=`$TARGET_SSH "cat $COORDINATE_FILE | cut -d ',' -f2 |cut -d'=' -f2"`
      fi
      CHANGE_MASTER_ARGS="MASTER_LOG_FILE='$NM_FILE', MASTER_LOG_POS=$NM_POS"
      CHANGE_CMD=`echo "reset slave; CHANGE MASTER TO MASTER_HOST='$NM_FQDN', MASTER_USER='$REPL_USER', MASTER_PASSWORD='$REPL_PASSWD', MASTER_PORT=$NM_PORT, MASTER_LOG_FILE='$NM_FILE', MASTER_LOG_POS=$NM_POS" | sed -e "s/' /'/g" -e "s/= /=/g"`
  fi

  $TARGET_SSH "echo \"set global read_only=on;\" \"stop slave;\" \"$CHANGE_CMD ;\" \"start slave\" > $INCOMING_DIR/start_slave.sql"
  [ $? -ne 0 ] && debug "[Error]" "INNOBACKUP failed during preparing CHANGE_MASTER command" "alert"

  echo "Executing target script: $TARGET_SCRIPT on '$T_HOST:$T_PORT'." | tee -a $LOG_FILE

  $TARGET_SSH "sudo $TARGET_SCRIPT $T_DATADIR $T_PORT $V_TARGET_INSTANCE_TYPE $BKPUSER start_slave"
  [ $? -ne 0 ] && debug "[Error]" "Failed to start MySQL on '$T_HOST:$T_PORT'." "alert"

  echo "Executing Start Slave on '$T_HOST($T_PORT)'." | tee -a $LOG_FILE
  $TARGET_SSH "mysql -u$BACKUP_USER -p$BACKUP_PASSWD -S $T_SOCKET -e\"set global read_only=on; stop slave; $CHANGE_CMD ; start slave;\"" 2>/dev/null 
  [ $? -ne 0 ] && debug "[Error]" "Failed to start replication on '$T_HOST:$T_PORT'." "alert"
 
  sleep 5
  
  IS_SLAVE_RUNNING=`$TARGET_SSH "mysql -u$BACKUP_USER -p$BACKUP_PASSWD -S $T_SOCKET -e\"show slave status\G\" |grep \"Slave_IO_Running\|Slave_SQL_Running\" |grep \"Yes\" |wc -l" 2>/dev/null`

  if [ $IS_SLAVE_RUNNING -eq 2 ]
  then
      SLAVE_STARTED_AT=`date +%s`
      SLAVE_START_TIME=`echo "$(( SLAVE_STARTED_AT - PREPARE_DONE_AT ))"`
      TOTAL_TIME=`echo "$(( SLAVE_STARTED_AT - STARTED_AT ))"`
      printf "Total Time (in Sec):%6s, Innobackup:%6s, Prepare:%6s Slave Start:%6s\n" "$TOTAL_TIME" "$INNOBACKUP_TIME" "$PREPARE_TIME" "$SLAVE_START_TIME" >> $EMAIL_FILE 
      debug "[Info]" "alert"
      rm -f $TMP_FILE $HOST_FILE $TMP_MYCNF
      echo "-----------------------------------------------------------------------" | tee -a $LOG_FILE
      echo  "`date "+%Y-%m-%d %H:%M:%S"` [Info] Script Completed Successfully on '$T_HOST:$T_PORT'." | tee -a $LOG_FILE
      echo "-----------------------------------------------------------------------" | tee -a $LOG_FILE
  else
  	  echo "-----------------------------------------------------------------------" | tee -a $LOG_FILE
  	  echo  "`date "+%Y-%m-%d %H:%M:%S"` [Info] Script Failed on '$T_HOST:$T_PORT'." | tee -a $LOG_FILE
  	  echo "-----------------------------------------------------------------------" | tee -a $LOG_FILE
  	  debug "[Error]" "Replcation broken on '$T_HOST($T_PORT)'." "alert"
  fi
}

#----------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  bootstrap
  innobackup_phase
  prepare_phase
  slave_phase
  return 0
}

main $*

