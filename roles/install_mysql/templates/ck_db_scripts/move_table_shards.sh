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
# Purpose: This script should be used to run queries against shard tables. 
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"
COMMON_FUNC_FILE="${SCRIPT_DIR}/common_functions.sh"

. ${PARAMETER_FILE}
. ${COMMON_FUNC_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
HOST_FILE=/tmp/${SCRIPT_NAME}_hostfile.$$
TMP_FILE=/tmp/${SCRIPT_NAME}_tmpfile.$$

help(){
  echo "###############################################################################"
  echo ""
  echo "This script should be used to run queries against shard tables."
  echo ""
  echo "Usage:"
  echo ""
  echo "$SCRIPT_NAME.sh -d <DATA_CENTER> -g <GROUP_NAME> --from-schema <FROM_SCHEMA> --to-schema <TO_SCHEMA> [ -p <PARALLELISM> ]"
  echo ""
  echo "  Required:"
  echo "      --from-schema          From SCHEMA GROUP (ie. numericId, cookieId)"
  echo "      --to-schema            To SCHEMA GROUP (ie. numericId, cookieId)"
  echo "      -d | --data-center     Data Center code (ie. ckw, rs)"
  echo "      -g | --group           Shard Group (ie. fldb, fodb, budb)"
  echo "      -l | --logical-shards  No. of schema per shard (ie. 8, 64). Default is 8"
  echo "      -n | --instance        Instance number"
  echo "      -t | --table-name      Table Name"
  echo ""
  echo "  Example:"
  echo "      Regular SQL:"           
  echo "          $SCRIPT_NAME.sh -d ckw -g fldb -t tablename --from-schema schemaname --to-schema schemaname" 
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
  
  for arg in $options
  do
     if [[ ${args[$i]} == "-"* || ${args[$i]} == "--"* ]] && [[ ${args[$i+1]} != "-"* || ${args[$i+1]} != "--"* ]] 
     then
        case ${args[$i]} in
             -d | --data-center )       V_DATA_CENTER=${args[$i+1]};;
             -g | --group )             V_GROUP=${args[$i+1]};;
             --from-schema )            V_FROM_SCHEMA=${args[$i+1]};;
             --to-schema )            V_TO_SCHEMA=${args[$i+1]};;
             -t | --table-name )        V_TABLE_NAME=${args[$i+1]};;
             -l | --logical-shards )    V_LOGICAL_SHARDS=${args[$i+1]};;
             -n | --instance )          V_INSTANCE_NUMBER=${args[$i+1]};;
             -p | --parallel )          V_PARALLEL=${args[$i+1]};;
             *)                         echo "Invalid option '${args[$i]}'" && exit 1;;
        esac
    fi
    i=$(($i+2))
  done
 
  [ -z "${V_FROM_SCHEMA}" ] && echo "Please specify 'From Schema Name' for -s option. Please see --help for help." && exit 1
  [ -z "${V_TO_SCHEMA}" ] && echo "Please specify 'To Schema Name' for -s option. Please see --help for help." && exit 1
  [ -z "${V_DATA_CENTER}" ] && echo "Please specify 'Data Center' for -d option. Please see --help for help." && exit 1
  [ -z "${V_GROUP}" ] && echo "Please specify 'Shard Group' for -g option. Please see --help for help." && exit 1
  [ -z "${V_LOGICAL_SHARDS}" ] && V_LOGICAL_SHARDS=8
  [[ -z "${V_PARALLEL}" || $V_PARALLEL -eq 0 ]] && V_PARALLEL=1
  [[ $V_PARALLEL -gt 8 ]] && V_PARALLEL=8
  
RANGE=""                                                                                                                                                                                    
  [ ! -z "${V_DATA_CENTER}" ] && DCENTERS=`echo $V_DATA_CENTER | sed "s/,/','/g"` && RANGE="where dataCenter in ('$DCENTERS')"
  [ ! -z "${V_GROUP}" ] && GRPS=`echo $V_GROUP | sed "s/,/','/g"` && RANGE="$RANGE and groupName in ('$GRPS')"
  [ ! -z "${V_INSTANCE_NUMBER}" ] && RANGE="$RANGE and shardNumber in (`echo $V_INSTANCE_NUMBER | awk 'BEGIN { RS=","; FS="-"; ORS="" } NR > 1 { print "," } NF > 1  { for (i=$1; i<$2; ++i) {
 print i "," } print $2; next } { print $1 }'`)"
  [ ! -z "${V_HOSTNAME}" ] && HOSTS=`echo $V_HOSTNAME | sed "s/,/','/g"` && RANGE="$RANGE and hostname in ('$HOSTS')"

  mysql -NB -e"select concat(fqdn, \":\", port, \":\", shardNumber) from $ADMIN_SCHEMA.$ADMIN_TABLE $RANGE" > $HOST_FILE
  [ ! -s $HOST_FILE ] && echo "Please check if 'Data Center' and/or 'Shard Group' is valid." && exit 1

  return 0

}

#-------------------------------------------------------------- execute_sql --
execute_sql() {

  CURRENT_DIR=`pwd`
  SQL_FILE=$CURRENT_DIR/${V_SQL_FILE}
  WRAPPER_FILE=$CURRENT_DIR/execute-load.sh
 
  echo "rename table ${V_FROM_SCHEMA}_XXXX.$V_TABLE_NAME to ${V_TO_SCHEMA}_XXXX.$V_TABLE_NAME"
  echo "---------------------------------------------------------------------------------------------------------"

cat > $WRAPPER_FILE << EOL
#!/bin/bash

RED=\`tput setaf 1\`
GREEN=\`tput setaf 2\`
NOCOLOR='\e[0m'

CURRENT_DIR=\`pwd\`
progress() {
DONE=0
while [ \$DONE -lt \`cat \$CURRENT_DIR/run_shard*.sh |grep -v "^#" |grep running |wc -l\` ]
do
    DONE=\`cat \$CURRENT_DIR/run_shard_*.log |grep "ERROR:\|SUCCESS:" |wc -l\`
    PCT=\$(( \$DONE*100/\`cat \$CURRENT_DIR/run_shard*.sh |grep -v "^#" |grep running |wc -l\` ))
    printf "\`date \"+%Y-%m-%d %H:%M:%S\"\` SQLs completed %3d%%\n" "\$PCT"
    sleep 1
done
}
echo "\`date \"+%Y-%m-%d %H:%M:%S\"\` Starting the Change..." 
EOL

  echo "Above SQL(s) will be applied on the list of below servers:"
  echo ""
  
  while read LINE
  do
      HOSTNAME=`echo $LINE | cut -d":" -f1`
      PORT=`echo $LINE | cut -d":" -f2`
      SHARDNUM=`echo $LINE | cut -d":" -f3`
      
      MAX_SHARD=$(( $SHARDNUM * $V_LOGICAL_SHARDS ))
      MIN_SHARD=$(( $MAX_SHARD - $V_LOGICAL_SHARDS ))

      MIN_SCHEMA=`printf "%04d\n" "$MIN_SHARD"`
      MAX_SCHEMA=`printf "%04d\n" "$(( $MAX_SHARD-1 ))"`

      echo "$HOSTNAME($PORT) Shards: $MIN_SCHEMA-$MAX_SCHEMA" 
      
      FILENUM=$(( $PORT % $V_PARALLEL ))
      CMD_FILE=$CURRENT_DIR/run_shard_${HOSTNAME}_$FILENUM.sh
      LOG_FILE=$CURRENT_DIR/run_shard_${HOSTNAME}_$FILENUM.log
      echo "" >> $CMD_FILE 
      for ((i=$MIN_SHARD; i<$MAX_SHARD; i++))
      do
      	 SCHEMA_NUM=`printf "%04d\n" "$i"`
      	 FROM_DBNAME=${V_FROM_SCHEMA}_${SCHEMA_NUM}
      	 TO_DBNAME=${V_TO_SCHEMA}_${SCHEMA_NUM}
      	 echo "echo \`date \"+%Y-%m-%d %H:%M:%S\"\` 'SQL for $HOSTNAME($PORT):$FROM_DBNAME running...'" >> $CMD_FILE
         
         echo "mysql -vvv -u$USER -p$PASSWD -h$HOSTNAME -P$PORT -A $FROM_DBNAME -e\"rename table $FROM_DBNAME.$V_TABLE_NAME to $TO_DBNAME.$V_TABLE_NAME\"" >> $CMD_FILE
         
         echo "if [ \$? -eq 0 ];then" >> $CMD_FILE
      	 echo "    echo \`date \"+%Y-%m-%d %H:%M:%S\"\` 'SUCCESS: SQL for $HOSTNAME($PORT):$DBNAME completed'" >> $CMD_FILE
         echo "else" >> $CMD_FILE
         echo "    echo \`date \"+%Y-%m-%d %H:%M:%S\"\` 'ERROR: SQL for $HOSTNAME($PORT):$DBNAME failed (bad exit code, see log).'" >> $CMD_FILE
         echo "fi" >> $CMD_FILE
         echo "" >> $CMD_FILE
         echo "" >> $CMD_FILE
     done
     chmod 700 $CMD_FILE
     [ `cat $WRAPPER_FILE |grep "$CMD_FILE" |wc -l` -eq 0 ] && echo "sh $CMD_FILE >> $LOG_FILE 2>&1 &" >> $WRAPPER_FILE
  done < $HOST_FILE
  
cat >> $WRAPPER_FILE << EOL
echo "\`date \"+%Y-%m-%d %H:%M:%S\"\` All threads Started..."

progress

wait

echo "\`date \"+%Y-%m-%d %H:%M:%S\"\` All threads Done."

SUCCESS=\`cat run_shard_*.log |grep "SUCCESS:" |wc -l\`
ERR=\`cat run_shard_*.log |grep "ERROR:" |wc -l\`
echo "--------------"
printf "Total   : %4s\n" "\`cat \$CURRENT_DIR/run_shard*.sh |grep -v "^#" |grep running |wc -l\`"
printf "\${GREEN}Success : %4s \${NOCOLOR}\n" "\$SUCCESS"
printf "\${RED}Failed  : %4s \${NOCOLOR}\n" "\$ERR"
echo "--------------"

EOL
 
  echo ""
  echo "Execute $WRAPPER_FILE to apply changes." 
  echo ""

  # notify mysql-change-log slack channel
  mysql_change_log "$SCRIPT_NAME.sh $options"

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
