#!/bin/bash

# =============================================================================
  {% for line in fileBanner %}
# {{line}} {% endfor %}
# =============================================================================

###############################################################################
#
# Author : Nived
# Usage  : sh dwnumericid_alert.sh -h <host> -r <range>
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

#---------------------------------------------------------------------- help --
help() {
  echo "###############################################################################"
  echo ""
  echo "Create an alert if the dw_numeric_id mapping is less than <range>."
  echo ""
  echo "Usage:"
  echo ""
  echo "sh $SCRIPT_NAME.sh -d <DATA_CENTER> "
  echo ""
  echo "  Required:"
  echo "      -h        Source Host"
  echo "      -r        Range"
  echo ""
  echo ""
  echo "  Example:" 
  echo "      sh $SCRIPT_NAME.sh -h <hostname> -r <range>"
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
             -h | --host  )       hostname=${args[$i+1]};;
             -r | --range )       range=${args[$i+1]};;
             *)                   echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      fi

  done

  return 0

}

fetch_info() {

    #Fetch Host details

    src=`mysql -NB -e"select concat(fqdn, \"|\", port) from ckadmin.host_info where hostName = '$hostname';"`
    source_host=`echo $src|cut -d '|' -f1`
    source_port=`echo $src|cut -d '|' -f2`

    #Get the max value of CK numericId since it is auto increment in Vault

    maxId_ck=`mysql -NB -u ${USER} -p${PASSWD} -h ${source_host} -P ${source_port} -e"select max(ckNumericId) from ck.dw_numeric_id where ckNumericId < '400000000';"`
    maxId_users=`mysql -NB -u ${USER} -p${PASSWD} -h ${source_host} -P ${source_port} -e"select max(numericId) from ck.users;"`

    remaining_id=`mysql -NB -e"select $maxId_ck - $maxId_users";`

    if [ "$remaining_id" -lt "$range" ];

    then

      python $SCRIPT_DIR/jira_dba_infsupport.py "dwNumericId mapping count less than ${range}" "Remaining dwNumericId mappings: $remaining_id . Populate more ids into dw_numeric_id table in ck and ck_ca schema."

    else

      echo "" >/dev/null

    fi

}


main()
{
process_args $*
fetch_info
}

main $*
