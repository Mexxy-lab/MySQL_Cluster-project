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
# Purpose: This script should be used to check processlist on given list
#          of database servers. 
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
HOST_FILE=/tmp/${SCRIPT_NAME}_hostfile.$$
RESULT_FILE=/tmp/${SCRIPT_NAME}_resultfile.$$

#---------------------------------------------------------------------- help --
help(){
  echo '''
  This script should be used to check/modify mysql global variables for given shards.
  
  Usage:
  
    sh $SCRIPT_NAME.sh [ -d <DATA_CENTER> -g <SHARD_GROUP> -h <HOST_NAME> -n <INSTANCE_NUMBER> ]
  
    Arguments:
        -d or --data-center       Data Center code (ie. ckw, cke)
        -g or --group             Group (ie. mono, tkdb, fldb, fodb, budb, ipdb)
        -h or --hostname          Hostnamer (ie. mdb001.iad1, fodb9.sjc1)
        -p or --port              Port (ie. 3301 or 3301,3302)
        -n or --instance-number   Instance Number (ie. 1,2 or 1-3,4)
        -c or --count             Count of users/search string 
        -a or --alert             Alert based on search string
        -l or --limit             for alert threshold

    Example:
        sh $SCRIPT_NAME.sh -d ckw -g fldb -n 1-8
        sh $SCRIPT_NAME.sh -h fldb9.sjc1 -p 3301
  '''
}

#-------------------------------------------------------------- process_args --
process_args() {

  V_ALERT="" 
  V_LIMIT="0"
  
  options=$@

  # An array with all the arguments
  args=($options)

  [[ $args == "--help" || $args == "" ]] && help && exit 1

  for arg in $options
  do
     if [[ ${args[$i]} == "-"* || ${args[$i]} == "--"* ]] && [[ ${args[$i+1]} != "-"* || ${args[$i+1]} != "--"* ]] 
     then
        case ${args[$i]} in
             -d | --data-center )       V_DATA_CENTER=${args[$i+1]};;
             -g | --group )             V_GROUP=${args[$i+1]};;
             -n | --instance-number )   V_INSTANCE_NUMBER=${args[$i+1]};;
             -h | --hostname )          V_HOSTNAME=${args[$i+1]};;
             -p | --port )              V_PORT=${args[$i+1]};; 
             -c | --count )             V_COUNT=${args[$i+1]};;
             -a | --alert )             V_ALERT="Y";;  
             -l | --limit )             V_LIMIT=${args[$i+1]};;
             *)                         echo "Invalid option '${args[$i]}'" && exit 1;;
        esac
    i=$(($i+2))

  else

      case ${args[$i]} in
           --alert )                         V_ALERT="Y";;
      esac
      i=$(($i+1))

fi
done

  RANGE=" where "
  if [ -z "${V_HOSTNAME}" ]  
  then
      [ -z "${V_DATA_CENTER}" ] && echo "Please specify 'Data Center' for -d option. See --help for help" && exit 1
      [ -z "${V_GROUP}" ] && echo "Please specify 'Group' for -g option. See --help for help" && exit 1
      [ ! -z "${V_DATA_CENTER}" ] && DCENTERS=`echo $V_DATA_CENTER | sed "s/,/','/g"` && RANGE="$RANGE dataCenter in ('$DCENTERS')"
      [ ! -z "${V_GROUP}" ] && GRPS=`echo $V_GROUP | sed "s/,/','/g"` && RANGE="$RANGE and groupName in ('$GRPS')"
  else
      HOSTS=`echo $V_HOSTNAME | sed "s/,/','/g"` && RANGE="$RANGE hostname in ('$HOSTS')"
      [ ! -z "${V_DATA_CENTER}" ] && DCENTERS=`echo $V_DATA_CENTER | sed "s/,/','/g"` && RANGE="$RANGE and dataCenter in ('$DCENTERS')"
      [ ! -z "${V_GROUP}" ] && GRPS=`echo $V_GROUP | sed "s/,/','/g"` && RANGE="$RANGE and groupName in ('$GRPS')"
  fi

  [ ! -z "${V_INSTANCE_NUMBER}" ] && RANGE="$RANGE and shardNumber in (`echo $V_INSTANCE_NUMBER | awk 'BEGIN { RS=","; FS="-"; ORS="" } NR > 1 { print "," } NF > 1  { for (i=$1; i<$2; ++i) { print i "," } print $2; next } { print $1 }'`)"
  [ ! -z "${V_PORT}" ] && PORTS=`echo $V_PORT | sed "s/,/','/g"` && RANGE="$RANGE and port in ('$PORTS')"

  mysql -NB -e"select concat(hostName, \":\", fqdn, \":\", port) from $ADMIN_SCHEMA.$ADMIN_TABLE $RANGE" > $HOST_FILE
  [ ! -s $HOST_FILE ] && echo "No record(s) found for given Input Parameters." && exit 1
  
  return 0
}

#---------------------------------------------------------- func_processlist --
func_processlist() { 

  HOSTNAME=`echo $LINE | cut -d":" -f1`
  FQDN=`echo $LINE | cut -d":" -f2`
  PORT=`echo $LINE | cut -d":" -f3`

  echo "-----------------------------------------------------------------
$FQDN:$PORT
-----------------------------------------------------------------" > ${RESULT_FILE}_${FQDN}_${PORT}

  mysql -vvv -u$USER -p$PASSWD -h$FQDN -P$PORT --connect_timeout=10 -e"select ID, USER, HOST,SUBSTR(STATE,1,10) AS STATE,COMMAND,TIME,DB,SUBSTR(INFO,1,50) AS INFO from information_schema.processlist;" 2>/dev/null >> ${RESULT_FILE}_${FQDN}_${PORT}
  [ $? -ne 0 ] && echo -e "${RED}Error occurred during executing SQL on '$HOSTNAME : $PORT'${NOCOLOR}" >> ${RESULT_FILE}_${FQDN}_${PORT}
  
}

#--------------------------------------------------------------- processlist --
processlist() {
  
  while read LINE
  do
      func_processlist $LINE &
  done < $HOST_FILE
  wait
  
  return 0
}

result_file() {

if [[ "$V_COUNT" != "" && "$V_ALERT" != "Y" ]]; then
echo "-------------------------------------------"
echo "Count of connections with : $V_COUNT"
echo "-------------------------------------------"

  while read LINE
    do
          FQDN=`echo $LINE | cut -d":" -f2`
          PORT=`echo $LINE | cut -d":" -f3`
          count=`cat ${RESULT_FILE}_${FQDN}_${PORT}|grep -i "$V_COUNT"|wc -l`

          echo "$FQDN:$PORT        $count"
          rm -f ${RESULT_FILE}_${FQDN}_${PORT}
          
    done < $HOST_FILE

elif [[ "$V_COUNT" == "" && "$V_ALERT" != "Y" ]];then

  while read LINE
    do
          FQDN=`echo $LINE | cut -d":" -f2`
          PORT=`echo $LINE | cut -d":" -f3`

          cat ${RESULT_FILE}_${FQDN}_${PORT}
          rm -f ${RESULT_FILE}_${FQDN}_${PORT}

    done < $HOST_FILE

fi

}

alert_unauth () {

if [[ "$V_ALERT" == "Y" ]]; then

  while read LINE
    do
          FQDN=`echo $LINE | cut -d":" -f2`
          PORT=`echo $LINE | cut -d":" -f3`
          count=`cat ${RESULT_FILE}_${FQDN}_${PORT}|grep -i "$V_COUNT"|wc -l`

       if [[ "$count" -gt "$V_LIMIT" ]]; then
        
          echo "$FQDN:$PORT        $count">>/tmp/processlist_test_$$

       fi

       rm -f ${RESULT_FILE}_${FQDN}_${PORT}

    done < $HOST_FILE

  if [[ -s /tmp/processlist_test_$$ ]]; then

    cat /tmp/processlist_test_$$ |mail -s "$V_COUNT connections on $V_DATA_CENTER: $V_GROUP" "$PDMAILID"

  fi

fi

}
#---------------------------------------------------------------------- main --
# Main Script Processing
#
main () {

  process_args $*
  processlist
  result_file
  alert_unauth
  return 0

}

main $*
