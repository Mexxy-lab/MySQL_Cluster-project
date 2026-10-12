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
# Purpose: This script should be used to move database SLAVE(s) to the given 
#          MASTER(s) group. 
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

HOST_FILE=${CURRENT_DIR}/${SCRIPT_NAME}_hostfile.$$
HOST_FILE2=${CURRENT_DIR}/${SCRIPT_NAME}_hostfile2.$$
TMP_FILE=${CURRENT_DIR}/${SCRIPT_NAME}_tmpfile.$$
LOG_FILE=${CURRENT_DIR}/logs_${SCRIPT_NAME}_$$.log
ERR_FILE=${CURRENT_DIR}/err_${SCRIPT_NAME}_$$.err
EXECUTE_FILE=${CURRENT_DIR}/execute_${SCRIPT_NAME}_$$.sh
COMMAND_FILE=/tmp/commands_${SCRIPT_NAME}.$$

#----------------------------------------------------------------------- help --
help(){
  echo '''
  This script should be used to move SHARD SLAVES to the given SHARD MASTERS group.
  
  Usage:

  sh $SCRIPT_NAME.sh < REQUIRED > [ OPTIONAL ]
  
    Required:
        -r  or --role             Database Role  (ie. mono, shard, ticket, monovp)
        -m or --master            Master (ie, ckw.budb or mdb001.iad1)
        -s or --slave             Slave (ie, ckw.budb or ckw.mdb9,ckw.mdb10 or ckw.budb,ckw.fodb,ckw.fldb)
    
    Optional:
        -h  or --slave-hosts      List of Slave(s) (ie. fldb001.iad1,fldb002.iad1)
        -g  or --groupname        GroupName (ie. darwindb, odditydb)
        -n  or --instance-number  Instance Number(s) (ie. 1,2 1-4,5)
    
    Example:
        sh $SCRIPT_NAME.sh --role shard -m ckw.fodb -s cke.fldb -h fldb001.iad1 -n 1
        sh $SCRIPT_NAME.sh --role shard -m ckw.fodb -s ckw.fldb,ckw.budb,ckw.fldb
        sh $SCRIPT_NAME.sh --role mono -m mdb001.iad1 -s mdb02.iad1,mdb003.iad1
        sh $SCRIPT_NAME.sh --role monovp -m darwindb001.iad1 -s darwindb001.sjc1 -g darwindb
  
  '''
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
             -m | --master )           V_MASTER=${args[$i+1]};;
             -s | --slave )            V_SLAVE=${args[$i+1]};;
             -h | --slave-hosts )      V_SLAVE_HOSTS=${args[$i+1]};;
             -n | --instance-number )  V_INSTANCE_NUMBER=${args[$i+1]};;
             *)                        echo "Invalid option '${args[$i]}'" && exit 1;;
        esac
        i=$(($i+2))
     fi
  done

  [ -z "${V_ROLE}" ] && echo "Please specify 'Role' for -r or --role option. See --help for help" && exit 1
  [ -z "${V_MASTER}" ] && echo "Please specify 'Master' for --master option. See --help for help" && exit 1
  [ -z "${V_SLAVE}" ] && echo "Please specify 'Slave' for --slave option. See --help for help" && exit 1
  [ "${V_ROLE}" == "monovp" ] && [ -z "${V_GROUP}" ] && echo "Please specify 'GroupName' for -g option. See --help for help" && exit 1

  RANGE=""

  if [[ "${V_ROLE}" == *"shard"* ]] 
  then
     M_FILTER=`echo $V_MASTER | sed "s/,/'), ('/g" |sed "s/\./', '/g"`
     S_FILTER=`echo $V_SLAVE | sed "s/,/'), ('/g" |sed "s/\./', '/g"`
     RANGE="and (m.datacenter, m.groupname) in (('$M_FILTER'))"
     RANGE="$RANGE and (s.datacenter, s.groupname) in (('$S_FILTER'))"
     [ ! -z "${V_SLAVE_HOSTS}" ] && S_HOSTS=`echo $V_SLAVE_HOSTS | sed "s/,/','/g"` && RANGE="$RANGE and s.hostname in ('$S_HOSTS')"
     [ ! -z "${V_INSTANCE_NUMBER}" ] && RANGE="$RANGE and s.shardNumber in (`echo $V_INSTANCE_NUMBER | awk 'BEGIN { RS=","; FS="-"; ORS="" } NR > 1 { print "," } NF > 1  { for (i=$1; i<$2; ++i) { print i "," } print $2; next } { print $1 }'`)"

     mysql -NB -e"select concat(s.hostName, \":\", s.port, \":\", s.fqdn, \":\", m.hostName, \":\", m.port, \":\", m.fqdn) from $ADMIN_SCHEMA.$ADMIN_TABLE m, $ADMIN_SCHEMA.$ADMIN_TABLE s where m.shardNumber = s.shardNumber and m.role='$V_ROLE' and s.role='$V_ROLE' $RANGE" 2>/dev/null > $HOST_FILE  

     [ $? -ne 0 ] && echo "Error occurred during executing query against '$ADMIN_SCHEMA.$ADMIN_TABLE'" && exit 1    

   elif [[ "${V_ROLE}" == "ticket" ]]
   then
     S_FILTER=`echo $V_SLAVE | sed "s/,/','/g"`
     RANGE=" and (s.hostname) in ('$S_FILTER')"
     
     [ ! -z "${V_GROUP}" ] && RANGE="$RANGE and m.groupname = '$V_GROUP' and s.groupname = '$V_GROUP'"

     mysql -NB -e"select concat(s.hostName, \":\", s.port, \":\", s.fqdn, \":\", m.hostName, \":\", m.port, \":\", m.fqdn) from $ADMIN_SCHEMA.$ADMIN_TABLE m, $ADMIN_SCHEMA.$ADMIN_TABLE s where m.shardNumber = s.shardNumber and m.hostName = '$V_MASTER' and m.role='$V_ROLE' and s.role='$V_ROLE' $RANGE" 2>/dev/null > $HOST_FILE
         
     [ $? -ne 0 ] && echo "Error occurred during executing query against '$ADMIN_SCHEMA.$ADMIN_TABLE'" && exit 1

  else
     S_FILTER=`echo $V_SLAVE | sed "s/,/','/g"`
     RANGE=" and (s.hostname) in ('$S_FILTER')"
     
     [ ! -z "${V_GROUP}" ] && RANGE="$RANGE and m.groupname = '$V_GROUP' and s.groupname = '$V_GROUP'"

     mysql -NB -e"select concat(s.hostName, \":\", s.port, \":\", s.fqdn, \":\", m.hostName, \":\", m.port, \":\", m.fqdn) from $ADMIN_SCHEMA.$ADMIN_TABLE m, $ADMIN_SCHEMA.$ADMIN_TABLE s where m.hostName = '$V_MASTER' and m.role='$V_ROLE' and s.role='$V_ROLE' $RANGE" 2>/dev/null > $HOST_FILE
         
     [ $? -ne 0 ] && echo "Error occurred during executing query against '$ADMIN_SCHEMA.$ADMIN_TABLE'" && exit 1
  fi
  [ ! -s $HOST_FILE ] && echo "Please specify correct Input parameters. See --help for help." && exit 1

}
#---------------------------------------------------------- func_display_move --
func_display_move() {

  S_HOST=`echo $1 | cut -d":" -f1`   
  S_PORT=`echo $1 | cut -d":" -f2`
  S_FQDN=`echo $1 | cut -d":" -f3`
  NM_HOST=`echo $1 | cut -d":" -f4`
  NM_PORT=`echo $1 | cut -d":" -f5`
  NM_FQDN=`echo $1 | cut -d":" -f6`

  GTID=`mysql -u$USER -p$PASSWD -h$NM_FQDN -P$NM_PORT -NB -e"select count(1) from (select @@global.gtid_mode='ON' as gtid) a where a.gtid=1;" 2>/dev/null`

  TMP_FILE=/tmp/${SCRIPT_NAME}_tmp_${S_FQDN}_${S_PORT}.$$
  ERR_FILE=/tmp/${SCRIPT_NAME}_err_${S_FQDN}_${S_PORT}.$$
  
  if [ $GTID -eq 1 ] 
  then
     QRY="select @@global.gtid_executed" 
     M_GTID_EXECUTED1=$(mysql -u$USER -p$PASSWD -h$NM_FQDN -P$NM_PORT -NB -e"$QRY" 2>/dev/null | sed 's/\\n//g')
     S_GTID_EXECUTED1=$(mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -NB -e"$QRY" 2>/dev/null | sed 's/\\n//g')
     sleep 1
     M_GTID_EXECUTED2=$(mysql -u$USER -p$PASSWD -h$NM_FQDN -P$NM_PORT -NB -e"$QRY" 2>/dev/null | sed 's/\\n//g')
     S_GTID_EXECUTED2=$(mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -NB -e"$QRY" 2>/dev/null | sed 's/\\n//g')
  
     S_SUBTRACT=`mysql -u$TOOLS_USER -p$TOOLS_PASSWD -NB -e"select gtid_subtract('$S_GTID_EXECUTED2', '$S_GTID_EXECUTED1')" 2>/dev/null`                                 
     M_SUBTRACT=`mysql -u$TOOLS_USER -p$TOOLS_PASSWD -NB -e"select gtid_subtract('$M_GTID_EXECUTED2', '$M_GTID_EXECUTED1')" 2>/dev/null`                                 
     
     if [[ "$S_SUBTRACT" == "" && "$M_SUBTRACT" == "" ]]
     then
        S_GTID_EXECUTED=$S_GTID_EXECUTED2
        M_GTID_EXECUTED=$M_GTID_EXECUTED2
     else
        # check if more then one GTID set is currently updated.
        [[ "$S_SUBTRACT" == *","*  || "$M_SUBTRACT" == *","* ]] && echo "[Error] '$NM_HOST:$NM_PORT' or '$S_HOST:$S_PORT' has more than one gtid set changing atm." > $ERR_FILE && break
   
        # check if any of the servers is not writing anymore.
        [ "$S_SUBTRACT" != "" ] && EXCLUDE_SET=`echo $S_SUBTRACT | cut -d ':' -f1`  
        [ "$M_SUBTRACT" != "" ] && EXCLUDE_SET=`echo $M_SUBTRACT | cut -d ':' -f1`

        # Exclude r/w master's gtid set from both new_master and slave. 
        S_GTID_EXECUTED=`echo $S_GTID_EXECUTED2 | sed "s/$EXCLUDE_SET:[0-9]*-[0-9]*//" | sed "s/^,//" | sed "s/$,//"`
        M_GTID_EXECUTED=`echo $M_GTID_EXECUTED2 | sed "s/$EXCLUDE_SET:[0-9]*-[0-9]*//" | sed "s/^,//" | sed "s/$,//"`
     fi    
   
     # Check if master is a subset of slave.
     SUBSET=`mysql -u$TOOLS_USER -p$TOOLS_PASSWD -NB -e"select gtid_subset('$M_GTID_EXECUTED', '$S_GTID_EXECUTED')" 2>/dev/null` 
     [ $SUBSET -eq 0 ] && echo "[Error] '$NM_HOST:$NM_PORT' has errant transactions or '$S_HOST:$S_PORT' is behind '$NM_HOST:$NM_PORT'." > $ERR_FILE && break 
  fi

  mysql -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"show slave status\G" 2>/dev/null > $TMP_FILE

  S_LAG=`cat $TMP_FILE | grep "Seconds_Behind_Master" |cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
  CM_FQDN=`cat $TMP_FILE | grep "Master_Host" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
  CM_PORT=`cat $TMP_FILE | grep "Master_Port" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`

  CM_HOST=`mysql -NB -e"select hostName from $ADMIN_SCHEMA.$ADMIN_TABLE where fqdn = '$CM_FQDN' group by hostName;" 2>/dev/null`

  [ "$S_LAG" == "" ] && S_LAG="NULL"
  [ "$CM_PORT" == "" ] && CM_PORT="NULL"
  [ "$CM_HOST" == "" ] && CM_HOST="NULL"
  [ "$CM_FQDN" == "" ] && CM_FQDN="NULL"

  rm -f $TMP_FILE
  if [[ "$CM_FQDN:$CM_PORT" != "$NM_FQDN:$NM_PORT" ]]
  then
      echo "$S_HOST:$S_PORT:$S_FQDN:$CM_HOST:$CM_PORT:$CM_FQDN:$NM_HOST:$NM_PORT:$NM_FQDN:$S_LAG" > $TMP_FILE
  fi
}

#--------------------------------------------------------------- display_move --
display_move(){
  
  while read LINE
  do
      func_display_move $LINE &
  done < $HOST_FILE
  wait

  while read LINE
  do
      S_PORT=`echo $LINE | cut -d":" -f2`
      S_FQDN=`echo $LINE | cut -d":" -f3`
      THIS_TMP=/tmp/${SCRIPT_NAME}_tmp_${S_FQDN}_${S_PORT}.$$ 
      THIS_ERR=/tmp/${SCRIPT_NAME}_err_${S_FQDN}_${S_PORT}.$$ 
      [ -f $THIS_TMP ] && cat $THIS_TMP >> $HOST_FILE2
      [ -f $THIS_ERR ] && cat $THIS_ERR >> $ERR_FILE
      rm -f $THIS_TMP
  done < $HOST_FILE

  if [ -s $ERR_FILE ]
  then 
      echo "Following slave(s) couldn't move due to:"
      cat $ERR_FILE 
      echo ""
  fi    
  if [ -s $HOST_FILE2 ] 
  then
      echo ""
      echo " -------------------------------------------------------------------------------------------"
      echo "|           SLAVE           |  LAG  |       CURRENT_MASTER      |        NEW_MASTER         |"
      echo " -------------------------------------------------------------------------------------------"
      while read LINE
      do
         S_HOST=`echo $LINE | cut -d":" -f1`
         S_PORT=`echo $LINE | cut -d":" -f2`
         CM_HOST=`echo $LINE | cut -d":" -f4`
         CM_PORT=`echo $LINE | cut -d":" -f5`
         NM_HOST=`echo $LINE | cut -d":" -f7`
         NM_PORT=`echo $LINE | cut -d":" -f8` 
         S_LAG=`echo $LINE | cut -d":" -f10` 

         printf "| %20s:%s | %5s | %20s:%s | %20s:%s |\n" $S_HOST $S_PORT $S_LAG $CM_HOST $CM_PORT $NM_HOST $NM_PORT

      done < $HOST_FILE2
      echo " -------------------------------------------------------------------------------------------"
  else
  	  echo "[Info] No hosts found for given parameters which require CHANGE_MASTER. Exiting..." && exit 1
  fi
  return 0
}

#--------------------------------------------------------- func_change_master --
func_change_master()
{
  S_HOST=`echo $1 | cut -d":" -f1`
  S_PORT=`echo $1 | cut -d":" -f2`
  S_FQDN=`echo $1 | cut -d":" -f3`
  NM_HOST=`echo $1 | cut -d":" -f7`
  NM_PORT=`echo $1 | cut -d":" -f8`
  NM_FQDN=`echo $1 | cut -d":" -f9`

  TMP_FILE2=/tmp/${SCRIPT_NAME}_tmp2_${S_FQDN}_${S_PORT}.$$

  GTID=`mysql -u$USER -p$PASSWD -h$NM_FQDN -P$NM_PORT -NB -e"select count(1) from (select @@global.gtid_mode='ON' as gtid) a where a.gtid=1;" 2>/dev/null`
  if [ $GTID -eq 1 ]
  then
      V_POSITION="MASTER_AUTO_POSITION=1"
  else
      mysql -u$USER -p$PASSWD -h$NM_FQDN -P$NM_PORT -e"show master status\G" 2>/dev/null > $TMP_FILE2
      [ $? -ne 0 ] && echo "Error occurred during executing 'show master status' on '$NM_HOST : $M_PORT'" && exit 1 

      NM_FILE=`cat $TMP_FILE2 | grep "File" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      NM_POS=`cat $TMP_FILE2 | grep "Position" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`

      V_POSITION="MASTER_LOG_FILE='$NM_FILE', MASTER_LOG_POS=$NM_POS"
  fi

  NM_HOSTINFO=$NM_FQDN

  CHANGE_CMD=`echo "CHANGE MASTER TO MASTER_HOST='$NM_HOSTINFO', MASTER_PORT=$NM_PORT, MASTER_USER='$REPL_USER', MASTER_PASSWORD='$REPL_PASSWD', $V_POSITION" | sed -e "s/' /'/g" -e "s/= /=/g"`

# Generating TMP FILE for each host.
cat > $TMP_FILE2 << EOL
echo "\`date \"+%Y-%m-%d %H:%M:%S\"\` [INFO] Executing on $S_HOST ($S_FQDN:$S_PORT)"
mysql -vvv -u$USER -p$PASSWD -h$S_FQDN -P$S_PORT -e"stop slave; $CHANGE_CMD; start slave;"
if [ $? -eq 0 ]
then
    echo "\`date \"+%Y-%m-%d %H:%M:%S\"\` [INFO] CHANGE_MASTER command executed successfully."
else
    echo "\`date \"+%Y-%m-%d %H:%M:%S\"\` [ERROR] CHANGE_MASTER command failed (bad exit code, see log)."
fi
EOL
  return 0
}

#--------------------------------------------------------------- change_master --
change_master() {

  echo "Do you want to continue (yes/no)?"
  read CONFIRM < /dev/tty

  [ "$CONFIRM" != "yes" ] && exit 1

  # notify mysql-change-log slack channel
  mysql_change_log

  echo "Generating commands..."
  [ -f $COMMAND_FILE ] && rm -f $COMMAND_FILE
  echo "" >> $COMMAND_FILE
  while read LINE
  do
      func_change_master $LINE &   
  done < $HOST_FILE2
  wait

  while read LINE
  do
      S_PORT=`echo $LINE | cut -d":" -f2`
      S_FQDN=`echo $LINE | cut -d":" -f3`
      THIS_TMP=/tmp/${SCRIPT_NAME}_tmp2_${S_FQDN}_${S_PORT}.$$ 
      [ -f $THIS_TMP ] && cat $THIS_TMP >> $COMMAND_FILE
      rm -f $THIS_TMP
  done < $HOST_FILE2
  
  echo ""

# Generating the EXECUTE file

cat > $EXECUTE_FILE << EOL

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
COMMON_FUNC_FILE="${SCRIPT_DIR}/common_functions.sh"

. ${COMMON_FUNC_FILE}

if [ ! -f $COMMAND_FILE ]
then
    echo "file: $COMMAND_FILE doesn't exist."
    echo "NOTE: commands file gets deleted after first successful execution to prevent data inconsistency"
    echo "Exiting..."
    exit 1
fi
echo "-----------------------------------------------------"
echo "QUERY: stop slave; CHANGE MASTER to... ; start slave;"
echo "-----------------------------------------------------"
echo "Above query will be executed against following servers:"
echo ""
cat $COMMAND_FILE |grep "Executing" |cut -d' ' -f8- |  sed 's/"//g'
echo ""
if [ `cat $COMMAND_FILE | grep "Not Executing" |wc -l` -gt 0 ]
then
    echo "Excluding below servers due to wrong CHANGE_MASTER Command"
    echo ""
    cat $COMMAND_FILE |grep "Not Executing" |cut -d' ' -f9- |  sed 's/"//g'
    echo ""
fi
echo "Do you want to continue (yes/no)?"
read CONFIRM < /dev/tty
[ "\$CONFIRM" != "yes" ] && exit 1

# notify mysql-change-log slack channel 
mysql_change_log "$SCRIPT_NAME.sh $options"

echo "\`date \"+%Y-%m-%d %H:%M:%S\"\` Change Master script Started..."
sh $COMMAND_FILE >> $LOG_FILE 2>&1
if [ $? -eq 0 ]
then
    if [ \`cat $LOG_FILE |grep "^ERROR" |wc -l\` -gt 0 ]
    then
        echo "\`date \"+%Y-%m-%d %H:%M:%S\"\` [INFO] CHANGE_MASTER script partially Completed."
        echo "ERROR(s) found in : $LOG_FILE."
        mv $COMMAND_FILE ${COMMAND_FILE}.old
        echo "commands file has been renamed to ${COMMAND_FILE}.old. Please generate new commands file for the FAILED ones."
    else
    	echo "\`date \"+%Y-%m-%d %H:%M:%S\"\` [INFO] CHANGE_MASTER script Completed."
        rm -f $COMMAND_FILE
        echo ""
        echo "Logs are located at: $LOG_FILE"
    fi
else
    echo "\`date \"+%Y-%m-%d %H:%M:%S\"\` [ERROR] CHANGE_MASTER script failed (bad exit code, see log)."
fi
EOL

  echo "To run CHANGE_MASTER commands, Please execute: $EXECUTE_FILE"

  rm -f $HOST_FILE $HOST_FILE2
}
#----------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  display_move
  change_master
  return 0
}

main $*
