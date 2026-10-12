#!/bin/bash
# =============================================================================
# {% for line in fileBanner %}
# {{line}} {% endfor %}
# =============================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
HOST_FILE=/tmp/hostfile.$$
TMP_FILE=/tmp/tmpfile.$$

help(){
  echo "###############################################################################"
  echo ""
  echo "This script should be used to run queries against shard tables."
  echo ""
  echo "Usage:"
  echo ""
  echo "sh $SCRIPT_NAME.sh -d <DATA_CENTER> -g <SHARD_GROUP> -s <SCHEMA> [ -i <INSTANCE_NUMBER> ]"
  echo ""
  echo "  Required:"
  echo "      -d    Data Center code (ie. ckw, rs)"
  echo "      -g    Shard Group (ie. fldb, fodb, budb)"
  echo "      -s    SCHEMA GROUP"
  echo ""
  echo "  Optional:"
  echo "      -i    Instance Number (ie 1,2,..16)"
  echo ""
  echo "  Example:" 
  echo "      sh $SCRIPT_NAME.sh -d ckw -g fldb -i 2"
  echo ""
  echo "###############################################################################"
  exit 1
}

#-------------------------------------------------------------- process_args --
process_args() {

  if [ "$*" == "--help" ] 
  then 
      help 
  fi 

  while getopts ":d:g:s:i:" OPTION
  do
    case "$OPTION" in
      d)  DCENTER=${OPTARG};;
      g)  SHARD_GROUP=${OPTARG};;
      s)  SCHEMA_GROUP=${OPTARG};;
      i)  INSTANCE_NUM=${OPTARG};;
      \?) echo "" && echo "Invalid option -$OPTARG specified at command argument" && help ;;
      :)  echo "" && echo "Option -$OPTARG requires an argument" && help ;; 
    esac
  done
  shift `expr ${OPTIND} - 1`

  [ -z "${DCENTER}" ] && echo "Please specify 'Data Center' for -d option." && help
  [ -z "${SHARD_GROUP}" ] && echo "Please specify 'Shard Group' for -g option" && help
  [ -z "${SCHEMA_GROUP}" ] && echo "Please specify 'Schema Group' for -s option" && help

  RANGE=""
  [ ! -z "${INSTANCE_NUM}" ] && RANGE="and shardNumber in (`echo $INSTANCE_NUM | awk 'BEGIN { RS=","; FS="-"; ORS="" } NR > 1 { print "," } NF > 1  { for (i=$1; i<$2; ++i) { print i "," } print $2; next } { print $1 }'`)"

  mysql -NB -e"select concat(hostName, \":\", ipAddress, \":\", port, \":\", shardNumber) from $ADMIN_SCHEMA.$ADMIN_TABLE where dataCenter='$DCENTER' and groupName = '$SHARD_GROUP' $RANGE" > $HOST_FILE
  [ ! -s $HOST_FILE ] && echo "Please check if 'Data Center' and/or 'Shard Group' is valid." && exit 1

  return 0
}


#-------------------------------------------------------------- execute_sql --
execute_sql() {

  QRY="select now();"
  echo $QRY
  echo ""
  read 
  while read LINE
  do
      HOSTNAME=`echo $LINE | cut -d":" -f1`
      IPADDR=`echo $LINE | cut -d":" -f2`
      PORT=`echo $LINE | cut -d":" -f3`
      SHARDNUM=`echo $LINE | cut -d":" -f4`
      
      MAX_SHARD=$(( $SHARDNUM * 64))
      MIN_SHARD=$(( $MAX_SHARD - 64))
      
      for ((i=$MIN_SHARD; i<$MAX_SHARD; i++))
      do
      	 SCHEMA_NUM=`printf "%04d\n" "$i"`
      	 DBNAME=${SCHEMA_GROUP}_${SCHEMA_NUM}
      	 echo "$DBNAME:"
         mysql -NB -u$USER -p$PASSWD -h$IPADDR -P$PORT -A $DBNAME -e"$QRY" > $TMP_FILE
      done
  done < $HOST_FILE

  cat $TMP_FILE | sort |tail -1
  [ -f $HOST_FILE ] && rm -f $HOST_FILE
  [ -f $TMP_FILE ] && rm -f $TMP_FILE
}
#----------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  execute_sql
  return 0
}

main $*
