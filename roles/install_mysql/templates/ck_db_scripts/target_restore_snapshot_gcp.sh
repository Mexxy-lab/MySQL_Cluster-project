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
# Purpose: This is a target script used by opsdb server to restore db snapshot
#          on targeted db servers at scale.
#
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################
 
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"
 
. ${PARAMETER_FILE}
 
SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
GCLOUD="/usr/local/share/google/google-cloud-sdk/bin/gcloud"
SNAPSHOTTS=`date "+%Y%m%d-%H%M%S"`
T_HOST=`hostname -f`
LOCAL_AUTH="mysql -u$BACKUP_USER -p$BACKUP_PASSWD"

TOOLS_MYCNF=${HOME}/.tools.$$.cnf
cat > $TOOLS_MYCNF << EOL
!include /etc/my.cnf
[client]
user=$TOOLS_USER
password=$TOOLS_PASSWD
EOL

#---------------------------------------------------------------------- help --
help(){
  echo '''
  This script should be used to restore a snapshot in GCP.
   
  Usage:
   
  sh $SCRIPT_NAME.sh [ -t <datetime> ] 
   
  Required:
        -s | --snapshot-info             Snapshot info. SOURCEDISK,TARGETDISK,INSTANCETYPE,PORT,MOUNTNAME (ie. budb001-sdb1,fodb001-sdb1,multi,3301,/db/data/sdb1)
 
  Optional:
        -d | --target-disksize-in-gb )   Disk size of a target host. This option is added to create a disk with then size other then currently assigned.
        -y | --disktype )                Disk Type. (ie. pd-ssd, pd-standard) Default: it will preserve current disktype upon restore.

  Example:
        sh $SCRIPT_NAME.sh -s budb001-sdb1,fodb001-sdb1,multi,3301,/db/data/sdb1
        sh $SCRIPT_NAME.sh -t YYYY-MM-DD_HH:MM:SS
  '''
  exit 1
}

#--------------------------------------------------------------------- debug --
debug() {
    echo "`date "+%Y-%m-%d %H:%M:%S"` [$1] $2" | tee -a $LOG_FILE
     
    [[ "$1" == "Warning" ]] && echo "Exiting..."
    if [[ "$1" == "Error" ]]
    then
        echo "Exiting..."
        rm -f $LOCK_FILE
    fi
    return 0
}
#-------------------------------------------------------------- process_args --
process_args() {
 
  options=$@
 
  # An array with all the arguments
  args=($options)
 
  [[ $args == "--help" || $args == "" ]] && help && exit 1
   
  V_OVERWRITE="N"
  i=0
  for arg in $options
  do
      if [[ ${args[$i]:0:1} == "-" && ${args[$i+1]:0:1} != "-" ]]
      then
          case ${args[$i]} in
             -s | --snapshot-info )          V_SNAPSHOT_INFO=${args[$i+1]};;
             -d | --target-disksize-in-gb )  V_TARGET_DISKSIZE=${args[$i+1]};;
             -y | --disktype )               V_TARGET_DISKTYPE=${args[$i+1]};;
             -c | --command )                V_COMMAND=${args[$i+1]};;
             -m | --mount-name )             V_MOUNTNAME=${args[$i+1]};;
             -o | --overwrite )              V_OVERWRITE="Y";;
             *)                              echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      else
          case ${args[$i]} in
             -o | --overwrite )              V_OVERWRITE="Y";;
          esac
          i=$(($i+1))
      fi
  done
  
  if [ ! -z "${V_COMMAND}" ]
  then
      [[ `/usr/sbin/lsof |grep "$V_MOUNTNAME" |wc -l` -gt 0 ]] && exit 1
      exit 0
  fi
  return
}
 
#---------------------------------------------------------------- mount_disk --
unmount_disk(){
 
  if [ `/bin/lsblk | awk '{print $7}' | grep "$MOUNT_NAME"` ]
  then                                                                                                                                                                      
      /bin/umount $MOUNT_NAME
      [ $? -ne 0 ] && return 1
      debug "Info" "unmount_disk: '$MOUNT_NAME' un-mounted from '$T_HOST'."
  fi
}
 
#--------------------------------------------------------------- detach_disk --
detach_disk(){
   
  if [ `/sbin/blkid | awk '{print $1}' | grep "$OLD_FILESYSTEM"` ]
  then
      $GCLOUD compute instances detach-disk $GCP_INSTANCENAME --disk=$T_DISKNAME --zone=$T_ZONE -q 2>/dev/null
      [ $? -ne 0 ] && return 1
      debug "Info" "detach_disk: '$OLD_FILESYSTEM' detached from '$T_HOST'."
  fi
}
 
#--------------------------------------------------------------- delete_disk --
delete_disk(){
  
  if [[ `$GCLOUD compute disks list | grep "$T_DISKNAME"` ]]
  then
      $GCLOUD compute disks delete $T_DISKNAME --zone=$T_ZONE -q 2>/dev/null
      [ $? -ne 0 ] && return 1
      debug "Info" "delete_disk: '$T_DISKNAME' deleted."
  fi
}
#--------------------------------------------------------------- create_disk --
create_disk(){
   
  if [[ ! `$GCLOUD compute disks list | grep "$T_DISKNAME" |grep "$T_DISKSIZE"` ]]
  then
      $GCLOUD compute disks create $T_DISKNAME --size=$T_DISKSIZE_IN_GB --source-snapshot=$SNAPSHOT_TO_RESTORE --type=$T_DISKTYPE --zone=$T_ZONE -q >/dev/null 2>/dev/null
      [ $? -ne 0 ] && return 1
      debug "Info" "create_disk: '$T_DISKNAME' created using a snapshot of '$SNAPSHOT_TO_RESTORE'."
  fi
}
 
#--------------------------------------------------------------- attach_disk --
attach_disk(){
  if [ ! `/sbin/blkid | awk '{print $1}' | grep "$OLD_FILESYSTEM"` ]
  then
      $GCLOUD compute instances attach-disk $GCP_INSTANCENAME --disk=$T_DISKNAME --zone=$T_ZONE -q 2>/dev/null
      [ $? -ne 0 ] && return 1
      debug "Info" "attach_disk: '$OLD_FILESYSTEM' attached to '$T_HOST'."
  fi
}
 
#--------------------------------------------------------------- modiy_fstab --
modify_fstab() {
   
  if [ ! -z "$OLDUUID" ]
  then
      NEWUUID=`/sbin/blkid -s UUID -o value $OLD_FILESYSTEM 2>/dev/null`
      sed -i "s/$OLDUUID/$NEWUUID/g" /etc/fstab
      debug "Info" "modify_fstab: /etc/fstab Updated with new UUID"
  fi
}
 
#---------------------------------------------------------------- mount_disk --
mount_disk(){
   
  /bin/mount -a
  [ $? -ne 0 ] && return 1
  debug "Info" "mount_disk: '$MOUNT_NAME' mounted to '$T_HOST'."
}
 
#------------------------------------------------------------- func_snapshot --
restore() {
 
  S_DISKNAME=`echo $V_SNAPSHOT_INFO | cut -d',' -f1`
  T_DISKNAME=`echo $V_SNAPSHOT_INFO | cut -d',' -f2`
  T_INSTANCE_TYPE=`echo $V_SNAPSHOT_INFO | cut -d',' -f3`
  T_FQDN=`echo $V_SNAPSHOT_INFO | cut -d',' -f4`
  T_PORT=`echo $V_SNAPSHOT_INFO | cut -d',' -f5`
  MOUNT_NAME=`echo $V_SNAPSHOT_INFO | cut -d',' -f6`
  SNAPSHOT_TO_RESTORE=`echo $V_SNAPSHOT_INFO | cut -d',' -f7`
  GCP_INSTANCENAME=`echo $T_DISKNAME |cut -d '-' -f1` 
 
  S_DATADIR="/db/data/`echo $S_DISKNAME | cut -d'-' -f2`"
  T_DATADIR="/db/data/`echo $T_DISKNAME | cut -d'-' -f2`"
 
  LOCK_FILE=/tmp/${SCRIPT_NAME}_${T_HOST}_${T_PORT}.lock
  LOG_FILE=/tmp/${SCRIPT_NAME}_${T_HOST}_${T_PORT}.log
 
  [ -f $LOCK_FILE ] && debug "Warning" "Another instance of this script is already running" && exit 1
   
  touch $LOCK_FILE
 
  S_ZONE=`$GCLOUD compute disks list | grep $S_DISKNAME | grep -v root | head -1 | awk '{print $2}'`
  [ $? -ne 0 ] && debug "Error" "Unable to execute 'gcloud compute disks list'"
 
  T_ZONE=`$GCLOUD compute disks list | grep $T_DISKNAME | grep -v root | head -1 | awk '{print $2}'`
  [ $? -ne 0 ] && debug "Error" "Unable to execute 'gcloud compute disks list'"
 
  if [[ ! -f $LOG_FILE || "$OVERWRITE" == "Y" || `cat $LOG_FILE |grep "FILESYSTEM" |wc -l` -eq 0 ]]
  then
      [[ `grep "$MOUNT_NAME" /proc/mounts |wc -l` -eq 0 ]] && debug "Error" "'$MOUNT_NAME' not exist on '$T_HOST'" && exit 1
      OLD_FILESYSTEM=`grep "$MOUNT_NAME" /proc/mounts | awk '{print $1}' 2>/dev/null`
      OLDUUID=`/sbin/blkid -s UUID -o value $OLD_FILESYSTEM`
      DISKINFO=`$GCLOUD compute disks list | grep $T_DISKNAME | grep -v root | head -1`
      [ $? -ne 0 ] && debug "Error" "Unable to execute 'gcloud compute disks list'"

      T_ZONE=`echo "$DISKINFO" | awk '{print $2}'`
      T_DISKSIZE=`echo "$DISKINFO" | awk '{print $3}'`
      T_DISKTYPE=`echo "$DISKINFO" | awk '{print $4}'`
      
      [ ! -z "${V_TARGET_DISKSIZE}" ] && T_DISKSIZE=$V_TARGET_DISKSIZE
      [ ! -z "${V_TARGET_DISKTYPE}" ] && T_DISKTYPE=$V_TARGET_DISKTYPE
      
      echo "FILESYSTEM:$OLD_FILESYSTEM|UUID:$OLDUUID|T_DISKSIZE_IN_GB:${T_DISKSIZE}GB|T_ZONE:${T_ZONE}|T_DISKTYPE:${T_DISKTYPE}" > $LOG_FILE
  fi   
  
  OLD_FILESYSTEM=`cat $LOG_FILE |grep "FILESYSTEM" |cut -d'|' -f1 |cut -d':' -f2`
  OLDUUID=`cat $LOG_FILE |grep "FILESYSTEM" |cut -d'|' -f2 |cut -d':' -f2`
  T_DISKSIZE_IN_GB=`cat $LOG_FILE |grep "FILESYSTEM" |cut -d'|' -f3 |cut -d':' -f2`
  T_ZONE=`cat $LOG_FILE |grep "FILESYSTEM" |cut -d'|' -f4 |cut -d':' -f2`
  T_DISKTYPE=`cat $LOG_FILE |grep "FILESYSTEM" |cut -d'|' -f5 |cut -d':' -f2`

  # Un-mount old disk
  if [ `grep "FILESYSTEM:" $LOG_FILE |tail -1 |grep "FILESYSTEM:" |wc -l` -eq 1 ]
  then
      unmount_disk
      [ $? -ne 0 ] && debug "Error" "Error occurred while un-mounting '$MOUNT_NAME' from '$T_HOST'" && rm -f $LOG_FILE && exit 1
  fi
 
  # Detach old disk from the instance
  if [ `grep "Info" $LOG_FILE | tail -1 |grep "unmount_disk:" |wc -l` -eq 1 ]
  then
      detach_disk
      if [ $? -ne 0 ]
      then
          mount_disk
          [ $? -ne 0 ] && debug "Error" "Error occurred while mounting '$MOUNT_NAME to '$T_HOST'"
          rm -f $LOG_FILE
          exit 1
      fi
  fi   
 
  # Delete old disk
  if [ `grep "Info" $LOG_FILE | tail -1 | grep "detach_disk:" |wc -l` -eq 1 ]
  then
      delete_disk
      if [ $? -ne 0 ]
      then
          attach_disk
          [ $? -ne 0 ] && debug "Error" "Error occurred while attaching '$OLD_FILESYSTEM' to '$T_HOST'" && exit 1
       
          mount_disk
          [ $? -ne 0 ] && debug "Error" "Error occurred while mounting '$MOUNT_NAME to '$T_HOST'"
          rm -f $LOG_FILE
          exit 1
      fi
  fi   
   
  # Create new disk using snapshot
  if [ `grep "Info" $LOG_FILE | tail -1 | grep "delete_disk:" |wc -l` -eq 1 ]
  then
      create_disk
      [ $? -ne 0 ] && debug "Error" "Error occurred while creating '$T_DISKNAME'" && exit 1
  fi
 
  # Attache newly create disk to the instance
  if [ `grep "Info" $LOG_FILE | tail -1 | grep "create_disk:" |wc -l` -eq 1 ]
  then
      attach_disk
      [ $? -ne 0 ] && debug "Error" "Error occurred while attaching '$OLD_FILESYSTEM' to '$T_HOST'." && exit 1
  fi
 
  # Modify /etc/fstab to replace UUID of old disk with new disk
  if [ `grep "Info" $LOG_FILE | tail -1 | grep "attach_disk:" |wc -l` -eq 1 ]
  then
      modify_fstab
      [ $? -ne 0 ] && debug "Error" "Error occurred while modifying /etc/fstab on '$T_HOST'." && exit 1
  fi
 
  # Mount new disk
  if [ `grep "Info" $LOG_FILE | tail -1 | grep "modify_fstab:" |wc -l` -eq 1 ]
  then
      mount_disk
      [ $? -ne 0 ] && debug "Error" "Error occurred while mounting '$MOUNT_NAME' to '$T_HOST'." && exit 1
  fi
  
  [ ! -z "${V_TARGET_DISKSIZE}" ] && /sbin/resize2fs $OLD_FILESYSTEM 2>/dev/null
      
  # Start mysql and replication
 
  chown -R mysql:mysql $MOUNT_NAME
 
  sed -i "s,$S_DATADIR,$T_DATADIR,g" $T_DATADIR/logs/binlogs/*.index
  sed -i "s,$S_DATADIR,$T_DATADIR,g" $T_DATADIR/logs/relaylogs/*.index
 
  [ -f $MOUNT_NAME/mysql/auto.cnf ] && rm -f $MOUNT_NAME/mysql/auto.cnf
 
  if [[ "$T_INSTANCE_TYPE" == "single" ]]
  then
      nohup service mysql start > /dev/null 2>&1 &
  else
      T_INSTANCENUM=$(($T_PORT % 3300))
      mysqld_multi start $T_INSTANCENUM
  fi
 
  # Keep checking every 2 seconds for 15 minutes until MySQL gets started.
  for i in {1..450}
  do 
      [ `netstat -lnt | awk '$4 ~ /:'$T_PORT'$/' |wc -l` -gt 0 ] && break
      sleep 2
  done
  
  [ `netstat -lnt | awk '$4 ~ /:'$T_PORT'$/' |wc -l` -eq 0 ] && debug "Error" "Unable to start MySQL on '$T_HOST:$T_PORT'"
   
  rm -f $LOCK_FILE $LOG_FILE
}
 
#---------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  restore
  return 0
}
 
main $*
