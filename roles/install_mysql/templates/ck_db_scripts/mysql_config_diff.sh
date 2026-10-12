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
# Auther : Nived
# Purpose:  Script to execute pt-config-diff per group
#
###############################################################################

date=`date +'%Y_%m_%d_%H%M%S'`
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
HOST_FILE=/tmp/${SCRIPT_NAME}_hostfile.$$
RESULT_FILE=/tmp/${SCRIPT_NAME}_resultfile.$$
LOGDIR=/var/log/dblogs

# colors
RED=`tput setaf 1`
GREEN=`tput setaf 2`
NOCOLOR='\e[0m'

#---------------------------------------------------------------------- help --
help() {
  echo "###############################################################################"
  echo ""
  echo "Script to execute pt-config-diff per group. For shards first instance will be compared with other instances"
  echo ""
  echo "Usage:"
  echo ""
  echo "sh $SCRIPT_NAME.sh -g <GROUP NAME> -s <SOURCE HOST> -t <TARGET HOST> -i <IGNORE>"
  echo ""
  echo "  Required:"
  echo "      -d        Target Datacenter"
  echo "      -g        Target Group name"
  echo "      -s        Source Host"
  echo "  Optional:"
  echo "      -t        Target Host"
  echo "      -n        Instance Number"
  echo "      -i        Ignore Variables during comparison. Hostname is ignored by default"
  echo ""
  echo ""
  echo "  Example:" 
  echo "      sh $SCRIPT_NAME.sh -g opsdb -s opsdb001.iad1 -t opsdb002.iad1 -i hostname"
  echo ""
  echo "###############################################################################"
  exit 1
}

#-------------------------------------------------------------- process_args --

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
             -d | --datacenter )         datacenter=${args[$i+1]};;
             -g | --target-group )       group=${args[$i+1]};;
             -s | --source_host  )       source_host=${args[$i+1]};;
             -t | --target_host )        target_host=${args[$i+1]};;
             -n | --instance )           instance_number=${args[$i+1]};;
             -i | --ignore)              ignore=${args[$i+1]};;
             *)                   echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      fi

  done

  return 0

}

fetch_hosts() {

  RANGE=""
  [ ! -z "${datacenter}" ] && DCENTERS=`echo $datacenter| sed "s/,/','/g"` && RANGE="where dataCenter in ('$DCENTERS')"
  [ ! -z "${group}" ] && GRPS=`echo $group | sed "s/,/','/g"` && RANGE=" $RANGE and groupName in ('$GRPS')"
  [ ! -z "${instance_number}" ] && RANGE="$RANGE and shardNumber in (`echo $instance_number | awk 'BEGIN { RS=","; FS="-"; ORS="" } NR > 1 { print "," } NF > 1  { for (i=$1; i<$2; ++i) { print i "," } print $2; next } { print $1 }'`)"
  [ ! -z "${target_host}" ] && HOSTS=`echo $target_host | sed "s/,/','/g"` && RANGE="$RANGE and hostname in ('$HOSTS')"

  mysql -NB -e"select concat(fqdn, \":\", port) from $ADMIN_SCHEMA.$ADMIN_TABLE $RANGE" > $HOST_FILE
  [ ! -s $HOST_FILE ] && echo "Please check if 'Data Center' and/or 'Shard Group' is valid." && exit 1

}

execute_diff() {

while read list

  target_host=`echo $list|cut -d ':' -f1`
  target_port=`echo $list|cut -d ':' -f2`

do

  source=`mysql -NB -e"select concat(fqdn, \":\", port) from $ADMIN_SCHEMA.$ADMIN_TABLE where hostName = '${source_host}' and port = '${target_port}'"`
  shost=`echo $source|cut -d ':' -f1`
  sport=`echo $source|cut -d ':' -f2`

  echo -e "$target_host \n"

  if [[ "${target_host}" == "" ]]
  then
    exit 0;

  else
  
    /usr/bin/pt-config-diff "u=${USER},p=${PASSWD},h=${shost},P=${sport}" "u=${USER},p=${PASSWD},h=${target_host},P=${target_port}" --report-width=200 --ignore-variables hostname,$ignore

    echo -e "\n"

  fi

done < $HOST_FILE

}


main()
{
process_args $*
fetch_hosts
execute_diff
}

main $*
