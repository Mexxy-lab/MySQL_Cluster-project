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
# Purpose: This script should be used to create db snapshots in GCP
#
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################
  
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"
  
. ${PARAMETER_FILE}
  
LOG_DIR="/db/data/opsdb/logs/dbscripts_logs"
SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
LOG_FILE=${LOG_DIR}/${SCRIPT_NAME}_logs.$$
GCLOUD=""/bin/gcloud
SNAPSHOTDT=`date "+%Y-%m-%d %H:%M:%S"`
SLACK_EMAIL="k6a1q8d6f6d2z2b7@ckcorp.slack.com,dba@creditkarma.com"


# Delete files older then 24 hours.
/bin/find $LOG_FILE -type f -mmin +1440 -delete

#---------------------------------------------------------------------- help --
help(){
  echo '''
  This script should be used to create db snapshots in GCP.
    
  Usage:
    
  sh $SCRIPT_NAME.sh [ -d <DATA_CENTER> -g <GROUP>  -n <INSTANCE_NUMBER> -e <EXTENDED> -h <HOSTNAME> --create ]
    
  Optional:
        -d | --data-center          Data Center code (ie. ckw, cke)
        -g | --group                Group (ie. fldb, fodb, budb, mono, tkdb, ipdb)
        -n | --instance-number      Instance Number (ie 1,2,..16)
        -h | --hostname             Hostname (ie mdb10.sjc1,mdb11.sjc1)
        --retention                 Delete weekly snapshots older then --retention days. Default: 30 days
        --application-consistent    To perform application consistent snapshot (Y/N). Default Y
    
  Example:
        sh $SCRIPT_NAME.sh -d euw2 -g fldb --hourly
    
  '''
  exit 1
}
  
#--------------------------------------------------------------------- debug --
debug() {
      
  echo "`date "+%Y-%m-%d %H:%M:%S"` [$1] $2" | tee -a $LOG_FILE
  [[ "$1" == "Error" ]] && rm -f $LOCK_FILE
  return 0
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
             -d | --data-center )         V_DATA_CENTER=${args[$i+1]};;
             -g | --group )               V_GROUP=${args[$i+1]};;
             -n | --instance-number )     V_INSTANCE_NUMBER=${args[$i+1]};;
             -h | --hostname )            V_HOSTNAME=${args[$i+1]};;
             -r | --retention )           V_RETENTION=${args[$i+1]};;
             --application-consistent )   V_APPCONSISTENT=${args[$i+1]};;
             *)                           echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      else
          case ${args[$i]} in
             --application-consistent )   V_APPCONSISTENT="Y";;
          esac  
          i=$(($i+1))
      fi
  done
  
  [ -z "${V_RETENTION}" ] && V_RETENTION=30
  [ -z "${V_APPCONSISTENT}" ] && V_APPCONSISTENT="Y"
    
  DAYOFWEEK=$( date '+%u' )
  HOUROFDAY=$( date '+%H' )
  
  FREQUENCY="hourly"
  RETENTION=$(date -d "-1 days" "+%Y-%m-%d %H:%M:%S")
  [[ $HOUROFDAY -eq 0 && $DAYOFWEEK -ne 1 ]] && FREQUENCY="daily" && RETENTION=$(date -d "-7 days" "+%Y-%m-%d %H:%M:%S")
  [[ $HOUROFDAY -eq 0 && $DAYOFWEEK -eq 1 ]] && FREQUENCY="weekly" && RETENTION=$(date -d "-${V_RETENTION} days" "+%Y-%m-%d %H:%M:%S")
  
  RANGE=""
  if [ ! -z "${V_DATA_CENTER}" ]
  then
      [ "${V_DATA_CENTER}" == "euw2" ] && DC_ALIAS="euw2"
      RANGE="and dataCenter = '$V_DATA_CENTER'"
      if [ ! -z "${V_HOSTNAME}" ]
      then
          HOSTS=`echo $V_HOSTNAME | sed "s/,/.$DC_ALIAS','/g"` && RANGE="$RANGE and hostname in ('$HOSTS.$DC_ALIAS')"
      fi
  fi
  [ ! -z "${V_GROUP}" ] && GRPS=`echo $V_GROUP | sed "s/,/','/g"` && RANGE="$RANGE and groupName in ('$GRPS')"
  [ ! -z "${V_INSTANCE_NUMBER}" ] && RANGE="$RANGE and shardNumber in (`echo $V_INSTANCE_NUMBER | awk 'BEGIN { RS=","; FS="-"; ORS="" } NR > 1 { print "," } NF > 1  { for (i=$1; i<$2; ++i) { print i "," } print $2; next } { print $1 }'`)"
  
  HOSTS=`mysql -NB -e"select concat(concat(substring_index(fqdn, '.', 1), \"-\", instancename), \":\", fqdn, \":\", port) from $ADMIN_SCHEMA.$ADMIN_TABLE where 1=1 $RANGE"`
  [ $? -ne 0 ] && echo "`date "+%Y-%m-%d %H:%M:%S"` - [Error] Not able to execute query to ckadmin.host_info" && exit 1
  
  [[ "$HOSTS" == "" ]] && echo "`date "+%Y-%m-%d %H:%M:%S"` - [Error] No hosts found for snapshots for a given input" &&  exit 1
   
  return
}
  
#----------------------------------------------------- func_create_snapshots --
func_create_snapshots() {
    
  DISKNAME=`echo $1 | cut -d":" -f1`
  SNAPSHOTHOST=`echo $1 | cut -d":" -f2`
  SNAPSHOTPORT=`echo $1 | cut -d":" -f3`
  
  PROJECT="--project=prod-back-end-data-b1fdb7c5"
  [[ $SNAPSHOTHOST == v* || $SNAPSHOTHOST == bkpv* ]] && PROJECT="--project=prod-vault-c7892f3d"
 
  SNAPSHOTNAME="$DISKNAME-$FREQUENCY-`date --date="$SNAPSHOTDT" "+%Y%m%d-%H%M%S"`"
  MY_AUTH="/usr/bin/mysql -u$USER -p$PASSWD -h$SNAPSHOTHOST -P$SNAPSHOTPORT"
    
  # Get zone info
  ZONE=`echo "$ZONEINFO" | grep "$DISKNAME" | head -1 | awk '{print $2}'`
    
  if [ "$V_APPCONSISTENT" == "Y" ]
  then
      # Stop slave
      $MY_AUTH -e "STOP SLAVE; FLUSH TABLES WITH READ LOCK; FLUSH LOGS;" 2>/dev/null
      [ $? -ne 0 ] && debug "Error" "Unable to execute 'STOP SLAVE' on '$SNAPSHOTHOST:$SNAPSHOTPORT'" && return 1
  fi
  
  # Log Slave Status
  BINLOG_STATUS=`$MY_AUTH -e "SHOW SLAVE STATUS\G SHOW MASTER STATUS\G" 2>/dev/null`
  [ $? -ne 0 ] && debug "Error" "Unable to execute 'SHOW SLAVE STATUS' and/or 'SHOW MASTER STATUS' on '$SNAPSHOTHOST:$SNAPSHOTPORT'" && return 1
  SNAPSHOTHOST_EXECUTEDGTID=$($MY_AUTH -NB -e"select @@global.gtid_executed;" 2>/dev/null | sed 's/\\n//g')
  [ $? -ne 0 ] && debug "Error" "Unable to execute query on '$SNAPSHOTHOST:$SNAPSHOTPORT'" && return 1
  
  # Perform a db snapshot
  $GCLOUD compute disks snapshot $DISKNAME --snapshot-names=$SNAPSHOTNAME --zone=$ZONE $PROJECT 2>/dev/null &
  [ $? -ne 0 ] && debug "Error" "Unable to execute 'gcloud compute disks snapshot $DISKNAME' for '$SNAPSHOTHOST:$SNAPSHOTPORT'" && return 1
  
  # Wait for the snapshot to be in either UPLOADING or READY state
  IN_PROGRESS=0
  while [ $IN_PROGRESS -lt 1 ]
  do
      IN_PROGRESS=`$GCLOUD compute snapshots describe $SNAPSHOTNAME $PROJECT 2>/dev/null | grep status | awk -F':' '{print $2}' | grep "READY\|UPLOADING" |wc -l`
      [ $? -ne 0 ] && debug "Error" "Unable to execute 'gcloud compute disks snapshots describe for '$SNAPSHOTHOST:$SNAPSHOTPORT'" && return 1
      [ $IN_PROGRESS -lt 1 ] && sleep 30
  done
  
  # Log snapshot info to Opsdb
  if [ "$V_APPCONSISTENT" == "Y" ]
  then   
      # Start slave
      $MY_AUTH -e "UNLOCK TABLES; START SLAVE;" 2>/dev/null
      [ $? -ne 0 ] && debug "Error" "Unable to execute 'START SLAVE' on '$SNAPSHOTHOST:$SNAPSHOTPORT'" && return 1
  fi
  
  STATUS=""
  while [[ "$STATUS" != "READY" ]]
  do
      STATUS=`$GCLOUD compute snapshots describe $SNAPSHOTNAME $PROJECT 2>/dev/null | grep status | awk -F':' '{print $2}' | sed -e 's/^ *//' -e 's/ *$//'`
      [ $? -ne 0 ] && debug "Error" "Unable to execute 'gcloud compute disks snapshots describe for '$SNAPSHOTHOST:$SNAPSHOTPORT'" && return 1
      # logic for failure
      [[ "$STATUS" != "READY" ]] && sleep 30
  done
    
  # Fetch list of snapshots older then retention policy                                                                                                                    
  DELETE_LIST=`$GCLOUD compute snapshots list $PROJECT --filter="(name:'$DISKNAME-$FREQUENCY' AND creationTimestamp < '$RETENTION')" 2>/dev/null | awk '{print $1}' | grep -v "NAME" | tr '\n' ' '`
  [ $? -ne 0 ] && debug "Error" "Unable to execute 'gcloud compute disks snapshotis list for '$SNAPSHOTHOST:$SNAPSHOTPORT'" && return 1
  
  if [ "$DELETE_LIST" != "" ]
  then
      # Delete old snapshots
      $GCLOUD compute snapshots delete $PROJECT --quiet $DELETE_LIST 2>/dev/null
      [ $? -ne 0 ] && debug "Error" "Unable to execute 'gcloud compute disks snapshots delete for '$SNAPSHOTHOST:$SNAPSHOTPORT'" && return 1
  fi
  
  SNAPSHOTHOST_BINLOGFILE=`echo "$BINLOG_STATUS" | grep " File:" | cut -d':' -f2 | sed -e 's/^ *//' -e 's/ *$//'`
  SNAPSHOTHOST_BINLOGPOS=`echo "$BINLOG_STATUS" | grep " Position:" | cut -d':' -f2 | sed -e 's/^ *//' -e 's/ *$//'`
  MASTERHOST=`echo "$BINLOG_STATUS" | grep " Master_Host:" | cut -d':' -f2 | sed -e 's/^ *//' -e 's/ *$//'`
  MASTERPORT=`echo "$BINLOG_STATUS" | grep " Master_Port:" | cut -d':' -f2 | sed -e 's/^ *//' -e 's/ *$//'`
  MASTERHOST_BINLOGFILE=`echo "$BINLOG_STATUS" | grep " Master_Log_File:" | cut -d':' -f2 | sed -e 's/^ *//' -e 's/ *$//'`
  MASTERHOST_EXECUTEDBINLOGPOS=`echo "$BINLOG_STATUS" | grep " Exec_Master_Log_Pos:" | cut -d':' -f2 | sed -e 's/^ *//' -e 's/ *$//'`
  
  # Only Successful Entry to DB
   
  QRY="INSERT INTO ckadmin.snapshot_catalog_gcp (
      dataCenter,
      snapshotName,
      snapshotHost,
      snapshotPort,
      snapshotHostBinlogFile,
      snapshotHostBinlogPosition,
      snapshotHostExecutedGtidSet,
      masterHost,
      masterPort,
      masterLogFile,
      execMasterLogPos,
      createdAt,
      status
    ) values(
      '$V_DATA_CENTER',
      '$SNAPSHOTNAME',
      '$SNAPSHOTHOST',
      $SNAPSHOTPORT,
      '$SNAPSHOTHOST_BINLOGFILE',
      '$SNAPSHOTHOST_BINLOGPOS',
      '$SNAPSHOTHOST_EXECUTEDGTID',
      '$MASTERHOST',
       $MASTERPORT,
      '$MASTERHOST_BINLOGFILE',
      '$MASTERHOST_EXECUTEDBINLOGPOS',
      '$SNAPSHOTDT',
      '$STATUS'
    )"
  
  mysql -NB -e"$QRY"
  [ $? -ne 0 ] && debug "Error" "INSERT to ckadmin.snapshot_catalog_gcp table failed for '$SNAPSHOTHOST:$SNAPSHOTPORT'" && return 1
  
  return 0
  
  
}
#---------------------------------------------------------- create_snapshots --
create_snapshots() {
  
  ZONEINFO=`$GCLOUD compute disks list --project=prod-back-end-data-b1fdb7c5 2>/dev/null ; $GCLOUD compute disks list --project=prod-vault-c7892f3d 2>/dev/null`
  [ $? -ne 0 ] && echo "`date "+%Y-%m-%d %H:%M:%S"` - [Error] Unable to execute 'gcloud compute disks list'" && exit 1
 
  for HOSTINFO in $HOSTS
  do
      LOCK_FILE="${LOG_DIR}/${SCRIPT_NAME}_`echo $HOSTINFO | awk -F':' '{ print $2 "_" $3 }'`.lock"
  
      if [ -f $LOCK_FILE ]
      then
          echo "`date "+%Y-%m-%d %H:%M:%S"` - [Error] Another instance of this script is already running"
      else
          touch $LOCK_FILE
          ( func_create_snapshots $HOSTINFO ; rm -f $LOCK_FILE ) &
      fi
  done
  wait
  
  # Alerting
  [ -f $LOG_FILE ] && cat $LOG_FILE | mail -s "Following Snapshot(s) FAILED:" "$SLACK_EMAIL"
  
  return 0
}
  
#---------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  create_snapshots
  return 0
}
  
main $*
