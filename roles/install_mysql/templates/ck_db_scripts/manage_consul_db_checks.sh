#!/bin/bash
# =============================================================================
# {% for line in fileBanner %}
# {{line}} {% endfor %}
# =============================================================================

###############################################################################
#
# Auther : Ashok Jivani
# Purpose: This script should be used to active/deactivate DB checks in consul. 
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
TMP_FILE=/tmp/${SCRIPT_NAME}_tmpfile.$$

FULL_HOSTNAME=`hostname -f`
[[ "$FULL_HOSTNAME" == *"sjc1"* ]] && OPSDB="opsdb001.sjc1.creditkarma.com"
[[ "$FULL_HOSTNAME" == *"iad1"* ]] && OPSDB="opsdb001.prod.iad1.ckint.io"
[[ "$FULL_HOSTNAME" == *"us-central1"* ]] && OPSDB="opsdb001.prod.iad1.ckint.io"
[[ "$FULL_HOSTNAME" == *"euw2"* ]] && OPSDB="opsdb001.prod.euw2.ckint.io"

TOOLS_AUTH="mysql -u$TOOLS_USER -p$TOOLS_PASSWD -h $OPSDB"

#---------------------------------------------------------------------- help --
help(){
  echo "###############################################################################"
  echo ""
  echo "This script should be used to manage database service checks on consul."
  echo ""
  echo "Usage:"
  echo ""
  echo "$SCRIPT_NAME.sh [ --master-candidate <value> --slave-candidate <value> ]"
  echo ""
  echo "  Optional:"
  echo "      --master-candidate     Master Candidate check (1=Enable, 2=Disable)"
  echo "      --slave-candidate      Slave Candidate check (1=Enable, 2=Disable)"
  echo ""
  echo "  Example:" 
  echo "      $SCRIPT_NAME.sh --help" 
  echo "      $SCRIPT_NAME.sh --master-candidate 1 --slave-candidate 1"
  echo ""
  echo "###############################################################################"
  exit 1
}

#-------------------------------------------------------------- process_args --
process_args() {

  options=$@

  # An array with all the arguments
  args=($options)

  [[ $args == "--help" || $args == "-h" ]] && help && exit 1
  
  V_CHECK="Y"
  i=0
  for arg in $options
  do
      if [[ ${args[$i]:0:1} == "-" && ${args[$i+1]:0:1} != "-" ]]
      then
          case ${args[$i]} in
             -m | --master-candidate )       V_MASTER_CANDIDATE=${args[$i+1]};;
             -s | --slave-candidate )        V_SLAVE_CANDIDATE=${args[$i+1]};;
             *)                              echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      fi
  done

  CONDITION=""
  if [[ ! -z "${V_MASTER_CANDIDATE}" ]] 
  then
     V_CHECK="N"
     if ! [[ "${V_MASTER_CANDIDATE}" == 0 || "${V_MASTER_CANDIDATE}" == 1 ]] 
     then 
        echo "Value for the --master-candidate parameter should be 0 or 1" && help
     else
  	    CONDITION="consulMasterCandidate = '$V_MASTER_CANDIDATE'" 
     fi
  fi

  if [[ ! -z "${V_SLAVE_CANDIDATE}" ]] 
  then
     V_CHECK="N"
     if ! [[ "${V_SLAVE_CANDIDATE}" == 0 || "${V_SLAVE_CANDIDATE}" == 1 ]] 
     then
        echo "Value for the --slave-candidate parameter should be 0 or 1" && help
     else
        if [[ "$CONDITION" == "" ]]
        then  
            CONDITION="consulSlaveCandidate = '$V_SLAVE_CANDIDATE'" 
        else
            CONDITION="$CONDITION, consulSlaveCandidate = '$V_SLAVE_CANDIDATE'" 
        fi    
     fi
  fi

  [[ "$V_CHECK" == "Y" ]] && show_db_checks
  if [[ "$CONDITION" != "" ]] 
  then
      # notify mysql-change-log slack channel
      mysql_change_log
      
      manage_db_checks
  fi
} 

#---------------------------------------------------------- mysql-change-log --
mysql_change_log() {

 SLACK_EMAIL="k6a1q8d6f6d2z2b7@ckcorp.slack.com"
 WHO=`logname`
 CMD="$SCRIPT_NAME.sh $options"
 echo "$CMD" | mail -s "$WHO executed" "$SLACK_EMAIL" 
}

#------------------------------------------------------------ show_db_checks --
show_db_checks() {
  
  SQL="SELECT concat(hostname,':',port, ':', instanceName, ':', consulMasterCandidate, ':', consulSlaveCandidate) from $ADMIN_SCHEMA.$ADMIN_TABLE where fqdn = '$FULL_HOSTNAME'"
 
  $TOOLS_AUTH -NB -e"$SQL" 2>/dev/null > $TMP_FILE
  [ $? -ne 0 ] && echo "Error occured during executing query on '$OPSDB" && exit 1
  
  if [ -s $TMP_FILE ]
  then 
      echo ""
      echo " -----------------------------------------------------------------------------------------"
      echo "|       HOSTNAME       | INSTANCE_NAME | CONSUL_MASTER_CANDIDATE | CONSUL_SLAVE_CANDIDATE |"
      echo " -----------------------------------------------------------------------------------------"
      while read LINE
      do
         H_HOSTNAME=`echo $LINE | cut -d":" -f1`
         H_PORT=`echo $LINE | cut -d":" -f2`
         H_INSTANCENAME=`echo $LINE | cut -d":" -f3`
         H_MASTER_CANDIDATE=`echo $LINE | cut -d":" -f4`
         H_SLAVE_CANDIDATE=`echo $LINE | cut -d":" -f5`

         printf "| %15s:%s | %13s |            %s            |            %s           |\n" $H_HOSTNAME $H_PORT $H_INSTANCENAME $H_MASTER_CANDIDATE $H_SLAVE_CANDIDATE 
      done < $TMP_FILE
      echo " -----------------------------------------------------------------------------------------"
  fi
  rm -f $TMP_FILE && exit
  
}

#----------------------------------------------------------- manage_db_check --
manage_db_checks() {
 
  SQL="UPDATE $ADMIN_SCHEMA.$ADMIN_TABLE set $CONDITION where fqdn = '$FULL_HOSTNAME'"

  echo ""
  echo "CAUTION!! This script will execute below commands."
  echo ""
  echo " 1. '$SQL' on $OPSDB"
  echo " 2. salt-call state.sls consul.config.service.db-rw-ro"
  echo " 3. consul reload"  
  echo ""
  echo ""
  echo "Do you want to contine(yes/no)?"
  read CONFIRM                                                                                                                                                                                
  [ "$CONFIRM" != "yes" ] && exit 1
 
  echo "[Info] Updating $ADMIN_SCHEMA.$ADMIN_TABLE host entry."

  # Updating opsdb:ckadmin.host_info entry.
  $TOOLS_AUTH -NB -e"$SQL" 2>/dev/null
  [ $? -ne 0 ] && echo "Error occurred during executing query on '$OPSDB" && exit 1
  
  echo "[Info] Running Consul salt state..."
  # Applying consul service check
  /usr/bin/salt-call state.sls consul.config.service.db-rw-ro 2>/dev/null > $TMP_FILE
  [ $? -ne 0 ] && echo "Error occurred during executing 'state.sls consul.config.service.db-rw-ro'" && exit 1

  echo "[Info] Reloading Consul."
  # Relading Consul
  /usr/bin/consul reload 2>/dev/null > $TMP_FILE
  [ $? -ne 0 ] && echo "Error occurred during executing 'consul reload'." && exit 1

  echo "[Info] DB service checks in Consul updated successfully."
  
  rm -f $TMP_FILE
  return 0
}


#---------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  return 0
}

main $*
