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
# Purpose: This script should be used for vault token tables cleanup/rollback 
#
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

DT=`date +'%Y%m%d%H%M%S'`
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="/usr/local/bin/parameter.txt"

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
LOG_FILE=/tmp/${SCRIPT_NAME}_${DT}.log

rm -f /tmp/${SCRIPT_NAME}_authentication_holder_request_parameter*

#---------------------------------------------------------------------- help --
help(){
  echo "###############################################################################"
  echo ""
  echo "This script should be used for vault token tables cleanup/rollback."
  echo ""
  echo "Usage:"
  echo ""
  echo "$SCRIPT_NAME.sh"
  echo ""
  echo "  Optional"
  echo "      -t or --tablename       Table (schema.tablename)"
  echo "      -b or --batchsize       Batch Size (default 10000000)"
  echo "      -r or --rollback        to Rollback"
  echo "      -p or --parallel        parallelism for inserts (default 8)"
  echo "      "
  echo "  Example:" 
  echo "      $SCRIPT_NAME.sh"
  echo ""
  echo "###############################################################################"
  exit 1
}

#-------------------------------------------------------------- process_args --
process_args() {

  options=$@

  # An array with all the arguments
  args=($options)

  [[ $args == "--help" ]] && help && exit 1
  
  i=0
  V_JOB="cleanup"
  for arg in $options
  do
      if [[ ${args[$i]:0:1} == "-" && ${args[$i+1]:0:1} != "-" ]]
      then
          case ${args[$i]} in
             -t | --table )             V_TABLES=${args[$i+1]};;
             -b | --batchsize )         V_BATCHSIZE=${args[$i+1]};;
             -p | --parallel )          V_PARALLEL=${args[$i+1]};;
             -r | --rollback )          V_JOB="rollback";;
             *)                         echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      fi
  done

  [ -z $V_BATCHSIZE ] && V_BATCHSIZE=10000000
  [ -z $V_PARALLEL ] && V_PARALLEL=8
 
  IS_RO=`mysql -NB -e"select count(1) from information_schema.global_variables where variable_name = 'READ_ONLY' and variable_value = 'ON'"`
  [[ $IS_RO -eq 0 ]] && echo "`date \"+%Y-%m-%d %H:%M:%S\"` - [Error] Please enable READ_ONLY before running this script" && exit 1
  
  TABLE_LIST=('access_token' 'refresh_token' 'authentication_holder' 'token_scope' 'authentication_holder_request_parameter' 'authentication_holder_scope' 'saved_user_auth' 'saved_user_auth_authority')
 
  if [ ! -z $V_TABLES ] 
  then
      # Checking that there are no duplicates in input 
      [[ "`echo $V_TABLES | xargs -d',' -n1 |sort |xargs`" != "`echo $V_TABLES | xargs -d',' -n1 |sort -u |xargs`" ]] && echo "`date \"+%Y-%m-%d %H:%M:%S\"` - [Error] Duplicate vaule(s) found for -t|--tables option." && exit 1

      IFS=',' read -r -a INPUT_TABLES <<< $V_TABLES

      for TABLE in "${INPUT_TABLES[@]}"
      do
          if [[ "${TABLE_LIST[*]}" != *"$TABLE"* ]]
          then
              echo "`date \"+%Y-%m-%d %H:%M:%S\"` - [Error] One or more values for -t|--tables is not matching with pre-defined table list." && exit 1
          fi
      done
      TABLE_LIST=( "${INPUT_TABLES[@]}" )
  fi
  # Print warning on screen
  echo "[Warning] $V_JOB job will be executed against following tables:"
  echo
  for TBL in "${TABLE_LIST[@]}"
  do
      echo $TBL
  done
  echo
  echo "Do you want to continue (yes/no)?"
  read CONFIRM < /dev/tty
  [ "$CONFIRM" != "yes" ] && exit 1

}

func_cleanup() {

    TABLE="$1"
    MY_AUTH="mysql -vvv -A vault_oauth"

    echo "`date \"+%Y-%m-%d %H:%M:%S\"` - [Info] Cleanup started for : $TABLE" | tee -a $LOG_FILE
    echo "----------------------------------------------------------------------------------" | tee -a $LOG_FILE
    
    # DROP _old, _new tables and CREATE _new table
    $MY_AUTH -e"DROP TABLE IF EXISTS ${TABLE}_new; DROP TABLE IF EXISTS ${TABLE}_old; CREATE TABLE ${TABLE}_new LIKE ${TABLE};" | tee -a $LOG_FILE

    # INSERT INTO _new table
    case $TABLE in 
        access_token)
          $MY_AUTH -e"INSERT INTO ${TABLE}_new SELECT * FROM ${TABLE} WHERE expiration > now();" | tee -a $LOG_FILE
          [ $? -ne 0 ] && echo "`date \"+%Y-%m-%d %H:%M:%S\"` - [Error] Failed to INSERT to ${TABLE}_new" | tee -a $LOG_FILE
          ;;
        
        refresh_token)
          $MY_AUTH -e"INSERT INTO ${TABLE}_new SELECT * FROM ${TABLE} WHERE expiration > now();" | tee -a $LOG_FILE
          [ $? -ne 0 ] && echo "`date \"+%Y-%m-%d %H:%M:%S\"` - [Error] Failed to INSERT to ${TABLE}_new" | tee -a $LOG_FILE
          ;;    
        
        authentication_holder)
          $MY_AUTH -e"INSERT INTO ${TABLE}_new SELECT * FROM ${TABLE} WHERE id IN (SELECT auth_holder_id FROM access_token) OR id IN (SELECT auth_holder_id FROM refresh_token) OR id IN (SELECT auth_holder_id FROM authorization_code);" | tee -a $LOG_FILE
          [ $? -ne 0 ] && echo "`date \"+%Y-%m-%d %H:%M:%S\"` - [Error] Failed to INSERT to ${TABLE}_new" | tee -a $LOG_FILE
          ;;
        
        token_scope)
          $MY_AUTH -e"INSERT INTO ${TABLE}_new SELECT * FROM ${TABLE} WHERE owner_id IN (SELECT id FROM access_token);" | tee -a $LOG_FILE
          [ $? -ne 0 ] && echo "`date \"+%Y-%m-%d %H:%M:%S\"` - [Error] Failed to INSERT to ${TABLE}_new" | tee -a $LOG_FILE
          ;;
        
        authentication_holder_request_parameter)
          MIN_ID=`mysql -A vault_oauth -NB -e"SELECT MIN(id) FROM authentication_holder;"`
          MAX_ID=`mysql -A vault_oauth -NB -e"SELECT MAX(id) FROM authentication_holder;"`

          NUM=1
          while [ ${MAX_ID} -gt ${MIN_ID} ];
          do
              FILENUM=$(($NUM % $V_PARALLEL ))
              NEXT=$(( ${MIN_ID} + ${V_BATCHSIZE} ))
              [ $NEXT -eq $MAX_ID ] && NEXT=$(( $NEXT+1 ))
              echo "INSERT INTO ${TABLE}_new SELECT * FROM ${TABLE} WHERE owner_id IN (SELECT id FROM authentication_holder WHERE id >= $MIN_ID AND id < $NEXT);" >> /tmp/${SCRIPT_NAME}_${TABLE}_${FILENUM}.$$
              MIN_ID=$NEXT
              NUM=$(( $NUM+1 ))
          done
          for FILENAME in `ls /tmp |grep $SCRIPT_NAME |grep $TABLE | grep $$`
          do
              $MY_AUTH < /tmp/$FILENAME | tee -a $LOG_FILE &
              [ $? -ne 0 ] && echo "`date \"+%Y-%m-%d %H:%M:%S\"` - [Error] Failed to INSERT to ${TABLE}_new" | tee -a $LOG_FILE
          done

          # wait for all parallel threads to complete
          echo "`date \"+%Y-%m-%d %H:%M:%S\"` - Info] Waiting for all threads to complete..." | tee -a $LOG_FILE
          wait
          ;;
        
        authentication_holder_scope)
          $MY_AUTH -e"INSERT INTO ${TABLE}_new SELECT * FROM ${TABLE} WHERE owner_id IN (SELECT id FROM authentication_holder);" | tee -a $LOG_FILE
          [ $? -ne 0 ] && echo "`date \"+%Y-%m-%d %H:%M:%S\"` - [Error] Failed to INSERT to ${TABLE}_new" | tee -a $LOG_FILE
          ;;
        
        saved_user_auth)
          $MY_AUTH -e"INSERT INTO ${TABLE}_new SELECT * FROM ${TABLE} WHERE id IN (SELECT user_auth_id FROM authentication_holder);" | tee -a $LOG_FILE 
          [ $? -ne 0 ] && echo "`date \"+%Y-%m-%d %H:%M:%S\"` - [Error] Failed to INSERT to ${TABLE}_new" | tee -a $LOG_FILE
          ;;
        
        saved_user_auth_authority)
          $MY_AUTH -e"INSERT INTO ${TABLE}_new SELECT * FROM ${TABLE} WHERE owner_id IN (SELECT user_auth_id FROM authentication_holder);" | tee -a $LOG_FILE 
          [ $? -ne 0 ] && echo "`date \"+%Y-%m-%d %H:%M:%S\"` - [Error] Failed to INSERT to ${TABLE}_new" | tee -a $LOG_FILE
          ;;
    esac
            
    # table flip
    $MY_AUTH -e"RENAME TABLE ${TABLE} TO ${TABLE}_old; RENAME TABLE ${TABLE}_new TO ${TABLE};" | tee -a $LOG_FILE
    [ $? -ne 0 ] && echo "`date \"+%Y-%m-%d %H:%M:%S\"` - [Error] Failed to RENAME ${TABLE} to ${TABLE}_old and ${TABLE}_new to ${TABLE}" | tee -a $LOG_FILE

}

func_rollback() {

    TABLE="$1"
    MY_AUTH="mysql -vvv -A vault_oauth"
    MY_AUTH1="mysql -A vault_oauth"

    echo "`date \"+%Y-%m-%d %H:%M:%S\"` - [Info] Rollback started for : $TABLE" | tee -a $LOG_FILE
    echo "---------------------------------------------------------" | tee -a $LOG_FILE
    # table flip
    $MY_AUTH -e"RENAME TABLE ${TABLE} TO ${TABLE}_failed; RENAME TABLE ${TABLE}_old TO ${TABLE};" | tee -a $LOG_FILE
    [ $? -ne 0 ] && echo "`date \"+%Y-%m-%d %H:%M:%S\"` - [Error] Failed to RENAME ${TABLE} to ${TABLE}_failed and ${TABLE}_old to ${TABLE}" | tee -a $LOG_FILE

}

vault_cleanup() {

  # Looping through list of tables
  echo "`date \"+%Y-%m-%d %H:%M:%S\"` - [Info] ${V_JOB} started..." | tee -a $LOG_FILE 
  for TBL in "${TABLE_LIST[@]}"
  do
      func_${V_JOB} $TBL
  done
  echo "`date \"+%Y-%m-%d %H:%M:%S\"` - [Info] ${V_JOB} completed." | tee -a $LOG_FILE
}

#---------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  vault_cleanup
  return 0
}

main $*

