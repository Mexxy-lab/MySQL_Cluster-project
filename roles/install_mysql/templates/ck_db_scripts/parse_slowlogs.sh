#!/bin/bash
# =============================================================================

###############################################################################
#
# Auther : Ashok Jivani
# Purpose: This script should be used to rotate slow query logs, parse them
#          and loading the output to the opsdb server.
# Usage  : script_name.sh
#
###############################################################################
TODAY=`date "+%Y-%m-%d"`
HOSTNAME=`hostname`
SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TMP_FILE=/tmp/${SCRIPT_NAME}.$$
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"

. ${PARAMETER_FILE}
USER=${BACKUP_USER}       # username
PASSWD=${BACKUP_PASSWD}     # password

DAY_OF_WEEK=$(date +%u)
DAYS=0
[ $DAY_OF_WEEK -eq 3 ] && DAYS="3"
[ $DAY_OF_WEEK -eq 7 ] && DAYS="4"

ENDDATE=`date "+%Y-%m-%d"`                                                                                                                                                   
STARTDATE=`date --date="$ENDDATE -$DAYS days" "+%Y-%m-%d"`
SINCE="$STARTDATE 00:00:00"
UNTIL="$ENDDATE 23:00:00"


[[ "$HOSTNAME" == *"euw2"* ]] && OPSDB="opsdb001.prod.euw2.ckint.io"

#--------------------------------------------------------------------- debug --
debug() {
  echo "$1 Exiting..."
  exit 1
}

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
             -s | --send-opsdb )                  V_SEND_TO_OPSDB=${args[$i+1]};;
             -f | --force-parsing )               V_FORCE_PARSING=${args[$i+1]};;
                            *)                  echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      fi
    done
}

#----------------------------------------------------------- parse_slow_logs --
parse_slow_logs() {
  HOST_PREFIX=$1
  PASS_LOG_TO_OPSDB=${V_SEND_TO_OPSDB}
  MY_AUTH="mysql -u ${USER} -p${PASSWD} "
  [[ "$HOST_PREFIX" == "shard_master" ]] && MY_AUTH=`cat /root/msdb1`

  SLOW_LOG_FILE=`$MY_AUTH -NB -e"select @@global.slow_query_log_file"`
  if [ -s "${SLOW_LOG_FILE}"  ]
  then
      #HOST_PREFIX=`mysql -u$TOOLS_USER -p$TOOLS_PASSWD -hopsdb1.sjc1.creditkarma.com -NB -e"select replace(concat(hostname,\"_\",port), \".\", \"_\") from $ADMIN_SCHEMA.$ADMIN_TABLE where fqdn='$HOSTNAME'"`
      #[ $? -ne 0 ] && debug "[Error] Error occured during executing query against opsdb server."
      
      # Parse slow logs and send to opsdb server
      if [[ "${PASS_LOG_TO_OPSDB}" ]]; then
            /usr/bin/pt-query-digest --user=$TOOLS_USER --password=$TOOLS_PASSWD --host=$OPSDB --history D=slowlogs,t=slogs_$HOST_PREFIX --no-report --limit=100% --since="$SINCE" --until="$UNTIL" $SLOW_LOG_FILE
            [ $? -ne 0 ] && debug "[Error] Error occurred during running pt-query-digest."
      else
            /usr/bin/pt-query-digest --limit=100% --since="$SINCE" --until="$UNTIL"   $SLOW_LOG_FILE
            [ $? -ne 0 ] && debug "[Error] Error occurred during running pt-query-digest."
      fi
  fi
  rm -f $TMP_FILE
  exit
}

#---------------------------------------------------------------- check_host --
check_host() {
  PASS_LOG_TO_OPSDB=${V_SEND_TO_OPSDB}
  FORCE_EXECUTION=${V_FORCE_PARSING}
  [[ ${FORCE_EXECUTION} ]] && parse_slow_logs 'no-host-prefix'  ${FORCE_EXECUTION}
  # Check for mono master
  SESSION_ID_WITH_LOCK=$(curl -s http://127.0.0.1:8500/v1/kv/masterlock/mdb/.lock | python -m json.tool 2>/dev/null | grep Session | cut -f4 -d'"')
  [ "$SESSION_ID_WITH_LOCK" != "" ] && [ "`curl -s http://127.0.0.1:8500/v1/session/info/${SESSION_ID_WITH_LOCK} | python -m json.tool 2>/dev/null |grep Node | cut -f4 -d '"'`" == "$HOSTNAME" ] && parse_slow_logs mono_master   ${PASS_LOG_TO_OPSDB}

  # Check for sdb1 master
  SESSION_ID_WITH_LOCK=$(curl -s http://127.0.0.1:8500/v1/kv/masterlock/sdb1/.lock | python -m json.tool 2>/dev/null | grep Session | cut -f4 -d'"')
  [ "$SESSION_ID_WITH_LOCK" != "" ] && [ "`curl -s http://127.0.0.1:8500/v1/session/info/${SESSION_ID_WITH_LOCK} | python -m json.tool 2>/dev/null |grep Node | cut -f4 -d '"'`" == "$HOSTNAME" ] && parse_slow_logs shard_master   ${PASS_LOG_TO_OPSDB}

  # Check for mono read slave
  SESSION_ID_WITH_LOCK=$(curl -s http://127.0.0.1:8500/v1/kv/masterlock/mdb/.lock | python -m json.tool 2>/dev/null | grep Session | cut -f4 -d'"')
  [ "$SESSION_ID_WITH_LOCK" != "" ] && [ "`curl -s http://127.0.0.1:8500/v1/session/info/${SESSION_ID_WITH_LOCK} | python -m json.tool 2>/dev/null |grep Node | cut -f4 -d '"'`" == "$HOSTNAME" ] && exit  
 
  IS_MONO="N"
  NODE_MAINTENANCE="N"
  SLAVE_CANDIDATE="N"
  curl -s http://127.0.0.1:8500/v1/health/node/$HOSTNAME | python -m json.tool 2>/dev/null > $TMP_FILE
 
  [[ `cat $TMP_FILE |grep "Service mdb"` ]] && IS_MONO="Y"
  [[ `cat $TMP_FILE |grep "CheckID.*_node_maintenance"` ]] && NODE_MAINTENANCE="Y"
  [[ `cat $TMP_FILE |grep "ServiceName.*ro"` ]] && SLAVE_CANDIDATE="Y"
  [[ "$IS_MONO" == "Y" && "$NODE_MAINTENANCE" == "N" && "$SLAVE_CANDIDATE" == "Y" ]] && parse_slow_logs mono_slave  ${PASS_LOG_TO_OPSDB}
}

#----------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  check_host
  return 0
}

main $*
