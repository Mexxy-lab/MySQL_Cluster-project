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
# Purpose: This script should be executed as a preFailover hook from DB Orchestrator.  
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ORC_CONFIG_FILE=/etc/orchestrator.conf.json
SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
CANDIDATE_LIST=/tmp/candidate.$$
EMAIL="dba@creditkarma.pagerduty.com"

NODE_USER=`cat $ORC_CONFIG_FILE |grep "MySQLTopologyUser" | cut -d ':' -f2 | sed -e 's/[ ",]//g'`
NODE_PASSWD=`cat $ORC_CONFIG_FILE |grep "MySQLTopologyPassword" | cut -d ':' -f2 | sed -e 's/[ ",]//g'`

NODE_AUTH="mysql -u$NODE_USER -p$NODE_PASSWD"

#------------------------------------------------------------------- debug --
debug() {
    echo "$1" | mail -s "Database Failover: $SCRIPT_NAME hook FAILED" "$EMAIL" && exit 1   
}

#---------------------------------------------------------------------- help --
help(){
  echo '''
  This script should be executed as a preFailover hook from DB Orchestrator.  

  Usage:
  
  $SCRIPT_NAME.sh --dead-master <deadmasterhost:port> --execute

    Required:
        --dead-master               Hostinfo of current primary host. (ie. fldb001.prod.iad1.ckint.io:3301)
        --execute                   Y/N. Default N
    
    Example:
        $SCRIPT_NAME.sh --dead-master fldb001.prod.iad1.ckint.io:3301 --execute
  '''
}

#-------------------------------------------------------------- process_args --
process_args() {
  
  options=$@
  # An array with all the arguments
  args=($options)
  [[ $args == "--help" || $args == "" ]] && help && exit 1

  V_EXECUTE="N"
  for arg in $options
  do
     if [[ ${args[$i]:0:1} == "-" && ${args[$i+1]:0:1} != "-" ]]
     then
         case ${args[$i]} in
             --dead-master )            V_DEAD_MASTER=${args[$i+1]};;
             --execute )                V_EXECUTE="Y";;
             *)                         echo "Invalid option '${args[$i]}'" && exit 1;;
         esac
         i=$(($i+2))
    else
         case ${args[$i]} in
             --execute )                V_EXECUTE="Y";;
         esac
         i=$(($i+1))
    fi
  done

  if [ ! -z "${V_DEAD_MASTER}" ] 
  then
      DEADMASTER_HOST=`echo $V_DEAD_MASTER |cut -d":" -f1`
      DEADMASTER_PORT=`echo $V_DEAD_MASTER |cut -d":" -f2`
      DEADMASTER_DC=`echo $DEADMASTER_HOST |cut -d"." -f2-`
  else 
      debug "Please specify 'deadMasterhost:port' for --dead-master option" 
  fi
 
  return 0
}

#------------------------------------------------------------- postfailove --
prefailover() {
   
  # Fetch list of slaves of a DeadMaster but excluding the list which shouldn't promoted at masters from the config file.
  EXCLUDE_HOSTS=`awk '/],/ {f=0;next} {$f=$f};f; /PromotionIgnoreHostnameFilters/ {f=1}' $ORC_CONFIG_FILE | sed 's/[",]//g' | xargs | sed -e 's/ /\\|/g'`

  NODE_LIST=`/usr/bin/orchestrator -c which-slaves -i $V_DEAD_MASTER --quiet |grep -v -E "${EXCLUDE_HOSTS}"`

  [ "$NODE_LIST" == "" ] && debug "No failover candidate available"

  /usr/bin/nc -z $DEADMASTER_HOST $DEADMASTER_PORT > /dev/null
  if [ $? -eq 0 ] 
  then
      # MySQL is running on DeadMaster, trying to set SUPER_READ_ONLY to ON.
      if [ "$V_EXECUTE" == "--execute" ] 
      then 
          i=1
          while [[ $i -le 3 ]] 
          do
              $NODE_AUTH -h $DEADMASTER_HOST -P $DEADMASTER_PORT -e"SET GLOBAL SUPER_READ_ONLY=ON" 2>&1
              [[ $? -eq 0 ]] && PROCEED=1 && break
              i=$((i+1))
              sleep 1
          done
      else
          echo "This is a dry-run. It won't execute SUPER_READ_ONLY=ON on '$DEADMASTER'."
          PROCEED=1
      fi  
      [[ $PROCEED -ne 1 ]] && debug "Unable to set SUPER_READ_ONLY=ON on '$DEADMASTER'"
  fi 
  
  # Generating master candidate list.
  for NODE in $NODE_LIST
  do
      NODE_HOSTNAME=`echo $NODE | cut -d":" -f1`
      NODE_PORT=`echo $NODE | cut -d":" -f2`
 
      # If node's data center is not matching with deadMaster's, it shouldn't get promoted.
      if [[ $NODE != *$DEADMASTER_DC* ]]
      then
          /usr/bin/orchestrator -c register-candidate -i $NODE --promotion-rule=must_not > /dev/null
      else
          echo $NODE >> $CANDIDATE_LIST
          /usr/bin/orchestrator -c register-candidate -i $NODE --promotion-rule=prefer > /dev/null
      fi
  done

  [ ! -s $CANDIDATE_LIST ] && debug "No failover candidate available"

  # Looping for maximum 10 minutes
  i=0
  while [[ $i -lt 600 ]]
  do
      while read slave; do
          S_HOSTNAME=`echo $slave |cut -d":" -f1`
          S_PORT=`echo $slave |cut -d":" -f2`
    
          # Loop until 1 slave has applied all IO events it received
        
          STATUS=$($NODE_AUTH -h$S_HOSTNAME -P$S_PORT -e "show slave status\G" 2>&1)
          if [[ `echo "$STATUS"` ==  *"Slave_SQL_Running: Yes"* ]]
          then
              if [[ `echo "$STATUS" | grep "Read_Master_Log_Pos\|Exec_Master_Log_Pos" | cut -d":" -f2 | uniq | wc -l` -eq 1 ]]
              then
                  echo `date "+%Y-%m-%d_%H:%M:%S"` " - $S_HOSTNAME:$S_PORT seems to be in sync. Exiting..." 
                  rm -f $CANDIDATE_LIST
                  exit
              else
                  echo `date "+%Y-%m-%d_%H:%M:%S"` " - $S_HOSTNAME:$S_PORT is lagging"
              fi
          fi
      done < $CANDIDATE_LIST
      i=$((i+1))
      sleep 1
  done
  return 0
}
#---------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  prefailover
  return 0
}

main $*
