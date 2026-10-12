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
# Purpose: This script should be used to check SLAVE_LAG for given database 
#          servers. 
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
HOST_FILE=/tmp/${SCRIPT_NAME}_hostfile.$$
RESULT_FILE=/tmp/${SCRIPT_NAME}_resultfile.$$

# colors
RED=`tput setaf 1`
NOCOLOR='\e[0m'

#---------------------------------------------------------------------- help --
help(){
  echo '''
  This script should be used to check SLAVE_LAG for given database servers.
  
  Usage:
  
  sh $SCRIPT_NAME.sh -d <DATA_CENTER> -g <GROUP> [ -n <INSTANCE_NUMBER> -e <EXTENDED> -h <HOSTNAME> -a ]
  
    Required:
        -d | --data-center       Data Center code (ie. ckw, cke)
        -g | --group             Group (ie. fldb, fodb, budb, mono, tkdb, ipdb)
  
    Optional:
        -n | --instance-number   Instance Number (ie 1,2,..16)
        -h | --hostname          Hostname (ie mdb10.sjc1,mdb11.sjc1)
        -e | --extended          Extended. This mode will display master positions for each slave. (ie 1)
        -c | --compact           Show only list of slave which are not caught up. Default disabled. (ie 1)
  
    Example:
  
        sh $SCRIPT_NAME.sh -d ckw -g fldb -n 2 -e
        sh $SCRIPT_NAME.sh -d ckw,rs -g mono -h mdb10.sjc1
  '''
}

#-------------------------------------------------------------- process_args --
process_args() {

  options=$@

  # An array with all the arguments
  args=($options)

  [[ $args == "--help" || $args == "" ]] && help && exit 1
  
  V_EXTENDED="Y"
  i=0
  for arg in $options
  do
      if [[ ${args[$i]:0:1} == "-" && ${args[$i+1]:0:1} != "-" ]]
      then
          case ${args[$i]} in
             -d | --data-center )       V_DATA_CENTER=${args[$i+1]};;
             -g | --group )             V_GROUP=${args[$i+1]};;
             -n | --instance-number )   V_INSTANCE_NUMBER=${args[$i+1]};;
             -h | --hostname )          V_HOSTNAME=${args[$i+1]};;
             -e | --extended )          V_EXTENDED="Y";; 
             -c | --compact )           V_COMPACT="Y" && V_EXTENDED="Y";; 
             *)                         echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      else
          case ${args[$i]} in
             -e | --extended )          V_EXTENDED="Y";;
             -c | --compact )           V_COMPACT="Y";; 
          esac    
          i=$(($i+1))
      fi
  done

  [ -z "${V_DATA_CENTER}" ] && echo "Please specify 'Data Center' for -d option." && help
  [ -z "${V_GROUP}" ] && echo "Please specify 'Shard Group' for -g option" && help

  RANGE=""
  [ ! -z "${V_DATA_CENTER}" ] && DCENTERS=`echo $V_DATA_CENTER | sed "s/,/','/g"` && RANGE="where dataCenter in ('$DCENTERS')"
  [ ! -z "${V_GROUP}" ] && GRPS=`echo $V_GROUP | sed "s/,/','/g"` && RANGE="$RANGE and groupName in ('$GRPS')"
  [ ! -z "${V_INSTANCE_NUMBER}" ] && RANGE="$RANGE and shardNumber in (`echo $V_INSTANCE_NUMBER | awk 'BEGIN { RS=","; FS="-"; ORS="" } NR > 1 { print "," } NF > 1  { for (i=$1; i<$2; ++i) { print i "," } print $2; next } { print $1 }'`)"
  [ ! -z "${V_HOSTNAME}" ] && HOSTS=`echo $V_HOSTNAME | sed "s/,/','/g"` && RANGE="$RANGE and hostname in ('$HOSTS')"

  mysql -NB -e"select concat(fqdn, \":\", port) from $ADMIN_SCHEMA.$ADMIN_TABLE $RANGE" 2>/dev/null  > $HOST_FILE
  [ ! -s $HOST_FILE ] && echo "Please check if 'Data Center' and/or 'Shard Group' is valid." && exit 1

  return 0
}

#----------------------------------------------------------- check_slave_lag --
check_slave_lag() {
 
  QRY="show slave status\G"
  S_FQDN=`echo $1 | cut -d":" -f1`
  S_PORT=`echo $1 | cut -d":" -f2`
  TMP_FILE=/tmp/${SCRIPT_NAME}_tmp_${S_FQDN}_${S_PORT}.$$
  
  SLAVE_STATUS=`mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"$QRY" 2>/dev/null`
  if [ $? -ne 0 ] 
  then
      printf "${RED}Host  : %32s:%s - Error occurred during fetching SLAVE STATUS.${NOCOLOR}\n" "$S_FQDN" "$S_PORT" > $TMP_FILE
      EXTENDED="N"
  else
      S_LAG=`echo "$SLAVE_STATUS" | grep "Seconds_Behind_Master" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      S_FILE=`echo "$SLAVE_STATUS" | grep "Relay_Master_Log_File" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      S_POS=`echo "$SLAVE_STATUS" | grep "Exec_Master_Log_Pos" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      M_FQDN=`echo "$SLAVE_STATUS" | grep "Master_Host" |cut -d":" -f2 | sed -e 's/^ *//' -e 's/ *$//'`
      M_PORT=`echo "$SLAVE_STATUS" | grep "Master_Port" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      
      RD=${RED}
      [ "$LAG" != "NULL" ] && RD=""
  fi

  if [ "$M_FQDN" == "" ] 
  then
      printf "Host   : %32s:%s Lag: ${RD}%-5s${NOCOLOR} - %30s : %10s\n" "$S_FQDN" "$S_PORT" "$S_LAG" "$S_FILE" "$S_POS" > $TMP_FILE
      [ "${V_EXTENDED}" == "Y" ] && printf "Not a Slave.\n" >> $TMP_FILE
      printf "\n" >> $TMP_FILE
  else
      MASTER_STATUS=`mysql -u$USER -p$PASSWD -h$M_FQDN -P$M_PORT -e"show master status\G" 2>/dev/null`
      if [ $? -ne 0 ]
      then
          printf "Host   : %32s:%s Lag: ${RD}%-5s${NOCOLOR}  - %30s : %10s\n" "$S_FQDN" "$S_PORT" "$S_LAG" "$S_FILE" "$S_POS" > $TMP_FILE
          [ "${V_EXTENDED}" == "Y" ] && printf "${RED}Master : Error occurred during fetching MASTER STATUS.${NOCOLOR}\n" >> $TMP_FILE
          printf "\n" >> $TMP_FILE
      else
          M_FILE=`echo "$MASTER_STATUS" | grep "File:" | cut -d":" -f2| sed -e 's/^ *//' -e 's/ *$//'`
          M_POS=`echo "$MASTER_STATUS" | grep "Position:" | cut -d":" -f2| sed -e 's/^ *//' -e 's/ *$//'`
          if ! [[ "${V_COMPACT}" == "Y" && $S_LAG -eq 0 && "${M_FILE}" == "${S_FILE}" && $(( S_POS+300000 )) -ge $M_POS ]]
          then
              printf "Host   : %32s:%s Lag: ${RD}%-5s${NOCOLOR}  - %30s : %10s\n" "$S_FQDN" "$S_PORT" "$S_LAG" "$S_FILE" "$S_POS" > $TMP_FILE
              if [ "${V_EXTENDED}" == "Y" ]
              then
                  printf "Master : %32s:%s             - %30s : %10s\n" "$M_FQDN" "$M_PORT" "$M_FILE" "$M_POS" >> $TMP_FILE 
                  printf "\n" >> $TMP_FILE
              fi 
          fi
      fi
  fi    
}

#-------------------------------------------------------------- iterate_list --
iterate_list() {

  while read LINE
  do
      check_slave_lag $LINE &
  done < $HOST_FILE
  wait

  while read LINE
  do
  	  FQDN=`echo $LINE | cut -d":" -f1`
  	  PORT=`echo $LINE | cut -d":" -f2`
  	  [ -f /tmp/${SCRIPT_NAME}_tmp_${FQDN}_${PORT}.$$ ] && cat /tmp/${SCRIPT_NAME}_tmp_${FQDN}_${PORT}.$$ >> $RESULT_FILE
  done < $HOST_FILE

  # Display result
  [ -f $RESULT_FILE ] && cat $RESULT_FILE
  rm -f /tmp/${SCRIPT_NAME}_tmp* $HOST_FILE $RESULT_FILE

  return 0
}

#---------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  iterate_list
  return 0
}

main $*
