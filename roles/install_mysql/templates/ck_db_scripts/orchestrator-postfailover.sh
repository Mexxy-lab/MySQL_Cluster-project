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
# Purpose: This script should be executed as a postFailover hook from DB Orchestrator to manage DB CNAMEs.  
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ORC_CONFIG_FILE=/etc/orchestrator.conf.json
GCLOUD="/usr/local/share/google/google-cloud-sdk/bin/gcloud"
DNS_ZONE=`hostname -f |cut -d"." -f2- |tr '.' '-'`
ZONE_PARAMS="-z $DNS_ZONE --project prod-shared-vpc-host-project"
EMAIL="dba@creditkarma.pagerduty.com"

EXPORT_DNS_FILE="DnsZoneExport_`date "+%Y%m%d_%H%M%S"`.txt"
SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`

NODE_USER=`cat $ORC_CONFIG_FILE |grep "MySQLTopologyUser" | cut -d ':' -f2 | sed -e 's/[ ",]//g'`
NODE_PASSWD=`cat $ORC_CONFIG_FILE |grep "MySQLTopologyPassword" | cut -d ':' -f2 | sed -e 's/[ ",]//g'`

LOCAL_OPSDB="opsdb001.prod.{{ grains['datacenter'] }}.ckint.io"
TOOLS_USER="{{ salt['pillar.get']('admin_tools:tools_user', 'xxxxxxxxxxxx') }}"
TOOLS_PASSWD="{{ salt['pillar.get']('admin_tools:tools_password', 'xxxxxxxxxxxx') }}"

NODE_AUTH="mysql -u$NODE_USER -p$NODE_PASSWD"
OPSDB_AUTH="mysql -u$TOOLS_USER -p$TOOLS_PASSWD -h$LOCAL_OPSDB -P3306"

#------------------------------------------------------------------- debug --
debug() {
    echo "$1" | mail -s "Database Failover: $SCRIPT_NAME hook FAILED" "$EMAIL" && exit 1   
}

#---------------------------------------------------------------------- help --
help(){
  echo '''
  This script should be executed as a postFailover hook from DB Orchestrator to manage DB CNAMEs.  

  Usage:
  
  $SCRIPT_NAME.sh --dead-master <deadmasterhost:port> --new-master <newmasterhost:port> --execute

    Required:
        --dead-master               Hostinfo of current primary host. (ie. fldb001.prod.iad1.ckint.io:3301)
        --new-maste                 Hostinfo of new primary host. (ie. fodb001.prod.iad1.ckint.io:3301)
        --execute                   Y/N. Default N
    
    Example:
  
      To change sdb1.primary from fldb001.prod.iad1.ckint.io to fodb001.prod.iad1.ckint.io:
        $SCRIPT_NAME.sh --dead-master fldb001.prod.iad1.ckint.io:3301 --new-master fodb001.prod.iad1.ckint.io:3301 --execute
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
             --new-master )             V_NEW_MASTER=${args[$i+1]};;
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
  else 
      debug "Please specify 'deadMasterhost:port' for --dead-master option" 
  fi
  if [ ! -z "${V_NEW_MASTER}" ] 
  then
      NEWMASTER_HOST=`echo $V_NEW_MASTER |cut -d":" -f1`
      NEWMASTER_PORT=`echo $V_NEW_MASTER |cut -d":" -f2`
  else
      debug "Please specify 'newmasterhost:port' for --new-master option"
  fi
 
  # Fetch CNAME for deadMaster. We need to query OpsDB because hostName->instanceName mapping lives in OpsDB.
  PRIMARY_CNAME=`$OPSDB_AUTH -NB -e"SELECT CONCAT('primary.', instanceName,'.', SUBSTRING_INDEX(fqdn, '.', -4)) FROM ckadmin.host_info WHERE fqdn = '$DEADMASTER_HOST' AND port = '$DEADMASTER_PORT';"`
  [ $? -ne 0 ] && debug "Unable to query OpsDB to fetch a CNAME for '$V_DEAD_MASTER'"
  
  if [ "${V_EXECUTE}" == "N" ] 
  then
      echo "This is a DRY-RUN. This script would execute following commands:
      
      # Export DNS Zone
      # $GCLOUD dns record-sets export $EXPORT_DNS_FILE $ZONE_PARAMS
      
      # Start Transaction
      # $GCLOUD dns record-sets transaction start $ZONE_PARAMS
      
      # Remove CNAME from deadMaster
      # $GCLOUD dns record-sets transaction remove $ZONE_PARAMS --name $PRIMARY_CNAME. --type CNAME $DEADMASTER_HOST. --ttl 60
      
      # Add CNAME to newMaster
      # $GCLOUD dns record-sets transaction add $ZONE_PARAMS --name $PRIMARY_CNAME. --type CNAME $NEWMASTER_HOST. --ttl 60
      
      # Execute Transaction
      # $GCLOUD dns record-sets transaction execute $ZONE_PARAMS
      "
      exit
  fi
  
  # Exporting DNS Zone file
  $GCLOUD dns record-sets export $EXPORT_DNS_FILE $ZONE_PARAMS --zone-file-format 2>/dev/null
  [ $? -ne 0 ] && debug "Unable to export DNS Zone"
 
  return 0
}

#------------------------------------------------------------- postfailove --
postfailover() {
   
  # Make sure that newMaster DB is writable
  IS_WRITABLE=`$NODE_AUTH -h $NEWMASTER_HOST -P $NEWMASTER_PORT -NB -e"SELECT COUNT(1) FROM information_schema.global_variables WHERE variable_name = 'read_only' AND variable_value = 'OFF'"`
  [ $? -ne 0 ] && debug "Unable to check READ_ONLY status on '$DEADMASTER_HOST:$DEADMASTER_PORT'"
 
  [ $IS_WRITABLE -eq 0 ] && debug "'$DEADMASTER_HOST:$DEADMASTER_PORT' is showing READ_ONLY=ON. please check"
  
  # Switching DNS from deadMaster to newMaster
  # start transaction
  $GCLOUD dns record-sets transaction start $ZONE_PARAMS 2>/dev/null
  [ $? -ne 0 ] && debug "Unable to execute 'gcloud dns record-sets transaction start'"

  # Remove a CNAME from deadMaster if its added
  if [ `grep "$PRIMARY_CNAME" $EXPORT_DNS_FILE | grep "$DEADMASTER_HOST" |wc -l` -gt 0 ]
  then    
      $GCLOUD dns record-sets transaction remove $ZONE_PARAMS --name $PRIMARY_CNAME. --type CNAME $DEADMASTER_HOST. --ttl 60 2>/dev/null
      if [ $? -ne 0 ]
      then
          $GCLOUD dns record-sets transaction abort $ZONE_PARAMS 2>/dev/null
          debug "Unable to execute 'gcloud dns record-sets transaction remove'"
      fi
  fi    
  # Add a CNAME to newMaster
  $GCLOUD dns record-sets transaction add $ZONE_PARAMS --name $PRIMARY_CNAME. --type CNAME $NEWMASTER_HOST. --ttl 60 2>/dev/null
  if [ $? -ne 0 ] 
  then
      $GCLOUD dns record-sets transaction abort $ZONE_PARAMS 2>/dev/null
      debug "Unable to execute 'gcloud dns record-sets transaction add'"
  fi
  # complete transaction
  $GCLOUD dns record-sets transaction execute $ZONE_PARAMS 2>/dev/null
  if [ $? -ne 0 ]
  then
      $GCLOUD dns record-sets transaction abort $ZONE_PARAMS 2>/dev/null
      debug "Unable to execute 'gcloud dns record-sets transaction execute'"
  fi
  return 0
}
#---------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  postfailover
  return 0
}

main $*
