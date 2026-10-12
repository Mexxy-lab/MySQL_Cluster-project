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

PASSWD_FILE=$HOME/.ssh.$$.key
SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`

TOOLS_MYCNF=${HOME}/.tools.$$.cnf
cat > $TOOLS_MYCNF << EOL
!include /etc/my.cnf
[client]
user=$TOOLS_USER
password=$TOOLS_PASSWD
EOL

export TOOLS_AUTH="mysql --defaults-extra-file=$TOOLS_MYCNF"
export BKPUSER=`whoami`

#---------------------------------------------------------------------- help --
help(){
  echo '''
  This script should be used to scan binlogs files to find drop/truncate events.

  Usage:
      sh $SCRIPT_NAME.sh < REQUIRED > [ OPTIONAL ]

      Required:
          -d | --data-center           Data Center code (ie. euw2, cke)
          -g | --group                 Group (ie. mdb, tkdb, fldb, fodb, budb, ipdb)

      Optional:
          -n | --instance-number       Filter by instance_number. (ie 1,2,3 or 1-3,5-9)
          -h | --hostname              Filter by Hostname (ie. bkpmdbnew001.us-central1, bkppdbnew001.us-central1)
          -p | --parallel              Parallel threads per host. Default is 1
          -z | --serialize )           Running snapshot restore sequentially (meaning only one restore at a time). Default is one-restore-per-host
          -t | --event-time            Estimated event time (ie 2019-01-01_10:00:00)
          -x | --last-binlog-files     Last binary log files to scan (ie. 3, 5)
          -l | --list                  List binlogs

      Example:
         To scan files (2 per host) newer then '2019-01-01 10:00:00': 
            sh $SCRIPT_NAME.sh -d euw2 -g budb -p 2 --event-time 2019-01-01_10:00:00
       
         To scan last 2 files: 
            sh $SCRIPT_NAME.sh -d euw2 -g budb --last-binlog-files 2
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
  V_PARALLEL=1
  V_LIST="N"
  for arg in $options
  do
      if [[ ${args[$i]:0:1} == "-" && ${args[$i+1]:0:1} != "-" ]]
      then
          case ${args[$i]} in
              -d | --data-center )          V_DATA_CENTER=${args[$i+1]};;
              -g | --group )                V_GROUP=${args[$i+1]};;
              -n | --instance-number )      V_INSTANCE_NUMBER=${args[$i+1]};;
              -h | --hostname )             V_HOSTNAME=${args[$i+1]};;
              -l | --list )                 V_LIST="Y";;
              -p | --parallel )             V_PARALLEL=${args[$i+1]};;
              -z | --serialize )            V_SERIALIZE="Y";; 
              -t | --event-time )           V_EVENT_TIME=${args[$i+1]};;
              -x | --last-binlog-files )    V_BINLOG_COUNT=${args[$i+1]};;
               *)                           echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      else
          case ${args[$i]} in
              -l | --list )                 V_LIST="Y";;
              -z | --serialize )            V_SERIALIZE="Y";;
          esac
          i=$(($i+1))
      fi
  done
  [ -z "${V_DATA_CENTER}" ] && debug "Error" "Please specify 'Data Center' for -d option. See --help for help."
  [ -z "${V_GROUP}" ] && debug "Error" "Please specify 'Group' for -g option. See --help for help."
  [[ -z "${V_EVENT_TIME}" && -z "${V_BINLOG_COUNT}" ]] && debug "Error" "Please specify either --event-time or --last-binlog-files option. See --help for help."
  [ ! -z "${V_EVENT_TIME}" ] && SCAN_FILTER="--event-time $V_EVENT_TIME"
  [ ! -z "${V_BINLOG_COUNT}" ] && SCAN_FILTER="--last-binlog-files $V_BINLOG_COUNT"
  [[ "${V_LIST}" == "Y" ]] && SCAN_FILTER="$SCAN_FILTER --list"
  [[ ${V_PARALLEL} -gt 4 ||  -z "${V_PARALLEL}" ]] && V_PARALLEL=4

  RANGE=""
  [ ! -z "${V_DATA_CENTER}" ] && DCENTERS=`echo $V_DATA_CENTER | sed "s/,/','/g"` && RANGE="where dataCenter in ('$DCENTERS')"
  [ ! -z "${V_GROUP}" ] && GRPS=`echo $V_GROUP | sed "s/,/','/g"` && RANGE="$RANGE and groupName in ('$GRPS')"
  [ ! -z "${V_INSTANCE_NUMBER}" ] && RANGE="$RANGE and shardNumber in (`echo $V_INSTANCE_NUMBER | awk 'BEGIN { RS=","; FS="-"; ORS="" } NR > 1 { print "," } NF > 1  { for (i=$1; i<$2; ++i) { print i "," } print $2; next } { print $1 }'`)"
  [ ! -z "${V_HOSTNAME}" ] && HOSTS=`echo $V_HOSTNAME | sed "s/,/','/g"` && RANGE="$RANGE and hostname in ('$HOSTS')"

  HOSTLIST=`$TOOLS_AUTH -NB -e"select concat(fqdn, \":\", port, \":\", socket) from $ADMIN_SCHEMA.$ADMIN_TABLE $RANGE"`
  [ $? -ne 0 ] && debug "Error" "Please check if 'Data Center' and/or 'Shard Group' is valid."
}

#--------------------------------------------------------- func_scan_binlogs --
func_scan_binlogs() {
 
  while read INPUTS
  do
      T_FQDN=`echo $INPUTS | cut -d":" -f1`
      T_PORT=`echo $INPUTS | cut -d":" -f2`
      T_SOCKET=`echo $INPUTS | cut -d":" -f3`
 
      TARGET_SSH="ssh -n -o LogLevel=Error -o StrictHostKeyChecking=no $BKPUSER@$T_FQDN"
      TARGET_SCRIPT="/usr/local/bin/target_scan_binlogs.sh"
       
      # Making sure that target script is available.
      $TARGET_SSH "test -f $TARGET_SCRIPT"
      [ $? -ne 0 ] && debug "Error" "file $TARGET_SCRIPT does not exists on '$T_FQDN'."
 
      # Executing target script.
      $TARGET_SSH "sudo $TARGET_SCRIPT -s $T_SOCKET $SCAN_FILTER"
      [ $? -ne 0 ] && debug "Error" "Binlog scan failed on '$T_FQDN:$T_PORT'"
  done < $1
 
  return 0
}
#-------------------------------------------------------------- scan_binlogs --
scan_binlogs() {
 
  # Starting ssh-agent
  ssh-agent -s > $PASSWD_FILE
  . $PASSWD_FILE >/dev/null
  ssh-add 2>/dev/null
   
 [[ "$V_LIST" == "N" ]] && debug "Info" "Scanning of binlogs has started"
 
  # Splitting the input to per host files depending on parallelism value.
  CNT=0
  for HOSTINFO in $HOSTLIST
  do
       HOSTNAME=`echo $HOSTINFO | cut -d ":" -f1`
       HOSTNUM=`echo $HOSTINFO | cut -d ":" -f1 | cut -d"." -f1 |grep -o "...$" | bc`
       FILENUM=$(( $CNT % $V_PARALLEL ))
       echo "$HOSTINFO" >> /tmp/${SCRIPT_NAME}_runme_${HOSTNAME}_${FILENUM}.$$
      CNT=$(( CNT+1 ))
  done
 
  for HOSTRUNNER in `ls /tmp |grep $SCRIPT_NAME | grep runme | grep $$`
  do
      if [ "$V_SERIALIZE" == "N" ]
      then
          func_scan_binlogs /tmp/$HOSTRUNNER &
      else   
          func_scan_binlogs /tmp/$HOSTRUNNER
      fi
   done
   
  wait
 
  # Stopping ssh-agent
  ssh-add -D > /dev/null 2>&1
  ssh-agent -k > /dev/null 2>&1
  rm -f $PASSWD_FILE
 
  [[ "$V_LIST" == "N" ]] && debug "Info" "Binlog scaning completed."
 
  rm -f $TOOLS_MYCNF
 
  return 0
}
 
#---------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  scan_binlogs
  return 0
}

main $*
