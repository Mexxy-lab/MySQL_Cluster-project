#!/bin/bash
###############################################################################
#
# Auther : Ashok Jivani
# Purpose: This script should be used to rotate slow query logs, parse them
#          and loading the output to the opsdb server.
# Usage  : script_name.sh
#
###############################################################################

TODAY=`date "+%Y-%m-%d"`
SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"
. ${PARAMETER_FILE}
USER=${BACKUP_USER}       # username
PASSWD=${BACKUP_PASSWD}     # password

debug() {
  echo "$1 Exiting..."
    $MY_AUTH -e "set global slow_query_log=1;"
  exit 1
}

rotate_slow_logs() {
 
    if [`$MY_AUTH -NB -e"select @@version;" | grep '5.'`   ]; then
        SLOW_LOG_FILE=`$MY_AUTH -NB -e"select variable_value from information_schema.global_variables where variable_name = 'slow_query_log_file'"`
    else
        SLOW_LOG_FILE=`$MY_AUTH -NB -e"select variable_value from performance_schema.global_variables where variable_name = 'slow_query_log_file'"`
    fi
      
  if [ -f "${SLOW_LOG_FILE}" ]
  then
      [ ! -s "${SLOW_LOG_FILE}" ] && debug "[INFO] Slow query log file is empty."
  
      SLOW_LOG_DIR=$(dirname ${SLOW_LOG_FILE})
      BACKUP_FILE=$SLOW_LOG_DIR/slow_queries_`hostname -s`_${TODAY}.log
      [ -f "${BACKUP_FILE}" ] && debug "Slow query log already been rotated for '$TODAY'."
      
      # Disabling slow query logging.
      $MY_AUTH -e "set global slow_query_log=0;"    
          
      # Copying slow query log file.
      cp $SLOW_LOG_FILE $BACKUP_FILE 
      [ $? -ne 0 ] && debug "[Error] Error occurred during copying slow query log file."
  
      # Emptying slow query log file.
      > $SLOW_LOG_FILE
      [ $? -ne 0 ] && debug "[Error] Error occurred during emptying slow query log file."

      # delete old
      find $SLOW_LOG_DIR -mtime +30 -name '*slow_queries_*' -exec rm -- '{}' \;

      # Enabling sloq query logging.
      $MY_AUTH -e "set global slow_query_log=1;"
  fi
  return 
} 

if [ `ls -rt /root | grep msdb |wc -l` -gt 0 ]
then
    ls -rt /root |grep msdb | while read line
    do
        MY_AUTH=`cat /root/$line`
        rotate_slow_logs
    done

else
    MY_AUTH="mysql -u ${USER} -p${PASSWD} "
    rotate_slow_logs
fi
