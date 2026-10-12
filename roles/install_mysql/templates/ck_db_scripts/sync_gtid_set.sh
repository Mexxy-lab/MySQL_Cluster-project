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
# Purpose: This script should be used to sync GTID_EXECUTED set on slave(s) 
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"
COMMON_FUNC_FILE="${SCRIPT_DIR}/common_functions.sh"

. ${PARAMETER_FILE}
. ${COMMON_FUNC_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
HOST_FILE=/tmp/${SCRIPT_NAME}_hostfile.$$
RESULT_FILE=/tmp/${SCRIPT_NAME}_resultfile.$$

# colors
RED=`tput setaf 1`
NOCOLOR='\e[0m'

#---------------------------------------------------------------------- help --
help(){
  echo '''
  This script should be used to sync GTID_SET on slave(s).
  
  Usage:
  
  sh $SCRIPT_NAME.sh -d <DATA_CENTER> -g <GROUP> [ -n <INSTANCE_NUMBER> -h <HOSTNAME> --execute ]

    Required:
        -d | --data-center       Data Center code (ie. ckw, cke)
        -g | --group             Group (ie. fldb, fodb, budb, mono, tkdb, ipdb)

    Optional:
        -n | --instance-number   Instance Number (ie 1,2,..16)
        -h | --hostname          Hostname (ie mdb10.sjc1,mdb11.sjc1)
        -e | --extended          Extended output. Default disabled.
        --execute                In order to execute GTID_PURGED on slaves. Default disabled.

    Example:
    
       DRY-RUN: 
          sh $SCRIPT_NAME.sh -d ckw -g budb -n 2
    
       EXECUTE:
          sh $SCRIPT_NAME.sh -d ckw -g fldb -n 2 --execute
  '''
}

#-------------------------------------------------------------- process_args --
process_args() {

  options=$@

  # An array with all the arguments
  args=($options)

  [[ $args == "--help" || $args == "" ]] && help && exit 1
  
  V_EXECUTE="N"
  V_EXTENDED="N"
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
             --execute )                V_EXECUTE="Y";; 
             *)                         echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      else
          case ${args[$i]} in
             -e | --extended )          V_EXTENDED="Y";;
             -c | --compact )           V_COMPACT="Y";; 
             -e | --extended )          V_EXTENDED="Y";;
             --execute )                V_EXECUTE="Y";; 
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

  mysql -NB -e"select concat(hostName, \":\", fqdn, \":\", port) from $ADMIN_SCHEMA.$ADMIN_TABLE $RANGE" > $HOST_FILE
  [ ! -s $HOST_FILE ] && echo "Please check if 'Data Center' and/or 'Shard Group' is valid." && exit 1

  return 0
}

#----------------------------------------------------------- check_slave_lag --
sync_gtid_executed() {
 
  S_HOST=`echo $1 | cut -d":" -f1`
  S_FQDN=`echo $1 | cut -d":" -f2`
  S_PORT=`echo $1 | cut -d":" -f3`
  TMP_FILE=/tmp/${SCRIPT_NAME}_tmp_${S_FQDN}_${S_PORT}.$$
  TMP_FILE2=/tmp/${SCRIPT_NAME}_tmp2_${S_FQDN}_${S_PORT}.$$
  
  IS_INTERMEDIATE_MASTER=$(mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -NB -e"SHOW SLAVE HOSTS" 2>/dev/null | wc -l)
  [ $? -ne 0 ] && echo "Error occured during executing 'SHOW SLAVE HOSTS' on '$S_HOST:$S_PORT" && exit 1 
  
  [[ $IS_INTERMEDIATE_MASTER -gt 0  && "$V_EXECUTE" == "Y" ]] && echo "Looks like '$S_HOST($S_PORT)' has some slaves underneath. Please relocate its slaves and re-run the script." > $TMP_FILE && exit 1

  if [[ "$V_EXECUTE" == "Y" ]]
  then 	
      # STOP SLAVE on Slave.
      mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"STOP SLAVE;" 2>/dev/null 
      [ $? -ne 0 ] && echo "Error occured during executing 'STOP SLAVE' on '$S_HOST:$S_PORT" > $TMP_FILE && exit 1 
  fi

  SLAVE_STATUS=`mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"SHOW SLAVE STATUS\G" 2>/dev/null`
  [ $? -ne 0 ] && echo "Error occured during executing 'SHOW SLAVE STATUS' on '$S_HOST:$S_PORT" > $TMP_FILE && exit 1 

  M_FQDN=$(echo "$SLAVE_STATUS" | grep "Master_Host" |cut -d":" -f2 | sed -e 's/^ *//' -e 's/ *$//')
  M_PORT=$(echo "$SLAVE_STATUS" | grep "Master_Port" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//')

  S_GTID_EXECUTED=$(mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -NB -e"select @@global.gtid_executed;" 2>/dev/null | sed 's/\\n//g')
  [ $? -ne 0 ] && echo "Error occured during executing 'SELECT GTID_EXECUTED' on '$S_HOST:$S_PORT" > $TMP_FILE && exit 1 
  M_GTID_EXECUTED=$(mysql -u$USER -p$PASSWD -h$M_FQDN -P$M_PORT -NB -e"select @@global.gtid_executed;" 2>/dev/null | sed 's/\\n//g')
  [ $? -ne 0 ] && echo "Error occured during executing 'SELECT GTID_EXECUTEDT' on '$M_HOST:$M_PORT" > $TMP_FILE && exit 1 

  SUBSET=`mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -NB -e"select gtid_subset('$S_GTID_EXECUTED', '$M_GTID_EXECUTED')" 2>/dev/null`
  [ $? -ne 0 ] && echo "Error occured during executing 'GTID_SUBSET' on '$S_HOST:$S_PORT" > $TMP_FILE && exit 1 

  echo "$M_HOST:$M_PORT :  $M_GTID_EXECUTED" > $TMP_FILE
  echo "$S_HOST:$S_PORT :  $S_GTID_EXECUTED" >> $TMP_FILE
  
  if [[ $SUBSET -eq 0 ]]
  then	
      SUBTRACT=$(mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -NB -e"select gtid_subtract('$S_GTID_EXECUTED', '$M_GTID_EXECUTED')" 2>/dev/null | sed 's/\\n//g')
      [ $? -ne 0 ] && echo "Error occured during executing 'GTID_SUBTRACT' on '$S_HOST:$S_PORT" > $TMP_FILE && exit 1 

      IFS=',' read -r -a MASTER_SET <<< "$M_GTID_EXECUTED"
        IFS=',' read -r -a SLAVE_SET <<< "$S_GTID_EXECUTED"
        IFS=',' read -r -a ERRANT_SET <<< "$SUBTRACT"
      
        PURGE_SET=""
        for i in "${!SLAVE_SET[@]}"
        do
            match_count=0
            for j in "${!ERRANT_SET[@]}"
            do
                # Matching uuid between Slave and Errant Set.
                if [[ "`echo ${SLAVE_SET[i]} | cut -d ':' -f1`" == "`echo ${ERRANT_SET[j]} | cut -d ':' -f1`" ]] 
                then
                  # Matching transactions between Slave and Errant Set.
                  if [[ "`echo ${SLAVE_SET[i]} | cut -d ':' -f2`" == "`echo ${ERRANT_SET[j]} | cut -d ':' -f2`" ]]
                  then
                      match_count=1
                      break
                  else
                      # Since transactions not matching, getting gtid_set from its Master.
                      for k in "${!MASTER_SET[@]}"
                      do
                          if [[ "`echo ${SLAVE_SET[i]} | cut -d ':' -f1`" == "`echo ${MASTER_SET[k]} | cut -d ':' -f1`" ]]
                          then
                            PURGE_SET="$PURGE_SET,${MASTER_SET[k]}"
                            match_count=1
                            break
                          fi    
                      done  
                  fi
                else
                  match_count=0
                fi
            done
            [[ $match_count -eq 0 ]] && PURGE_SET="$PURGE_SET,${SLAVE_SET[i]}" 
        done
      
        PURGE_SET=$(echo $PURGE_SET |sed "s/^,//")
        
        echo "Errant_Set        :  $SUBTRACT" >> $TMP_FILE
        echo "---------------------------------------------------------------" >> $TMP_FILE

        [[ "$V_EXTENDED" == "N" ]] && printf "${RED}Errant Transactions found on '$S_HOST:$S_PORT'${NOCOLOR}\n" > $TMP_FILE

        if [[ $PURGE_SET != "" && "$V_EXECUTE" == "Y" ]]
        then
          # RESET MASTER on Slave.
          mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"RESET MASTER;" 2>/dev/null 
         [ $? -ne 0 ] && echo "Error occured during executing 'RESET MASTER' on '$S_HOST:$S_PORT" > $TMP_FILE && exit 1 
   
         # Set GTID_PURGED on Slave.
         mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"SET GLOBAL GTID_PURGED='$PURGE_SET';" 2>/dev/null
         [ $? -ne 0 ] && echo "Error occured during executing 'RESET MASTER' on '$S_HOST:$S_PORT" > $TMP_FILE && exit 1 
      fi
  else
      cat /dev/null > $TMP_FILE    
  fi

  if [[ "$V_EXECUTE" == "Y" ]]
  then
     # START SLAVE on Slave.
     mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"START SLAVE;" 2>/dev/null
     [ $? -ne 0 ] && echo "Error occured during executing 'START SLAVE' on '$S_HOST:$S_PORT" > $TMP_FILE && exit 1
  fi
}

#-------------------------------------------------------------- iterate_list --
iterate_list() {

  if [[ "$V_EXECUTE" == "Y" ]]
  then
     # notify mysql-change-log slack channel
     mysql_change_log "$SCRIPT_NAME.sh $options"
  fi
  while read LINE
  do
      sync_gtid_executed $LINE &
  done < $HOST_FILE
  wait

  while read LINE
  do
  	  FQDN=`echo $LINE | cut -d":" -f2`
  	  PORT=`echo $LINE | cut -d":" -f3`
  	  [ -f /tmp/${SCRIPT_NAME}_tmp_${FQDN}_${PORT}.$$ ] && cat /tmp/${SCRIPT_NAME}_tmp_${FQDN}_${PORT}.$$ >> $RESULT_FILE
  done < $HOST_FILE

  # Display results
  [ -f $RESULT_FILE ] && cat $RESULT_FILE
  [[ ! -s $RESULT_FILE ]] && echo "No Errant Transactions found on listed slave(s)."
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
