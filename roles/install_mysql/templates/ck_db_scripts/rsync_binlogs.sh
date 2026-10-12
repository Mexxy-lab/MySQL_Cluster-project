#!/bin/bash
# =============================================================================
# {% for line in fileBanner %}
# {{line}} {% endfor %}
# =============================================================================

###############################################################################
#
# Auther : Ashok Jivani
# Purpose: This script should be used to backup binary logs using RSYNC. 
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

TMPFILE="/tmp/rsync_binlogs.$$.tmp"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`

#--------------------------------------------------------------------- debug --
debug() { 
    echo "`date "+%Y-%m-%d %H:%M:%S"` $1 $2" >> $LOG_FILE 2>&1
    [ "$1" == "[Error]" ] && rm -f $TMPFILE $LOCKFILE && exit 1
}

#---------------------------------------------------------------------- help --
help(){
  echo "" 
  echo "This script should be used to backup given database instance using xtrabackup."
  echo ""
  echo "Usage:"
  echo ""
  echo "sh $SCRIPT_NAME.sh < REQUIRED > [ OPTIONAL ]"
  echo ""
  echo "  Required:"
  echo "      -i | --instance-name  Instance Name (ie. mdb, sdb1)"
  echo ""
  echo "  Optional:"
  echo "      -r | --retention      Retention Period in Days. Default 30 days (ie. 15)"
  echo ""
  echo "  Example:"
  echo ""
  echo " sh $SCRIPT_NAME.sh -i sdb1 --retention 30"
  exit 1
}

#-------------------------------------------------------------- process_args --
process_args() {

  options=$@

  # An array with all the arguments
  args=($options)

  [[ $args == "--help" || $args == "" ]] && help && exit 1

  V_PREPARE="N"
  i=0
  for arg in $options
  do
      if [[ ${args[$i]:0:1} == "-" && ${args[$i+1]:0:1} != "-" ]]
      then
          case ${args[$i]} in
            -i | --instance-name )    V_INSTANCE_NAME=${args[$i+1]};;
            -r | --retention )        V_RETENTION=${args[$i+1]};;
             *)                       echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      fi
  done

  [ -z "${V_INSTANCE_NAME}" ] && debug "[Error]" "Please specify 'Instance Name' for -i or --instance-name option. See --help for help"
  
  [ -z "${V_RETENTION}" ] && V_RETENTION=30

  LOG_FILE=/var/log/${SCRIPT_NAME}-${V_INSTANCE_NAME}.log
  V_GROUP=`cat /etc/my.cnf |grep "\[mysqld\|datadir" |grep "$V_INSTANCE_NAME" -B 1 |head -1 |tr -d "[]"`
  V_BINLOG_DIR=`dirname \`sed -n "/\[$V_GROUP\]/,/\[/p" /etc/my.cnf |grep "log_bin" |awk -F"=" '{print $2}' |sed -e 's/^ *//' -e 's/ *$//'\``
  
  [ ! -d $V_BINLOG_DIR ] && debug "[Error]" "Binlog_backup=Failed host=`hostname` instance=$V_INSTANCE_NAME binlog directory not exists."
}

#-------------------------------------------------------------- rsync_binlogs --
rsync_binlogs() {

  TMPFILE=/tmp/${SCRIPT_NAME}_${INSTANCE_NAME}.out
  LOCKFILE=/tmp/${SCRIPT_NAME}_${INSTANCE_NAME}.lock
  TARGET_DIR=/backup/xtrabackup-${V_INSTANCE_NAME}/binlogs

  [ -f $LOCKFILE ] && exit 1
  touch $LOCKFILE

  rsync -avhi `find $V_BINLOG_DIR -mtime -$V_RETENTION -type f` $TARGET_DIR > $TMPFILE  2>&1
  [ $? -ne 0 ] && debug "[Error]" "Binlog_backup=Failed host=`hostname` instance=$V_INSTANCE_NAME rsync failed."
 
  # Removing old binlog files.
  find $TARGET_DIR -mtime +$V_RETENTION -type f -exec rm {} \;
  [ $? -ne 0 ] && debug "[Error]" "Binlog_backup=Failed host=`hostname` instance=$V_INSTANCE_NAME Not able to remove old files."

  debug "[Info]" "Binlog_backup=Completed host=`hostname` instance=$V_INSTANCE_NAME"
  
  rm -f $LOCKFILE

  return 0
}

#----------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  rsync_binlogs
  return 0
}

main $*

