#!/bin/bash

###############################################################################
#
# Auther : Ashok Jivani
# Purpose: This script should be used match two slaves replication position if  
#          they both are slaving from the same master. 
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"
COMMON_FUNC_FILE="${SCRIPT_DIR}/common_functions.sh"

. ${PARAMETER_FILE}
. ${COMMON_FUNC_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`

CURRENT_DIR=`pwd`

HOST_FILE=/tmp/${SCRIPT_NAME}_$$_host
LOG_FILE=/tmp/${SCRIPT_NAME}_$$.log

#----------------------------------------------------------------------- help --
help(){
  echo "" 
  echo "This script should be used to match two sibling slave's  position if they are slaving from the same master."
  echo ""
  echo "Usage:"
  echo ""
  echo "sh $SCRIPT_NAME.sh < REQUIRED > [ OPTIONAL ]"
  echo ""
  echo "  Required:"
  echo "      -r  or --role             Database Role  (ie. mono, shard, ticket, monovp)"
  echo "      -a or --ahead             Ahead host info (ie, ckw.budb or ckw.mdb9,ckw.mdb10 or ckw.budb,ckw.fodb,ckw.fldb)"
  echo "      -b or --behind            Slave (ie, ckw.budb or ckw.mdb9,ckw.mdb10 or ckw.budb,ckw.fodb,ckw.fldb)"
  echo ""
  echo "  Optional:"
  echo "      -h  or --slave-hosts      List of Slave(s) (ie. fldb001.iad1,fldb002.iad1)"
  echo "      -g  or --groupname        GroupName (ie. darwindb, odditydb, fasdb)"
  echo "      -n  or --instance-number  Instance Number(s) (ie. 1,2 1-4,5)"
  echo ""
  echo "  Example:"
  echo "    Dry Run:"
  echo "      sh $SCRIPT_NAME.sh --role shard -a ckw.fodb -b cke.fldb -h fldb001.iad1 -n 1"
  echo ""
  echo "    Actual Execution:"
  echo "      sh $SCRIPT_NAME.sh --role shard -a ckw.fodb -b cke.fldb -h fldb001.iad1 -n 1 --execute"
  echo ""
  exit 1
}

#--------------------------------------------------------------- process_args --
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
             -r | --role )             V_ROLE=${args[$i+1]};;    
             -g | --group )            V_GROUP=${args[$i+1]};;
             -a | --ahead )            V_AHEAD=${args[$i+1]};;
             -b | --behind )           V_BEHIND=${args[$i+1]};;
             -h | --slave-hosts )      V_BEHIND_HOSTS=${args[$i+1]};;
             -n | --instance-number )  V_INSTANCE_NUMBER=${args[$i+1]};;
             *)                        echo "Invalid option '${args[$i]}'" && exit 1;;
        esac
        i=$(($i+2))
     fi
  done

  [ -z "${V_ROLE}" ] && echo "[Error] - Please specify 'Role' for -r or --role option. See --help for help" && exit 1
  [ -z "${V_AHEAD}" ] && echo "[Error] - Please specify 'AHEAD' for -a option. See --help for help" && exit 1
  [ -z "${V_BEHIND}" ] && echo "[Error] - Please specify 'BEHIND' for -b option. See --help for help" && exit 1
  [ "${V_ROLE}" == "monovp" ] && [ -z "${V_GROUP}" ] && echo "[Error] - Please specify 'GroupName' for -g option. See --help for help" && exit 1

  RANGE=""

  if [[ "${V_ROLE}" == "shard" ]] 
  then
     A_FILTER=`echo $V_AHEAD | sed "s/,/'), ('/g" |sed "s/\./', '/g"`
     B_FILTER=`echo $V_BEHIND | sed "s/,/'), ('/g" |sed "s/\./', '/g"`
     RANGE="and (a.datacenter, a.groupname) in (('$A_FILTER'))"
     RANGE="$RANGE and (b.datacenter, b.groupname) in (('$B_FILTER'))"
     [ ! -z "${V_BEHIND_HOSTS}" ] && B_HOSTS=`echo $V_BEHIND_HOSTS | sed "s/,/','/g"` && RANGE="$RANGE and b.hostname in ('$B_HOSTS')"
     [ ! -z "${V_INSTANCE_NUMBER}" ] && RANGE="$RANGE and b.shardNumber in (`echo $V_INSTANCE_NUMBER | awk 'BEGIN { RS=","; FS="-"; ORS="" } NR > 1 { print "," } NF > 1  { for (i=$1; i<$2; ++i) { print i "," } print $2; next } { print $1 }'`)"

     mysql -NB -e"select concat(b.hostName, \":\", b.ipAddress, \":\", b.port, \":\", b.fqdn, \":\", a.hostName, \":\", a.ipAddress, \":\", a.port, \":\", a.fqdn) from $ADMIN_SCHEMA.$ADMIN_TABLE a, $ADMIN_SCHEMA.$ADMIN_TABLE b where a.shardNumber = b.shardNumber and a.role='$V_ROLE' and b.role='$V_ROLE' $RANGE" 2>/dev/null > $HOST_FILE  

     [ $? -ne 0 ] && echo "[Error] - Error occurred during executing query against '$ADMIN_SCHEMA.$ADMIN_TABLE'" && exit 1    
  else
     B_FILTER=`echo $V_BEHIND | sed "s/,/','/g"`
     RANGE=" and (b.hostname) in ('$B_FILTER')"
     
     [ ! -z "${V_GROUP}" ] && RANGE="$RANGE and a.groupname = '$V_GROUP' and b.groupname = '$V_GROUP'"

     mysql -NB -e"select concat(b.hostName, \":\", b.ipAddress, \":\", b.port, \":\", b.fqdn, \":\", a.hostName, \":\", a.ipAddress, \":\", a.port, \":\", a.fqdn) from $ADMIN_SCHEMA.$ADMIN_TABLE a, $ADMIN_SCHEMA.$ADMIN_TABLE b where a.hostName = '$V_AHEAD' and a.role='$V_ROLE' and b.role='$V_ROLE' $RANGE" 2>/dev/null > $HOST_FILE
         
     [ $? -ne 0 ] && echo "[Error] - Error occurred during executing query against '$ADMIN_SCHEMA.$ADMIN_TABLE'" && exit 1
  fi
  [ ! -s $HOST_FILE ] && echo "[Error] - Please specify correct Input parameters. See --help for help." && exit 1
}

#--------------------------------------------------------- func_change_master --
func_match_siblings()
{
  B_HOST=`echo $1 | cut -d":" -f1`
  B_IP=`echo $1 | cut -d":" -f2`
  B_PORT=`echo $1 | cut -d":" -f3`
  B_FQDN=`echo $1 | cut -d":" -f4`
  A_HOST=`echo $1 | cut -d":" -f5`
  A_IP=`echo $1 | cut -d":" -f6`
  A_PORT=`echo $1 | cut -d":" -f7`
  A_FQDN=`echo $1 | cut -d":" -f8`

  TMP_FILE_A=/tmp/${SCRIPT_NAME}_tmpa_${A_IP}_${A_PORT}.$$
  TMP_FILE_B=/tmp/${SCRIPT_NAME}_tmpb_${B_IP}_${B_PORT}.$$
  TMP_FILE=/tmp/${SCRIPT_NAME}_tmp_${A_IP}_${A_PORT}.$$
  
  # checking if GTID is not enabled.
  GTID=`mysql -u$USER -p$PASSWD -h$B_IP -P$B_PORT -NB -e"select count(1) from (select @@global.gtid_mode='ON' as gtid) a where a.gtid=1;" 2>/dev/null`
  [ $? -ne 0 ] && echo "[Error] - Error occurred during executing check if GTID is enabled or not '$B_HOST:$B_PORT'" > $TMP_FILE && break
  if [ $GTID -ne 1 ]
  then
      # checking if AHEAD and BEHIND slaves are slaving from same master.
      MASTER_OF_A=`mysql -u$USER -p$PASSWD -h$A_IP -P$A_PORT -e"SHOW SLAVE STATUS\G" 2>/dev/null | grep "Master_UUID" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      [ $? -ne 0 ] && echo "Error occurred during executing 'SHOW SLAVE STATUS' on '$A_HOST:$A_PORT'" > $TMP_FILE && break 

      MASTER_OF_B=`mysql -u$USER -p$PASSWD -h$B_IP -P$B_PORT -e"SHOW SLAVE STATUS\G" 2>/dev/null | grep "Master_UUID" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      [ $? -ne 0 ] && echo "[Error] - Error occurred during executing 'SHOW SLAVE STATUS' on '$B_HOST:$B_PORT'" > $TMP_FILE && break 
     
      if [[ $MASTER_OF_A == $MASTER_OF_B ]]
      then
          # stop slave on BEHIND.
          mysql -vvv -u$USER -p$PASSWD -h$B_IP -P$B_PORT -e"STOP SLAVE;" 2>/dev/null > /tmp/23
          [ $? -ne 0 ] && echo "[Error] - Error occurred during executing 'STOP SLAVE' on '$B_HOST:$B_PORT'" > $TMP_FILE && break
          
          # Wait for 5 seconds"
          sleep 3

          # stop slave on AHEAD.
          mysql -u$USER -p$PASSWD -h$A_IP -P$A_PORT -e"STOP SLAVE;" 2>/dev/null
          [ $? -ne 0 ] && echo "[Error] - Error occurred during executing 'STOP SLAVE' on '$A_HOST:$A_PORT'" > $TMP_FILE && break 
     
          # Check if BEHIND is really behind.
          mysql -u$USER -p$PASSWD -h$A_IP -P$A_PORT -e"SHOW SLAVE STATUS\G" 2>/dev/null > $TMP_FILE_A
          [ $? -ne 0 ] && echo "[Error] - Error occurred during executing 'SHOW SLAVE STATUS' on '$A_HOST:$A_PORT'" > $TMP_FILE && break
          A_FILE=`cat $TMP_FILE_A | grep "Relay_Master_Log_File" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
          A_POS=`cat $TMP_FILE_A  | grep "Exec_Master_Log_Pos" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`

          mysql -u$USER -p$PASSWD -h$B_IP -P$B_PORT -e"SHOW SLAVE STATUS\G" 2>/dev/null > $TMP_FILE_B
          [ $? -ne 0 ] && echo "[Error] - Error occurred during executing 'SHOW SLAVE STATUS' on '$B_HOST:$B_PORT'" > $TMP_FILE && break
          B_FILE=`cat $TMP_FILE_B | grep "Relay_Master_Log_File" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
          B_POS=`cat $TMP_FILE_B  | grep "Exec_Master_Log_Pos" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
         
          if [[ `echo ${A_FILE}_${A_POS} | sed 's/\.//'` > `echo ${B_FILE}_${B_POS} |sed 's/\.//'` ]]
          then
              # start slave until on BEHIND
              mysql -u$USER -p$PASSWD -h$B_IP -P$B_PORT -e"START SLAVE UNTIL MASTER_LOG_FILE='$A_FILE', MASTER_LOG_POS=$A_POS;"  2>/dev/null
              [ $? -ne 0 ] && echo "[Error] - Error occurred during executing 'START SLAVE UNTIL' on '$B_HOST:$B_PORT'" > $TMP_FILE && break
              
              # sleep 
              sleep 5
             
              # Confirm if positions of A and B are matching.
              mysql -u$USER -p$PASSWD -h$A_IP -P$A_PORT -e"SHOW SLAVE STATUS\G" 2>/dev/null > $TMP_FILE_A
              [ $? -ne 0 ] && echo "[Error] - Error occurred during executing 'SHOW SLAVE STATUS' on '$A_HOST:$A_PORT'" > $TMP_FILE && break
              A_FILE=`cat $TMP_FILE_A | grep "Relay_Master_Log_File" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
              A_POS=`cat $TMP_FILE_A  | grep "Exec_Master_Log_Pos" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`

              mysql -u$USER -p$PASSWD -h$B_IP -P$B_PORT -e"SHOW SLAVE STATUS\G" 2>/dev/null > $TMP_FILE_B
              [ $? -ne 0 ] && echo "[Error] - Error occurred during executing 'SHOW SLAVE STATUS' on '$B_HOST:$B_PORT'" > $TMP_FILE && break
              B_FILE=`cat $TMP_FILE_B | grep "Relay_Master_Log_File" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
              B_POS=`cat $TMP_FILE_B  | grep "Exec_Master_Log_Pos" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
              if [[ `echo ${A_FILE}_${A_POS} | sed 's/\.//'` == `echo ${B_FILE}_${B_POS} |sed 's/\.//'` ]] 
              then
                  echo "[Info] - Positions matching between '$A_HOST:$A_PORT' and '$B_HOST:$B_PORT'" > $TMP_FILE 
              else
                  echo "[Warning] - Please check slave positions between '$A_HOST:$A_PORT' and '$B_HOST:$B_PORT'" > $TMP_FILE
              fi
          else
              echo "[Error] - Looks like '$B_HOST:$B_PORT' position is ahead then '$A_HOST:$A_PORT'" > $TMP_FILE && break
          fi
      else
          echo "[Error] - Looks like '$A_HOST:$A_PORT' and '$B_HOST:$B_PORT' are slaving from different masters." > $TMP_FILE && break
      fi
  else
      echo "[Error] - GTID is enabled on '$A_HOST:$A_PORT' and '$B_HOST:$B_PORT'." > $TMP_FILE && break
  fi

  return 0
}

#--------------------------------------------------------------- change_master --
match_siblings() {

  echo "This script will be executed on following servers:"
  echo ""
  echo " -----------------------------------------------------"
  echo "|         Slave_A           |         Slave_B         |"
  echo " -----------------------------------------------------"
  while read LINE
  do
      echo $LINE | awk -F':' '{ printf "| %19s:%s | %19s:%s |\n", $5, $7, $1, $3}'
  done < $HOST_FILE
  echo " -----------------------------------------------------"
  echo ""
  echo "Do you want to continue (yes/no)?"
  read CONFIRM < /dev/tty
  [ "$CONFIRM" != "yes" ] && echo "Exiting" && rm -f $HOST_FILE /tmp/${SCRIPT_NAME}_tmp* && exit 1
 
  # notify mysql-change-log slack channel
  mysql_change_log "$SCRIPT_NAME.sh $options"

  while read LINE
  do
      func_match_siblings $LINE &   
  done < $HOST_FILE
  wait

  while read LINE
  do
      A_IP=`echo $LINE | cut -d":" -f6`
      A_PORT=`echo $LINE | cut -d":" -f7`
      THIS_TMP=/tmp/${SCRIPT_NAME}_tmp_${A_IP}_${A_PORT}.$$ 
      [ -f $THIS_TMP ] && cat $THIS_TMP >> $LOG_FILE
      rm -f $THIS_TMP
  done < $HOST_FILE
  
  echo ""
  cat $LOG_FILE

  rm -f $HOST_FILE /tmp/${SCRIPT_NAME}_tmp* 
}
#----------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  match_siblings
  return 0
}

main $*
