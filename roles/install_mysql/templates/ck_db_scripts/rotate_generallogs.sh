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
# Purpose: This script should be used to rotate general log file. 
#
###############################################################################
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"
. ${PARAMETER_FILE}
TS=`date "+%Y%m%d_%H%M%S"`
SHORT_HOSTNAME=`hostname -s`
SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
USER=${BACKUP_USER}         # username
PASSWD=${BACKUP_PASSWD}     # password

debug() {
  echo "$1 Exiting..."
    $MY_AUTH -e "set global general_log=1;"
  exit 1
}

rotate_general_logs() {

    if [`$MY_AUTH -NB -e"select @@version;" | grep '5.'`   ]; then
        GENERAL_LOG_FILE=`$MY_AUTH -NB -e"select variable_value from information_schema.global_variables where variable_name = 'general_log_file'"`
    else
        GENERAL_LOG_FILE=`$MY_AUTH -NB -e"select variable_value from performance_schema.global_variables where variable_name = 'general_log_file'"`
    fi
      
  if [ -f "${GENERAL_LOG_FILE}" ]
  then
      GENERAL_LOG_DIR=$(dirname ${GENERAL_LOG_FILE})
      BACKUP_FILE=$GENERAL_LOG_DIR/general_log_`hostname -s`_${TS}.log
      
      # Disabling general logging.
      $MY_AUTH -e "set global general_log=0;"    
          
      # Copying general log file.
      cp $GENERAL_LOG_FILE $BACKUP_FILE 
      [ $? -ne 0 ] && debug "[Error] Error occured during copying general log file."
  
      # Emptying general log file.
      > $GENERAL_LOG_FILE
      [ $? -ne 0 ] && debug "[Error] Error occured during emptying slow query log file."
          
      # Enabling general logging.
      $MY_AUTH -e "set global general_log=1;"
  
      # Delete older general logs
      find $GENERAL_LOG_DIR -name 'general_log*.log' -type f -mmin +1440 -delete
  fi
  return 
} 

if [ `ls -rt /root | grep msdb |wc -l` -gt 0 ]
then
    ls -rt /root |grep msdb | while read line
    do
        MY_AUTH=`cat /root/$line`
        # IS_ENABLED=`$MY_AUTH -NB -e"select variable_value from information_schema.global_variables where variable_name = 'general_log'"`
        if [`$MY_AUTH -NB -e"select @@version;" | grep '5.'`   ]; then
            IS_ENABLED=`$MY_AUTH -NB -e"select variable_value from information_schema.global_variables where variable_name = 'general_log'"`
        else
            IS_ENABLED=`$MY_AUTH -NB -e"select variable_value from performance_schema.global_variables where variable_name = 'general_log'"`
        fi
        [[ "$IS_ENABLED" == "ON" ]] && rotate_general_logs
    done

else
    MY_AUTH="mysql -u ${USER} -p${PASSWD} "
    # IS_ENABLED=`$MY_AUTH -NB -e"select variable_value from information_schema.global_variables where variable_name = 'general_log'"`
    if [`$MY_AUTH -NB -e"select @@version;" | grep '5.'`   ]; then
        IS_ENABLED=`$MY_AUTH -NB -e"select variable_value from information_schema.global_variables where variable_name = 'general_log'"`
    else
        IS_ENABLED=`$MY_AUTH -NB -e"select variable_value from performance_schema.global_variables where variable_name = 'general_log'"`
    fi
    [[ "$IS_ENABLED" == "ON" ]] && rotate_general_logs
fi
