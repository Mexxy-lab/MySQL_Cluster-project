#!/bin/bash
# =============================================================================
# {% for line in fileBanner %}
# {{line}} {% endfor %}
# =============================================================================

###############################################################################
#
# Auther : Ashok Jivani
# Purpose: This script should be used to perform Multi-Source replication. 
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

BASE_DIR=`dirname 0`
PARAMETER_FILE="${BASE_DIR}/parameter.txt"

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`

AARORA="xxx@tmomail.net"
AJIVANI="xxx@tmomail.net"

help(){
  echo "" 
  echo "This script should be used to perform Multi-Source replication.."
  echo ""
  echo "Usage:"
  echo ""
  echo "sh $SCRIPT_NAME.sh < REQUIRED > [ OPTIONAL ]"
  echo ""
  echo "  Required:"
  echo "      --group    MySQL Group (ie. mono, shard, ticket)"
  echo ""
  echo "  Optional:"
  echo "      --master-host       Master (ie, fodb9.sjc1)"
  echo "      --slave-host        Slave (ie. fodb1.sjc1)"
  echo "      --slave-port        Slave Port (ie. 3301)"
  echo "      --rotation          Rotation in secondst (ie. 180, 300)"
  echo ""
  echo "  Example:  To make fodb1.sjc1 a slave of fodb9.sjc1 execute"
  echo ""
  echo "      sh $SCRIPT_NAME.sh --master-host fodb9.sjc1 --slave-host fodb1.sjc1 --slave-port 3301 --rotation 300"
  echo ""
  exit 1
}

#-------------------------------------------------------------- process_args --
process_args() {
 options=$@

# An array with all the arguments
args=($options)

[[ $args == "--help" || $args == "" ]] && help && exit 1

for arg in $options
do
    if [[ ${args[$i]} == "-"* || ${args[$i]} == "--"* ]] && [[ ${args[$i+1]} != "-"* || ${args[$i+1]} != "--"* ]] 
    then
          case ${args[$i]} in
             -m | --master-host )     V_MASTER_HOST=${args[$i+1]};;
             -mp | --master-port )    V_MASTER_PORT=${args[$i+1]};;
             -s | --slave-host )      V_SLAVE_HOST=${args[$i+1]};;
             -sp | --slave-port )     V_SLAVE_PORT=${args[$i+1]};;
             -r | --rotation )        V_SLAVE_PORT=${args[$i+1]};; 
             *)                       echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
      fi
      i=$(($i+2))
  done
  
  [ -z "${V_MASTER_HOST}" ] && echo "Please specify 'Master Hostname' for --master-host option. See --help for help" && exit 1
  [ -z "${V_SLAVE_HOST}" ] && echo "Please specify 'Slave Hostname' for --slave-host option. See --help for help" && exit 1
  [ -z "${V_SLAVE_PORT}" ] && echo "Please specify 'Slave Port' for --slave-port option. See --help for help" && exit 1
  [ -z "${V_ROTATION}" ] && V_ROTATION=300 

  SLAVE_LOG_DIR=/root/${V_MASTER_HOST}_to_${V_SLAVE_HOST}_${V_SLAVE_PORT}
  mkdir -p $SLAVE_LOG_DIR
  HOST_FILE=${SLAVE_LOG_DIR}/hostfile_${SCRIPT_NAME}.$$
  TMP_FILE=${SLAVE_LOG_DIR}/tmpfile_${SCRIPT_NAME}.$$
  TMP_FILE2=${SLAVE_LOG_DIR}/tmpfile2_${SCRIPT_NAME}.$$

  RANGE=""
  [ ! -z "${V_MASTER_PORT}" ] && RANGE="and m.port in (`echo $V_MASTER_PORT | awk 'BEGIN { RS=","; FS="-"; ORS="" } NR > 1 { print "," } NF > 1  { for (i=$1; i<$2; ++i) { print i "," } print $2; next } { print $1 }'`)"

  mysql -NB -e"select concat(s.hostname, \":\", s.ipAddress, \":\", s.port, \":\", m.hostName, \":\", m.ipaddress, \":\", m.port ) from $ADMIN_SCHEMA.$ADMIN_TABLE m, $ADMIN_SCHEMA.$ADMIN_TABLE s where m.hostName = '$V_MASTER_HOST' and s.hostName = '$V_SLAVE_HOST' and s.port='$V_SLAVE_PORT' $RANGE" > $HOST_FILE

  [ $? -ne 0 ] && echo "Error occurred during executing query against '$ADMIN_SCHEMA.$ADMIN_TABLE'" && exit 1    
     
  [ ! -s $HOST_FILE ] && echo "Please specify correct Input parameters. See --help for help." && exit 1
}

display_move(){
  
if [ -s $HOST_FILE ] 
  then
      echo ""
      echo " ---------------------------------------------------------------------------------------"
      echo "|                 SLAVE                      |                    MASTER                |"
      echo " ---------------------------------------------------------------------------------------"
      while read LINE
      do
          S_HOSTNAME=`echo $LINE | cut -d":" -f1`
          S_IPADDR=`echo $LINE | cut -d":" -f2`
          S_PORT=`echo $LINE | cut -d":" -f3`
          M_HOSTNAME=`echo $LINE | cut -d":" -f4`
          M_IPADDR=`echo $LINE | cut -d":" -f5`
          M_PORT=`echo $LINE | cut -d":" -f6` 

          printf "| %15s (%15s : %s) : | %15s (%15s : %s) |\n" $S_HOSTNAME $S_IPADDR $S_PORT $M_HOSTNAME $M_IPADDR $M_PORT

      done < $HOST_FILE
      echo " ---------------------------------------------------------------------------------------"
  else    
      echo "[Info] No hosts found for given parameters."
  fi

  return 0
}

#-------------------------------------------------------- change_master --
slaving() {

  echo "Do you want to continue (yes/no)?"
  read CONFIRM < /dev/tty

  [ "$CONFIRM" != "yes" ] && exit 1

  LOG_FILE=$SLAVE_LOG_DIR/${SCRIPT_NAME}_logs.log
  LOCK_FILE=$SLAVE_LOG_DIR/${SCRIPT_NAME}.lock
  
  touch $LOCK_FILE

  while true 
  do
      while read LINE
      do
          if [ ! -f $LOCK_FILE ] 
          then
              echo "LOCK_FILE doesn't exist. Exiting..."
              rm -f $TMP_FILE $TMP_FILE2 $HOST_FILE $HOST_FILE2
              exit 1
          fi
          S_HOSTNAME=`echo $LINE | cut -d":" -f1`
          S_IPADDR=`echo $LINE | cut -d":" -f2`
          S_PORT=`echo $LINE | cut -d":" -f3`
          M_HOSTNAME=`echo $LINE | cut -d":" -f4`
          M_IPADDR=`echo $LINE | cut -d":" -f5`
          M_PORT=`echo $LINE | cut -d":" -f6`
         
          # Checking if this is first iteration
          CHANGE_MASTER_FILE=$SLAVE_LOG_DIR/${S_HOSTNAME}_${M_PORT}.sql
          MASTER_STATUS_FILE=$SLAVE_LOG_DIR/${M_HOSTNAME}_${M_PORT}_master_status.sql

          if [ ! -f $CHANGE_MASTER_FILE ] 
          then
              # Creating CHANGE_MASTER command for first time.
          
              mysql -u$USER -p$PASSWD -h$M_IPADDR -P$M_PORT -e"show master status\G" > $MASTER_STATUS_FILE
              [ $? -ne 0 ] && echo "Error occurred during executing 'show master status' on '$M_HOSTNAME : $M_PORT'" && exit 1

              M_FILE=`cat $MASTER_STATUS_FILE | grep "File" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
              M_POS=`cat $MASTER_STATUS_FILE | grep "Position" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`

              CHANGE_CMD=`echo "CHANGE MASTER TO MASTER_HOST='$M_IPADDR', MASTER_USER='$REPL_USER', MASTER_PASSWORD='$REPL_PASSWD', MASTER_LOG_FILE='$M_FILE', MASTER_LOG_POS=$M_POS, MASTER_PORT=$M_PORT" | sed -e "s/' /'/g" -e "s/= /=/g"`
          
              echo "stop slave; $CHANGE_CMD; start slave;" > $CHANGE_MASTER_FILE
          fi
          
          # Everytime start slave, wait for x minutes, stop slave and persist positions.
          echo "`date "+%Y-%m-%d %H:%M:%S"` [Start] $M_HOSTNAME($M_PORT) --> $S_HOSTNAME($S_PORT)" | tee -a $LOG_FILE
          mysql -u$USER -p$PASSWD -h$S_IPADDR -P$S_PORT < $CHANGE_MASTER_FILE
          
          # Looping every 5 seconds for given time.
          V_ITERATE=$(($V_ROTATION/5))
          for (( i=1; i<=$V_ITERATE; i++ ))
          do
           	  sleep 5
           	  mysql -u$USER -p$PASSWD -h$S_IPADDR -P$S_PORT -e"show slave status\G" > $TMP_FILE
           	  LAG=`cat $TMP_FILE | grep "Seconds_Behind_Master" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
              SQLERR=`cat $TMP_FILE | grep "Last_SQL_Errno" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
              IOERR=`cat $TMP_FILE | grep "Last_IO_Errno" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`

              # if no lag then breaking the loop and move to next.
           	  [ "$LAG" == "0" ] && i=$(($V_ITERATE+1)) 

              # If replication breaks in between, stopping the script
              if [ "$LAG" == "NULL" ] && [[ $SQLERR != "0" ||  $IOERR != "0" ]]
                  then
                  rm -f $TMP_FILE2
                  echo "Replication crashed on $S_HOSTNAME($S_PORT). Please check $CHANGE_MASTER_FILE." |tee -a $TMP_FILE2
                  cat $TMP_FILE >> $TMP_FILE2
                  cat $TMP_FILE2 | /bin/mail -s "Multi-Source Replication CRASHED" "dba@creditkarma.com"
                  echo "Replication crashed on $S_HOSTNAME($S_PORT)" | mail "${AJIVANI},${AARORA}"
                  rm -f $LOCK_FILE $HOST_FILE $HOST_FILE2 $TMP_FILE $TMP_FILE2 
                  exit 1
              fi
          done

          mysql -vvv -u$USER -p$PASSWD -h$S_IPADDR -P$S_PORT -e"stop slave; show slave status\G" | tee -a $LOG_FILE
          mysql -u$USER -p$PASSWD -h$S_IPADDR -P$S_PORT -e"show slave status\G" > $TMP_FILE
          
          M_FILE=`cat $TMP_FILE | grep "Relay_Master_Log_File" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
          M_POS=`cat $TMP_FILE | grep "Exec_Master_Log_Pos" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`

          CHANGE_CMD=`echo "CHANGE MASTER TO MASTER_HOST='$M_IPADDR', MASTER_USER='$REPL_USER', MASTER_PASSWORD='$REPL_PASSWD', MASTER_LOG_FILE='$M_FILE', MASTER_LOG_POS=$M_POS, MASTER_PORT=$M_PORT" | sed -e "s/' /'/g" -e "s/= /=/g"`

          echo "stop slave; $CHANGE_CMD ; start slave;" > $TMP_FILE
  
          if ! diff $CHANGE_MASTER_FILE $TMP_FILE > /dev/null
          then
              cat $TMP_FILE > $CHANGE_MASTER_FILE
          fi

          mysql -u$USER -p$PASSWD -h$M_IPADDR -P$M_PORT -e"show master status\G" > $TMP_FILE

          RM_FILE=`cat $TMP_FILE | grep "File" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
          RM_POS=`cat $TMP_FILE | grep "Position" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
 
          echo "`date "+%Y-%m-%d %H:%M:%S"` [End]   $M_HOSTNAME($M_PORT) --> $S_HOSTNAME($S_PORT) Master at '$RM_FILE:$RM_POS' Slave at '$M_FILE:$M_POS'" | tee -a $LOG_FILE

      done < $HOST_FILE

      [ ! -f $HOST_FILE ] && echo "HOST_LIST file does not exist. Exiting..." && exit 1
      
      echo ""
      echo "*** Starting loop again ***"
      echo ""
  done
}
#----------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  display_move
  slaving
  return 0
}

main $*
