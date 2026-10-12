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
# Purpose: This script should be used to restore db snapshots in GCP
#
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################
 
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"
 
. ${PARAMETER_FILE}
 
SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
PASSWD_FILE=$HOME/.ssh.$$.key
 
TOOLS_MYCNF=${HOME}/.tools.$$.cnf
cat > $TOOLS_MYCNF << EOL
!include /etc/my.cnf
[client]
user=$TOOLS_USER
password=$TOOLS_PASSWD
EOL
 
ADMIN_MYCNF=${HOME}/.admin.$$.cnf
cat > $ADMIN_MYCNF << EOL
!include /etc/my.cnf
[client]
user=$USER
password=$PASSWD
EOL
 
export TOOLS_AUTH="mysql --defaults-file=$TOOLS_MYCNF"
export ADMIN_AUTH="mysql --defaults-file=$ADMIN_MYCNF"
 
export BKPUSER=`whoami`
 
#---------------------------------------------------------------------- help --
help(){
  echo '''
  This script should be used to build a slave from given source.
   
  Usage:
      sh $SCRIPT_NAME.sh < REQUIRED > [ OPTIONAL ]
   
      Required:
             -r | --role                      MySQL Role (ie. mono, shard, ticket, monovp)
             -s | --source                    Source Hostname or source datacenter.groupname (ie. fodb001.sjc1, ckw.fodb)
             -t | --target                    Target Hostname or target datacenter.groupname (ie. fldb001.sjc1, ckw.budb)
    
      Optional:
             -n | --instance-number           Instance Number. Default: All shards. (ie. 1,3 , 1-4)
             -m | --new-master )              New master Hostname or datacenter.groupname (ie. fodb001.us-central1, euw2.fodb) Default: Master of the source.
             -u | --until )                   Datetime to perform PITR. (format: YYYY-MM-DD_HH:MM:SS)
             -e | --event-tablename )         TableName to perform event based db recovery for given table. (ie. tablename)
             -d | --target-disksize-in-gb )   Disk size of a target host. This option is added to create a disk with then size other then currently assigned. 
             -y | --disktype )                Disk Type. (ie. pd-ssd, pd-standard) Default: it will preserve current disktype upon restore. 
             -o | --overwrite )               Overwrite Log File
             -z | --serialize )               Running snapshot restore sequentially (meaning only one restore at a time). Default is one-restore-per-host
  
  
      Example:
          Building new slave:    
              sh $SCRIPT_NAME.sh --role mono --source bkpmdb001.us-central1 --target mdbnew004.us-central1
          
          Time based restore:
              sh $SCRIPT_NAME.sh --role shard --source budb001.us-central1 --target fodb001.us-central1 --time 2019-01-01_10:00:00
          
          Event based restore:
              # Note: Please run scan_binlogs_gcp.sh first to scan binary logs to find DROP/TRUNCATE events on tableName
              sh $SCRIPT_NAME.sh --role shard --source budb001.us-central1 --target fodb001.us-central1 -e tableName
  '''
}
 
#--------------------------------------------------------------------- debug --
debug() {
    echo "`date "+%Y-%m-%d %H:%M:%S"` [$1] $2"
    [[ "$1" == "Error" ]] && echo "Exiting..." && exit 1
}
 
#-------------------------------------------------------------- process_args --
process_args() {
options=$@
 
  # An array with all the arguments
  args=($options)
 
  [[ $args == "--help" || $args == "" ]] && help && exit 1
 
  V_SERIALIZE="N"
  i=0
  for arg in $options
  do
      if [[ ${args[$i]:0:1} == "-" && ${args[$i+1]:0:1} != "-" ]]
      then
          case ${args[$i]} in
              -r | --role )                  V_ROLE=${args[$i+1]};;
              -s | --source )                V_SOURCE_HOSTNAME=${args[$i+1]};;
              -t | --target )                V_TARGET_HOSTNAME=${args[$i+1]};;
              -m | --new-master )            V_NEW_MASTER=${args[$i+1]};;
              -n | --instance-number )       V_INSTANCE_NUMBER=${args[$i+1]};;
              -u | --until )                 V_UNTIL=${args[$i+1]};;
              -e | --event-tablename )       V_EVENT_TABLENAME=${args[$i+1]};;
              -d | --target-disksize-in-gb ) V_TARGET_DISKSIZE=${args[$i+1]};;
              -y | --disktype )              V_TARGET_DISKTYPE=${args[$i+1]};;
              -o | --overwrite )             V_OVERWRITE="Y";;
              -p | --parallel )              V_PARALLEL=${args[$i+1]};;
              -z | --serialize )             V_SERIALIZE="Y";;
              *)                             echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      else
          case ${args[$i]} in
             -o | --overwrite )              V_OVERWRITE="Y";;
             -z | --serialize )              V_SERIALIZE="Y";;
          esac
          i=$(($i+1))
      fi
  done
 
  [ -z "${V_ROLE}" ] && debug "Error" "Please specify 'Role' for --role option. See --help for help."
  [ -z "${V_TARGET_HOSTNAME}" ] && debug "Error" "Please specify 'Target Hostname' for --target option. See --help for help."
  [ -z "${V_SOURCE_HOSTNAME}" ] && debug "Error" "Please specify 'Source Hostname' for --source option. See --help for help."
  [ -z "${V_NEW_MASTER}" ] && CHANGE_MASTER="N"
  [[ ! -z "${V_UNTIL}" &&  ! -z "${V_EVENT_TABLENAME}" ]] && debug "Error" "Please specify either --until or --event-tablename option. Both are not allowed togather"
  
  [[ ${V_PARALLEL} -gt 32 ||  -z "${V_PARALLEL}" ]] && V_PARALLEL=32
  
  # We don't want to create disks > 10TB
  [ ! -z ${V_TARGET_DISKSIZE} ] && [ ${V_TARGET_DISKSIZE} -gt 10240 ] && debug "Error" "Max allowed limit for --target-disksize-in-gb is 10240 (10TB)."
  [ ! -z ${V_TARGET_DISKTYPE} ] && [[ "${V_TARGET_DISKTYPE}" != "pd-ssd" && "${V_TARGET_DISKTYPE}" != "pd-standard" ]] && debug "Error" "Allowed value for --disktype are pd-ssd or pd-standard"
  
  RANGE=""                                                                                                                                                                               
  if [ ! -z "${V_INSTANCE_NUMBER}" ]
  then
      RANGE="and s.shardNumber in (`echo $V_INSTANCE_NUMBER | awk 'BEGIN { RS=","; FS="-"; ORS="" } NR > 1 { print "," } NF > 1  { for (i=$1; i<$2; ++i) { print i "," } print $2; next } { print $1 }'`)"
  fi   
   
  SHARD_HOSTS=1
  if [[ "${V_ROLE}" == *"shard"* ]]
  then
      if [[ "${V_SOURCE_HOSTNAME}" == *"euw2"* ]]
      then
         S_DC=`echo $V_SOURCE_HOSTNAME | cut -d '.' -f1`
         S_GROUP=`echo $V_SOURCE_HOSTNAME | cut -d '.' -f2`
         RANGE="$RANGE and s.dataCenter = '$S_DC' and s.groupName = '$S_GROUP'"
      else
         RANGE="$RANGE and s.hostName = '$V_SOURCE_HOSTNAME'" 
      fi  
      if [[ "${V_TARGET_HOSTNAME}" == *"euw2"* ]]
      then
         T_DC=`echo $V_TARGET_HOSTNAME | cut -d '.' -f1`
         T_GROUP=`echo $V_TARGET_HOSTNAME | cut -d '.' -f2`
         RANGE="$RANGE and t.dataCenter = '$T_DC' and t.groupName = '$T_GROUP'"                                                                                           
         SHARD_HOSTS=`$TOOLS_AUTH -NB -e"select count(distinct(hostname)) from $ADMIN_SCHEMA.$ADMIN_TABLE where dataCenter = '$T_DC' and groupName = '$T_GROUP'"`
      else
         RANGE="$RANGE and t.hostName = '$V_TARGET_HOSTNAME'"
      fi
      if [[ "$CHANGE_MASTER" == "N" ]]
      then
         if [[ "${V_SOURCE_HOSTNAME}" == *"euw2"* ]]
         then
             RANGE="$RANGE and nm.dataCenter = '$S_DC' and nm.groupName = '$S_GROUP'"
         else
             RANGE="$RANGE and nm.hostName = '$V_SOURCE_HOSTNAME'"
         fi    
      elif [[ "${V_NEW_MASATER}" == *"euw2"* ]]
      then
         NM_DC=`echo $V_NEW_MASTER | cut -d '.' -f1`
         NM_GROUP=`echo $V_NEW_MASTER | cut -d '.' -f2`
         RANGE="$RANGE and nm.dataCenter = '$NM_DC' and nm.groupName = '$NM_GROUP'"                                                                                           
      else
         RANGE="$RANGE and nm.hostName = '$V_NEW_MASTER'"
      fi
      RANGE="$RANGE and s.instanceName = t.instanceName"
  elif [[ "$CHANGE_MASTER" == "N" ]]
  then
     RANGE="$RANGE and s.hostName='$V_SOURCE_HOSTNAME' and t.hostName='$V_TARGET_HOSTNAME' and nm.hostName = '$V_SOURCE_HOSTNAME'"
  else
      RANGE="$RANGE and s.hostName='$V_SOURCE_HOSTNAME' and t.hostName='$V_TARGET_HOSTNAME' and nm.hostName = '$V_NEW_MASTER'"
  fi
 
  HOSTS=`$TOOLS_AUTH -NB -e"select concat(s.fqdn, \":\", s.port, \":\", if(s.multiInstance = 'Y', 'multi', 'single'), \":\", concat(substring_index(s.fqdn, '.', 1), \"-\", s.instancename), \":\", s.datadir, \":\", t.fqdn, \":\", t.port, \":\", if(t.multiInstance = 'Y', 'multi', 'single'), \":\", concat(substring_index(t.fqdn, '.', 1), \"-\", t.instancename), \":\", t.datadir, \":\", nm.fqdn, \":\", nm.port) from $ADMIN_SCHEMA.$ADMIN_TABLE s, $ADMIN_SCHEMA.$ADMIN_TABLE t, $ADMIN_SCHEMA.$ADMIN_TABLE nm  where s.role = t.role and s.role = nm.role and s.role = '$V_ROLE' and s.shardNumber=t.shardNumber and s.shardNumber = nm.shardNumber $RANGE" 2>/dev/null`
  [ $? -ne 0 ] && debug "Error" "Unable to execute query on ckadmin.host_info"
   
  [[ "$HOSTS" == "" ]] && debug "Error" "Please check if 'Data Center' and/or 'Shard Group' is valid."

  echo "-------------------------------------------------"
  echo "Snapshot will be restored on following server(s):"
  echo "-------------------------------------------------"

  for HOST in $HOSTS
  do
      echo $HOST | awk -F":" '{print $6 "(" $7 ")" }'
  done
  echo "-------------------------------------------------"
  echo "Do you want to contine(yes/no)?"
  read CONFIRM                                                                                                                                                                                
  [ "$CONFIRM" != "yes" ] && exit 1

  [[ ${V_PARALLEL} -gt ${SHARD_HOSTS} ||  -z "${V_PARALLEL}" ]] && V_PARALLEL=$SHARD_HOSTS

  # We don't want to create disks > 10TB
  [ ! -z ${V_TARGET_DISKSIZE} ] && [ ${V_TARGET_DISKSIZE} -gt 10240 ] && debug "Error" "Max allowed limit for --target-disksize-in-gb is 10240 (10TB)."
 
  return 0
}
 
#------------------------------------------------------------- func_snapshot --
func_restore_snapshot() {

  while read INPUTS
  do
      S_FQDN=`echo $INPUTS | cut -d":" -f1`
      S_PORT=`echo $INPUTS | cut -d":" -f2`
      S_DISKNAME=`echo $INPUTS | cut -d":" -f4`
      S_INSTANCENAME=`echo $INPUTS | cut -d":" -f4 | cut -d"-" -f2`
      T_FQDN=`echo $INPUTS | cut -d":" -f6`
      T_PORT=`echo $INPUTS | cut -d":" -f7`
      T_INSTANCETYPE=`echo $INPUTS | cut -d":" -f8`
      T_DISKNAME=`echo $INPUTS | cut -d":" -f9`
      T_MOUNTNAME=`echo $INPUTS | cut -d":" -f10`
      NM_FQDN=`echo $INPUTS | cut -d":" -f11`
      NM_PORT=`echo $INPUTS | cut -d":" -f12`
 
      # Find out which snapshot to restore
      if [ ! -z "${V_UNTIL}" ]
      then
          UNTIL=`echo $V_UNTIL | awk -F"_" '{print $1 " " $2}'`
          SNAPSHOT_TO_RESTORE=`$TOOLS_AUTH -NB -A $ADMIN_SCHEMA -e"SELECT snapshotName FROM snapshot_catalog_gcp WHERE snapshotHost = '$S_FQDN' AND snapshotPort = $S_PORT AND createdAt < '$UNTIL' AND status = 'READY' ORDER BY createdAt DESC LIMIT 1"`                 
      elif [ ! -z "${V_EVENT_TABLENAME}" ]
      then
          TABLE_FILTER=`echo $V_EVENT_TABLENAME | sed "s/,/%' OR eventStatement LIKE '%/g"` && TABLE_FILTER="eventStatement LIKE '%$TABLE_FILTER%'"
          EVENT_ID=`$TOOLS_AUTH -NB -A $ADMIN_SCHEMA -e"SELECT MIN(eventId) FROM scan_binlogs_gcp WHERE eventHost = '$S_FQDN' AND eventPort = $S_PORT AND ($TABLE_FILTER)"`
          SNAPSHOT_TO_RESTORE=`$TOOLS_AUTH -NB -A $ADMIN_SCHEMA -e"SELECT b.snapshotName FROM scan_binlogs_gcp a JOIN snapshot_catalog_gcp b WHERE a.eventId = $EVENT_ID AND b.snapshotHost = '$S_FQDN' AND b.snapshotPort = $S_PORT AND GTID_SUBSET(a.eventGtid, b.snapshotHostExecutedGtidSet) = 0 ORDER BY b.snapId DESC LIMIT 1"` 
      else
          SNAPSHOT_TO_RESTORE=`$TOOLS_AUTH -NB -A $ADMIN_SCHEMA -e"SELECT snapshotName FROM snapshot_catalog_gcp WHERE snapshotHost = '$S_FQDN' AND snapshotPort = $S_PORT AND status = 'READY' ORDER BY createdAt DESC LIMIT 1"`
      fi
      
      TARGET_SSH="ssh -n -o LogLevel=Error -o StrictHostKeyChecking=no $BKPUSER@$T_FQDN"
      TARGET_SCRIPT="/usr/local/bin/target_restore_snapshot_gcp.sh"

      # Making sure that target script is available.
      $TARGET_SSH "test -f $TARGET_SCRIPT"
      [ $? -ne 0 ] && debug "Error" "file $TARGET_SCRIPT does not exists on '$T_FQDN'."
 
      # Making sure that mount is not in use.
      $TARGET_SSH "sudo $TARGET_SCRIPT -c lsof -m $T_MOUNTNAME"
      [ $? -ne 0 ] && debug "Error" "'$T_MOUNTNAME' on '$T_FQDN' is in use."
       
      # Performing restore
      EXTRA_ARGS=""
      [ ! -z "${V_TARGET_DISKSIZE}" ] && EXTRA_ARGS="-d $V_TARGET_DISKSIZE"
      [ ! -z "${V_TARGET_DISKTYPE}" ] && EXTRA_ARGS="$EXTRA_ARGS -y $V_TARGET_DISKTYPE"
     
      $TARGET_SSH "sudo $TARGET_SCRIPT -s $S_DISKNAME,$T_DISKNAME,$T_INSTANCETYPE,$T_FQDN,$T_PORT,$T_MOUNTNAME,$SNAPSHOT_TO_RESTORE $EXTRA_ARGS"
      [ $? -ne 0 ] && debug "Error" "Restore failed on '$T_FQDN:$T_PORT'"
     
      # CHANGE MASTER if needed
      if [[ "$CHANGE_MASTER" != "N" ]]
      then
          $ADMIN_AUTH -h$T_FQDN -P$T_PORT -e"CHANGE MASTER TO MASTER_HOST='$NM_FQDN', MASTER_PORT=$NM_PORT, MASTER_USER='$REPL_USER', MASTER_PASSWORD='$REPL_PASSWD', MASTER_AUTO_POSITION=1"
          [ $? -ne 0 ] && debug "Error" "Unable to execute 'CHANGE MASTER TO' on '$T_FQDN:$T_PORT'."
          debug "Info" "Master changed '$NM_FQDN:$NM_PORT' -> '$T_FQDN:$T_PORT'."
      fi

      # If this is a db restore without --until or --event-tablename, lets start replication
      if [[ -z "${V_UNTIL}" && -z "${V_EVENT_TABLENAME}" ]]
      then
          $ADMIN_AUTH -h$T_FQDN -P$T_PORT -e"START SLAVE;"
          [ $? -ne 0 ] && debug "Error" "Unable to execute 'START SLAVE' on '$T_FQDN:$T_PORT'."
          debug "Info" "Replication started on '$T_FQDN:$T_PORT'."
      fi

      # If this is an event based recovery, lets skip bad events 
      if [ ! -z "${V_EVENT_TABLENAME}" ]
      then
          # Disable strict ACID parameters for replication to run faster.
          $ADMIN_AUTH -h$T_FQDN -P$T_PORT -e"SET GLOBAL sync_binlog=0; SET GLOBAL innodb_flush_log_at_trx_commit=2;"
          [ $? -ne 0 ] && debug "Error" "Unable to execute 'SET GLOBAL...' on '$T_FQDN:$T_PORT'"
          
          # Fetch GTIDs which are needed to be skipped
          SKIPGTIDS=`$TOOLS_AUTH -NB -A $ADMIN_SCHEMA -e"SELECT eventGtid FROM scan_binlogs_gcp WHERE eventHost = '$S_FQDN' AND eventPort = $S_PORT AND ($TABLE_FILTER) ORDER BY eventId"`
          for SKIPGTID in $SKIPGTIDS
          do 
              debug "Info" "Skipping $T_FQDN($T_PORT):$SKIPGTID"
              $ADMIN_AUTH -h$T_FQDN -P$T_PORT -e"START SLAVE UNTIL sql_before_gtids = '$SKIPGTID';"
              [ $? -ne 0 ] && debug "Error" "Unable to execute 'START SLAVE UNTIL' on '$T_FQDN:$T_PORT'"

              # wait till sql thread is active
              SLAVE_IO_RUNNING="Yes"
              SLAVE_SQL_RUNNING="Yes"
              while [[ "$SLAVE_IO_RUNNING" == "Yes" && "$SLAVE_SQL_RUNNING" != "No" ]]
              do
                  SLAVE_STATUS=`$ADMIN_AUTH -h$T_FQDN -P$T_PORT -e"SHOW SLAVE STATUS\G"`
                  [ $? -ne 0 ] && debug "Error" "Unable to execute 'SHOW SLAVE STATUS' on '$T_FQDN:$T_PORT'"

                  SLAVE_IO_RUNNING=`echo "$SLAVE_STATUS" |grep "Slave_IO_Running" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
                  SLAVE_SQL_RUNNING=`echo "$SLAVE_STATUS" |grep "Slave_SQL_Running:" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
                  
                  sleep 2
              done
              $ADMIN_AUTH -h$T_FQDN -P$T_PORT -e"STOP SLAVE; SET GTID_NEXT='$SKIPGTID'; BEGIN; COMMIT; SET GTID_NEXT='AUTOMATIC';"
              [ $? -ne 0 ] && debug "Error" "Unable to execute 'SET GTID_NEXT' on '$T_FQDN:$T_PORT'"
          done

          # Enable strict ACID options     
          $ADMIN_AUTH -h$T_FQDN -P$T_PORT -e"SET GLOBAL sync_binlog=1; SET GLOBAL innodb_flush_log_at_trx_commit=1;"
          [ $? -ne 0 ] && debug "Error" "Unable to execute 'SET GLOBAL...' on '$T_FQDN:$T_PORT'"
  
          # Finally starting replication
          $ADMIN_AUTH -h$T_FQDN -P$T_PORT -e"START SLAVE;"
          [ $? -ne 0 ] && debug "Error" "Unable to execute 'START SLAVE' on '$T_FQDN:$T_PORT'"
          debug "Info" "Replication started on '$T_FQDN:$T_PORT'."
      fi
  done < $1
 
  return 0
}
#------------------------------------------------------------------ snapshot --
restore_snapshot() {
 
  # Starting ssh-agent
  ssh-agent -s > $PASSWD_FILE
  . $PASSWD_FILE >/dev/null
  ssh-add 2>/dev/null
   
  echo "`date "+%Y-%m-%d %H:%M:%S"` [Info] Restore process started"
 
  # Splitting the input to per host files
  for HOSTINFO in $HOSTS
  do
      HOSTNUM=`echo $HOSTINFO | cut -d ":" -f6 | cut -d"." -f1 |grep -o "...$" | bc`
      FILENUM=$(( $HOSTNUM % $V_PARALLEL ))
      RUNME=/tmp/${SCRIPT_NAME}_runme_${FILENUM}.$$
      echo "$HOSTINFO" >> $RUNME
  done
 
  for HOSTRUNNER in `ls /tmp |grep $SCRIPT_NAME | grep runme | grep $$`
  do
      if [ "$V_SERIALIZE" == "N" ]
      then
          func_restore_snapshot /tmp/$HOSTRUNNER &
      else   
          func_restore_snapshot /tmp/$HOSTRUNNER
      fi
  done
   
  wait
 
  # Stopping ssh-agent
  ssh-add -D > /dev/null 2>&1
  ssh-agent -k > /dev/null 2>&1
  rm -f $PASSWD_FILE
 
  echo "`date "+%Y-%m-%d %H:%M:%S"` [Info] Restore process completed"
 
  rm -f $TOOLS_MYCNF $ADMIN_MYCNF
 
  return 0
}
 
#---------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  restore_snapshot
  return 0
}
 
main $*
