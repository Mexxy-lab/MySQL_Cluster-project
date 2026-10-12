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
# Purpose: This script should be used to scan binlog files for drop/truncate
#          events and log GTID before the event to Opsdb.
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`

TOOLS_MYCNF=${HOME}/.tools.$$.cnf
cat > $TOOLS_MYCNF << EOL
!include /etc/my.cnf
[client]
user=$TOOLS_USER
password=$TOOLS_PASSWD
EOL

LOCAL_MYCNF=${HOME}/.local.$$.cnf
cat > $LOCAL_MYCNF << EOL
!include /etc/my.cnf
[client]
user=$BACKUP_USER
password=$BACKUP_PASSWD
EOL

export TOOLS_AUTH="mysql --defaults-file=$TOOLS_MYCNF"
export LOCAL_AUTH="mysql --defaults-file=$LOCAL_MYCNF"

#---------------------------------------------------------------------- help --
help(){
  echo '''
  This script should be used to scan binlogs files to find drop/truncate events.

  Usage:
      sh $SCRIPT_NAME.sh < REQUIRED > [ OPTIONAL ]

      Required:
             -s | --socket                MySQL socket path

      Optional:
             -t | --event-time            Estimated event time (ie 2019-01-01_10:00:00)
             -n | --last-binlog-files     Last binary log files to scan (ie. 3, 5)
             -l | --list                  List binlogs

      Example:
             sh $SCRIPT_NAME.sh --socket /db/data/sdb1/mysql/mysql.sock --event-time 2019-01-01_10:00:00
  '''
}
#--------------------------------------------------------------------- debug --
debug() {
  echo "`date "+%Y-%m-%d %H:%M:%S"` [$1] $2"                                                                                                                              
  if [[ "$1" == "Error" ]] 
  then
      rm -f $TOOLS_MYCNF $LOCAL_MYCNF
      echo "Exiting..." 
      exit 1
  fi
}

#-------------------------------------------------------------- process_args --
process_args() {

  options=$@

  # An array with all the arguments
  args=($options)

  [[ $args == "--help" || $args == "" ]] && help && exit 1

  V_LIST="N"
  for arg in $options
  do
      if [[ ${args[$i]:0:1} == "-" && ${args[$i+1]:0:1} != "-" ]]
      then
          case ${args[$i]} in
              -s | --socket )               V_SOCKET=${args[$i+1]};;
              -l | --list )                 V_LIST="Y";;
              -t | --event-time )           V_EVENT_TIME=${args[$i+1]};;
              -x | --last-binlog-files )    V_BINLOG_COUNT=${args[$i+1]};;
               *)                           echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      else
          case ${args[$i]} in
              -l | --list )                 V_LIST="Y";;
          esac
          i=$(($i+1))
      fi
  done

  [ -z "${V_SOCKET}" ] && debug "Error" "Please specify 'Socket' for --socket option. See --help for help." && exit 1
  [[ -z "${V_EVENT_TIME}" && -z "${V_BINLOG_COUNT}" ]] && debug "Error" "Please specify either --event-time or --last-binlog-files option. See --help for help." && exit 1

  [ ! -z "${V_EVENT_TIME}" ] &&  V_EVENT_TIME=`echo $V_EVENT_TIME | awk -F"_" '{print $1 " " $2}'`

}

#--------------------------------------------------------------- scan_binlog --
scan_binlog() {

  # Find binlog location
  BINLOG_PATH=`$LOCAL_AUTH -S $V_SOCKET -NB -e"SELECT SUBSTRING_INDEX(@@global.log_bin_basename, '/', 7);"`
  [ $? -ne 0 ] && debug "Error" "Unable to execute sql to get binlog path from OpsDB"
  
  EVENT_PATTERN="drop table\|truncate table"
  [ ! -z "${V_EVENT_TIME}" ] && SCAN_LIST=`find $BINLOG_PATH -newermt "$V_EVENT_TIME" -type f -name "*."?????? | sort | uniq | xargs -n 1 basename`
  [ ! -z "${V_BINLOG_COUNT}" ] && SCAN_LIST=`find $BINLOG_PATH -type f -name "*."?????? | sort | uniq | xargs -n 1 basename | tail -n $V_BINLOG_COUNT`

  if [ ! -z "${SCAN_LIST}" ]
  then
      HOSTINFO=`$LOCAL_AUTH -S $V_SOCKET -NB -e"SELECT CONCAT(@@report_host, ':', @@port)"`
      [ $? -ne 0 ] && debug "Error" "Unable to execute a query on `hostname -f`."
      HOST=`echo "$HOSTINFO" | cut -d':' -f1`
      PORT=`echo "$HOSTINFO" | cut -d':' -f2`
      
      INSTANCENAME=`$TOOLS_AUTH -h $LOCAL_OPSDB -P 3306 -NB -e"SELECT instanceName FROM $ADMIN_SCHEMA.$ADMIN_TABLE WHERE fqdn = '$HOST' AND port = '$PORT'"`
      [ $? -ne 0 ] && debug "Error" "Unable to execute a query on OpsDB."
      
      if [[ "$V_LIST" == "Y" ]]
      then
          echo "$HOST:$PORT:"
          echo "$SCAN_LIST"
      else
          while IFS= read -r BINLOG_FILE
          do
              debug "Info" "Processing $HOST:$PORT:$BINLOG_FILE"
              binlogEvents1=`$LOCAL_AUTH -S $V_SOCKET -NB -e"SHOW BINLOG EVENTS IN '$BINLOG_FILE'"`
              [ $? -ne 0 ] && debug "Error" "Unable to execute 'SHOW BINLOG EVENTS' sql on '$HOST:$PORT'"
              
              SQL=""
              binlogEvents=`( tr -s ' ' | grep -i "$EVENT_PATTERN" -B 1 ) <<< "$binlogEvents1"`
              if [ ! -z "${binlogEvents}" ]
              then
                  while IFS= read -r currentEvent
                  do
                      if [[ `echo "$currentEvent" | tr -s ' ' |grep -i "$EVENT_PATTERN"` ]]
                      then
                          EVENT_GTID=`echo "$prevEvent" | grep "GTID_NEXT" | cut -f 6 |cut -d'=' -f2 |sed -e 's/^ *//' -e 's/ *$//'  | sed "s/'//g"`
                          EVENT_STATEMENT=`echo "$currentEvent" | grep -i "$EVENT_PATTERN" |cut -f 6 |sed -e 's/^ *//' -e 's/ *$//'  | sed "s/'//g"`
                          SQL="$SQL INSERT IGNORE INTO scan_binlogs_gcp (eventHost, eventPort, eventInstanceName, eventGtid, eventStatement) VALUES ('$HOST', $PORT, '$INSTANCENAME', '$EVENT_GTID', '$EVENT_STATEMENT');" 
                      fi
                      prevEvent=$currentEvent
                  done <<< "$binlogEvents"
              fi    
      
              if [ "${SQL}" != "" ]
              then
                  $TOOLS_AUTH -h $LOCAL_OPSDB -P 3306 -A $ADMIN_SCHEMA -e"$SQL" 2>&1
                  [ $? -ne 0 ] && debug "Error" "Unable to execute 'INSERT INTO $ADMIN_SCHEMA.scan_binlogs_gcp' sql on OpsDB"
              fi
          done <<< "$SCAN_LIST"
      fi
  fi
  rm -f $TOOLS_MYCNF $LOCAL_MYCNF
}

#----------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  scan_binlog
  return 0
}

main $*
