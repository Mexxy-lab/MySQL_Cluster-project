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
# Author : Nived
# Purpose: This script should be used to create new schemas in shards. 
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"
COMMON_FUNC_FILE="${SCRIPT_DIR}/common_functions.sh"

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
HOST_FILE=/tmp/${SCRIPT_NAME}_hostfile.$$
TMP_FILE=/tmp/${SCRIPT_NAME}_tmpfile.$$

help(){
  echo "###############################################################################"
  echo ""
  echo "This script should be used to manage schemas on shards."
  echo ""
  echo "Usage:"
  echo ""
  echo "$SCRIPT_NAME.sh -s <SCHEMA> [ -d <DATA_CENTER> -g <SHARD_GROUP> ]"
  echo ""
  echo "  Required:"
  echo "      -r    role"
  echo "      -s    Schema Name (ie. numericId, cookieId)"
  echo "      -c    Create/Drop"
  echo ""
  echo "  Optional:"
  echo "      -d    Data Center code (ie. ckw, rs)"
  echo "      -g    Shard Group (ie. fldb, fodb, budb)"
  echo ""
  echo "  Example:" 
  echo "      Regular:"
  echo "          $SCRIPT_NAME -s numericId"
  echo ""
  echo "      Targeting shards:"
  echo "          $SCRIPT_NAME.sh -d ckw -g fodb -s numericId"
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
             -r | --role )              V_ROLE=${args[$i+1]};;
             -g | --group )             V_GROUP=${args[$i+1]};;
             -s | --schema )            V_SCHEMA=${args[$i+1]};;
             -c | --command )           V_COMMAND=${args[$i+1]};;
             *)                         echo "Invalid option '${args[$i]}'" && exit 1;;
        esac
    fi
    i=$(($i+2))
  done

  SHARD_GROUPS=`mysql -NB -e"select group_concat(distinct groupName) from $ADMIN_SCHEMA.$ADMIN_TABLE where role like '%shard%'"|sed -e "s/,/ /g"`
  SHARD_ROLES=`mysql -NB -e"select group_concat(distinct role) from $ADMIN_SCHEMA.$ADMIN_TABLE where role like '%shard%'"|sed -e "s/,/ /g"`

  [ -z "${V_SCHEMA}" ] && echo "Please specify 'Schema Group' for -s option. Please see --help for help." && exit 1
  [ -z "${V_COMMAND}" ] && echo "Please specify Command Create/Drop. Please see --help for help." && exit 1
  [ ! -z "${V_DATA_CENTER}" ] && [ -z "${V_GROUP}" ] && echo "Please specify 'GroupName' for -g option. Please see --help for help." && exit 1
  [ ! -z "${V_GROUP}" ] && [ -z "${V_DATA_CENTER}" ] && echo "Please specify 'Data Center' for -d option. Please see --help for help." && exit 1
  ! [[ $SHARD_GROUPS =~ $V_GROUP ]] && echo "Allowed Shard group names are $SHARD_GROUPS. Please see --help for help." && exit 1                                 
  ! [[ $SHARD_ROLES =~ $V_ROLE ]] && echo "Allowed Shard roles are $SHARD_ROLES. Please see --help for help." && exit 1

  SCHEMA_CHECK=`mysql -NB -e"select count(*) from ${ADMIN_SCHEMA}.schema_info where schemaName = '${V_SCHEMA}' and isSharded = 'Y'"`

  if [[ $SCHEMA_CHECK -eq 0 ]]; then
    echo "Invalid Schema name provided. Please make sure that the schema name is added to schema_info"
    exit 99;
  fi
  if [[ -z "${V_DATA_CENTER}" && -z "${V_GROUP}" ]]
  then

    current_dc=`salt-call grains.get ck_datacenter`
    active_dc=`salt-call pillar.get active_datacenter`

    if [[ $current_dc != $active_dc ]]; then
    echo "Cannot execute the script from Inactive DC. Please execute the script from $active_dc"
    exit 99;
    fi
  fi

}

calculate_shards(){

  LOGICAL_SHARDS=`mysql -NB -e"select numOfschema from ${ADMIN_SCHEMA}.schema_info where schemaName = '${V_SCHEMA}' and isSharded = 'Y'"`

  #HOST_COUNT=`mysql -NB -e"select count(distinct hostName) from $ADMIN_SCHEMA.$ADMIN_TABLE where groupname = '${V_GROUP}' and datacenter = '${V_DATA_CENTER}'"`
  if [[ -z "${V_DATA_CENTER}" && -z "${V_GROUP}" ]]
  then
    INSTANCE_COUNT=`mysql -NB -e"select count(distinct instanceName) from $ADMIN_SCHEMA.$ADMIN_TABLE where role = '${V_ROLE}'"`

    #INSTANCE_PER_HOST=$(( $INSTANCE_COUNT / $HOST_COUNT ))
    SCHEMA_TOTAL=$( echo "scale=3; $LOGICAL_SHARDS / $INSTANCE_COUNT"|bc)

    COUNT_CHECK=$(echo "$SCHEMA_TOTAL < 1" | bc -l)

    if [[ $COUNT_CHECK == 1 ]]; then

      DIFF_SCHEMA=$( echo "scale=3; 1 - $SCHEMA_TOTAL "|bc)

      #Generating the schema mapping with hostnames
      mysql -NB -e"select concat(t.instanceName, \":\", t.port, \":\", t.shardNumber, \":\",round(t.MIN_SCHEMA), \":\",round(t.MAX_SCHEMA)) from (select instanceName, port, shardNumber, ($SCHEMA_TOTAL * shardNumber - $SCHEMA_TOTAL) AS MIN_SCHEMA, ($SCHEMA_TOTAL * shardNumber - 1 + $DIFF_SCHEMA) AS MAX_SCHEMA from $ADMIN_SCHEMA.$ADMIN_TABLE where role = '${V_ROLE}' group by instanceName order by shardNumber) t where t.MIN_SCHEMA = floor(t.MIN_SCHEMA);" >>$TMP_FILE
    
    else
      mysql -NB -e"select concat(t.instanceName, \":\", t.port, \":\", t.shardNumber, \":\",round(t.MIN_SCHEMA), \":\",round(t.MAX_SCHEMA)) from (select instanceName, port, shardNumber, ($SCHEMA_TOTAL * shardNumber - $SCHEMA_TOTAL) AS MIN_SCHEMA, ($SCHEMA_TOTAL * shardNumber - 1) AS MAX_SCHEMA from $ADMIN_SCHEMA.$ADMIN_TABLE where role = '${V_ROLE}' group by instanceName order by shardNumber) t where t.MIN_SCHEMA = floor(t.MIN_SCHEMA);" >>$TMP_FILE
    fi

  else

    INSTANCE_COUNT=`mysql -NB -e"select count(distinct instanceName) from $ADMIN_SCHEMA.$ADMIN_TABLE where groupname = '${V_GROUP}' and datacenter = '${V_DATA_CENTER}'"`
    #INSTANCE_PER_HOST=$(( $INSTANCE_COUNT / $HOST_COUNT ))
    SCHEMA_TOTAL=$( echo "scale=3; $LOGICAL_SHARDS / $INSTANCE_COUNT"|bc)

    COUNT_CHECK=$(echo "$SCHEMA_TOTAL < 1" | bc -l)

    if [[ $COUNT_CHECK == 1 ]]; then

      DIFF_SCHEMA=$( echo "scale=3; 1 - $SCHEMA_TOTAL "|bc)

      #Generating the schema mapping with hostnames
      mysql -NB -e"select concat(t.fqdn, \":\", t.port, \":\", t.shardNumber, \":\",round(t.MIN_SCHEMA), \":\",round(t.MAX_SCHEMA)) from (select fqdn, port, shardNumber, ($SCHEMA_TOTAL * shardNumber - $SCHEMA_TOTAL) AS MIN_SCHEMA, ($SCHEMA_TOTAL * shardNumber - 1 + $DIFF_SCHEMA) AS MAX_SCHEMA from $ADMIN_SCHEMA.$ADMIN_TABLE where groupname = '${V_GROUP}' and datacenter = '${V_DATA_CENTER}') t where t.MIN_SCHEMA = floor(t.MIN_SCHEMA);" >>$HOST_FILE
    
    else
      mysql -NB -e"select concat(t.fqdn, \":\", t.port, \":\", t.shardNumber, \":\",round(t.MIN_SCHEMA), \":\",round(t.MAX_SCHEMA)) from (select fqdn, port, shardNumber, ($SCHEMA_TOTAL * shardNumber - $SCHEMA_TOTAL) AS MIN_SCHEMA, ($SCHEMA_TOTAL * shardNumber - 1) AS MAX_SCHEMA from $ADMIN_SCHEMA.$ADMIN_TABLE where groupname = '${V_GROUP}' and datacenter = '${V_DATA_CENTER}') t where t.MIN_SCHEMA = floor(t.MIN_SCHEMA);" >>$HOST_FILE

    fi 

  fi

if [[ -z "${V_DATA_CENTER}" && -z "${V_GROUP}" ]]

then

while read LINE 
do
    INSTANCENAME=$(echo $LINE | cut -d':' -f1)
    PORT=$(echo $LINE | cut -d':' -f2)
    SHARD_NUM=$(echo $LINE | cut -d':' -f3)
    MIN_SCHEMA=$(echo $LINE | cut -d':' -f4)
    MAX_SCHEMA=$(echo $LINE | cut -d':' -f5)
    
    SESSION_ID_WITH_LOCK=$(curl -s http://127.0.0.1:8500/v1/kv/masterlock/$INSTANCENAME/.lock 2>/dev/null | python -m json.tool | grep Session)
    [ $? -ne 0 ] && echo -e "${RED}Error getting master hosts. Exiting ..... ${NOCOLOR}" && exit 9
    SESSION_ID=`echo $SESSION_ID_WITH_LOCK| cut -f4 -d'"'`
    if [ "$SESSION_ID" != "" ]
    then
        MASTER_HOST=$(curl -s http://127.0.0.1:8500/v1/session/info/${SESSION_ID} 2>/dev/null | python -m json.tool |grep Node | cut -f4 -d '"')
        if [ "$MASTER_HOST" != "" ] 
        then
            echo "$MASTER_HOST:$PORT:$SHARD_NUM:$MIN_SCHEMA:$MAX_SCHEMA" >> $HOST_FILE 
        fi    
    fi      
done < $TMP_FILE

fi

}

gen_query() {

    V_COMMAND=`echo "${V_COMMAND^^}"`

    if [[ "${V_COMMAND}" = "CREATE" ]]; then
        QRY="CREATE DATABASE IF NOT EXISTS"

    elif [[ "${V_COMMAND}" = "DROP" ]]; then
        cat $HOST_FILE|while read LINE

        do                                                                                                                                                                                                                                                                     

          HOST=`echo $LINE | cut -d":" -f1`
          PORT=`echo $LINE | cut -d":" -f2`
          SHARDNUM=`echo $LINE | cut -d":" -f3`
          table_count=0+$table_count
          table_count=`mysql -u$USER -p$PASSWD -h$HOST -P$PORT -NB -e"SELECT COUNT(*) FROM information_schema.tables where table_schema like '${V_SCHEMA}_____'"`

        done

            if [[ $table_count -eq 0 ]]; then
             QRY="DROP DATABASE IF EXISTS"
            else                                                                                                                                                                                                                                                               
                echo "Database on $HOST:$PORT is not Empty"
                exit 1;
            fi

    else
    echo "Invalid Command $V_COMMAND. Valid options are create/drop"
    exit 1;

    fi

}


#-------------------------------------------------------------- execute_sql --
execute_sql() {

  CURRENT_DIR=`pwd`
  WRAPPER_FILE=$CURRENT_DIR/execute-load.sh
  #QRY="CREATE DATABASE IF NOT EXISTS" 
  echo "SQL(s)"
  echo "---------------------------------------------------------------------------------------------------------"
  echo "$QRY ${V_SCHEMA}_xxxx"
  echo "---------------------------------------------------------------------------------------------------------"

cat > $WRAPPER_FILE << EOL
#!/bin/bash

RED=\`tput setaf 1\`
GREEN=\`tput setaf 2\`
NOCOLOR='\e[0m'

. ${COMMON_FUNC_FILE}

# notify mysql-change-log slack channel
mysql_change_log "$SCRIPT_NAME.sh $options - shard_count: ${LOGICAL_SHARDS}"

CURRENT_DIR=\`pwd\`
progress() {
DONE=0
TOTAL=$LOGICAL_SHARDS
while [[ \$DONE -lt \$TOTAL ]]
do
    DONE=\`cat \$CURRENT_DIR/run_shard_*.log |grep Bye |wc -l\`
    PCT=\$(( \$DONE*100/\$TOTAL ))
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
      MIN_SCHEMA=`echo $LINE | cut -d":" -f4`
      MAX_SCHEMA=`echo $LINE | cut -d":" -f5`

     for i in `seq ${MIN_SCHEMA} ${MAX_SCHEMA}`

     do
     
       SCHEMA_NUM=`printf "%04d\n" "$i"`

      echo "$HOSTNAME($PORT)"
      
      CMD_FILE=$CURRENT_DIR/run_shard_$SHARDNUM.sh
      LOG_FILE=$CURRENT_DIR/run_shard_$SHARDNUM.log
      echo "" >> $CMD_FILE 
         DBNAME=${V_SCHEMA}_${SCHEMA_NUM}
         echo "echo \`date \"+%Y-%m-%d %H:%M:%S\"\` 'SQL for $DBNAME running...'" >> $CMD_FILE
         echo "mysql -vvv -u$USER -p$PASSWD -h$HOSTNAME -P$PORT -e\"$QRY $DBNAME;\" " >> $CMD_FILE
         echo "if [ \$? -eq 0 ];then" >> $CMD_FILE
         echo "    echo \`date \"+%Y-%m-%d %H:%M:%S\"\` 'SQL for $DBNAME completed'" >> $CMD_FILE
         echo "else" >> $CMD_FILE
         echo "    echo \`date \"+%Y-%m-%d %H:%M:%S\"\` 'ERROR: SQL for $DBNAME failed (bad exit code, see log).'" >> $CMD_FILE
         echo "fi" >> $CMD_FILE
         echo "" >> $CMD_FILE
         echo "" >> $CMD_FILE
      chmod 700 $CMD_FILE
    done
  done < $HOST_FILE

cat $HOST_FILE|cut -d ':' -f3|sort -nu|while read instance

do

  CMD_FILE=$CURRENT_DIR/run_shard_$instance.sh
  LOG_FILE=$CURRENT_DIR/run_shard_$instance.log
  echo "sh $CMD_FILE >> $LOG_FILE 2>&1 &" >> $WRAPPER_FILE

done
 
cat >> $WRAPPER_FILE << EOL
echo "\`date \"+%Y-%m-%d %H:%M:%S\"\` All threads Started..."

progress

wait

echo "\`date \"+%Y-%m-%d %H:%M:%S\"\` All threads Done."

SUCCESS=\`cat run_shard_*.log |grep "completed" |wc -l\`
ERR=\`cat run_shard_*.log |grep "ERROR:" |wc -l\`
echo "--------------"
printf "Total   : %4s\n" "\$TOTAL"
printf "\${GREEN}Success : %4s \${NOCOLOR}\n" "\$SUCCESS"
printf "\${RED}Failed  : %4s \${NOCOLOR}\n" "\$ERR"
echo "--------------"

EOL
 
  echo ""
  echo "Execute $WRAPPER_FILE to apply changes." 
  echo ""

  [ -f $HOST_FILE ] && rm -f $HOST_FILE
  [ -f $TMP_FILE ] && rm -f $TMP_FILE
}
#----------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  calculate_shards
  gen_query
  
  if [[ $? != 0 ]]; then
    exit 99;
  fi

  execute_sql
}

main $*
