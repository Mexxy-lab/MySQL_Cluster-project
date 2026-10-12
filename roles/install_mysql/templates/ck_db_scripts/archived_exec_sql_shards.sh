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

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
HOST_FILE=/tmp/${SCRIPT_NAME}_hostfile.$$
TMP_FILE=/tmp/${SCRIPT_NAME}_tmpfile.$$


ADMIN_MYCNF=${HOME}/.admin.$$.cnf
cat > $ADMIN_MYCNF << EOL
!include /etc/my.cnf
[client]
user=$USER
password=$PASSWD
EOL

export ADMIN_AUTH="mysql --defaults-file=$ADMIN_MYCNF"

help(){
  echo "###############################################################################"
  echo ""
  echo "This script should be used to run queries against shard tables."
  echo ""
  echo "Usage:"
  echo ""
  echo "$SCRIPT_NAME.sh -s <SCHEMA> -f <SQL_FILE> [ -d <DATA_CENTER> -g <SHARD_GROUP> -n <INSTANCE_NUMBER> -p <PARALLELISM> -o 1 --outfile 1 --loaddata 1 ]"
  echo ""
  echo "  Required:"
  echo "      -s | --schema          SCHEMA GROUP (ie. numericId, cookieId)"
  echo ""
  echo "  Optional:"
  echo "      -d | --data-center     Data Center code (ie. cke, ckc)"
  echo "      -g | --group           Shard Group (ie. fldb, fodb, budb)"
  echo "      -h | --hostname        Hostname (ie. fldb001.us-central1)"
  echo "      -l | --logical-shards  No. of schema per shard (ie. 8, 64). Default is 8"
  echo "      -n | --instance-number Instance Number (ie 1,2,..16)"
  echo "      -t | --table-name      Table Name"
  echo "      -f | --file            SQL File (ie. OPS-XXXX.sql)"
  echo "      --outfile              To write the output of the sql to the file. This option also needs -t to be specified."
  echo "      --loaddata             To run LOAD DATA for given table. This option also needs -t to be specified."
  echo "      --from-table           To run LOAD DATA for given table. This option also needs -t to be specified."
  echo "      -p | --parallel        Parallelism (ie 2, 4, 8). Default is 32"
  echo "      -o | --osc             Online Schema Change (ie 1). Default is regular SQL Change."
  echo ""
  echo "  Example:"
  echo "      Regular SQL:"           
  echo "          $SCRIPT_NAME.sh -s numericId -f ops-1.sql" 
  echo ""
  echo "      Online-Schema-Change:"  
  echo "          $SCRIPT_NAME.sh -s numericId -f ops-1.sql --osc"
  echo ""
  echo "      Targeting shards:"      
  echo "          $SCRIPT_NAME.sh -d ckw -g fodb -n 1-16 -s numericId -f ops-1.sql --parallel 2"
  echo ""
  echo "      To Outfile from SQL file (ie. raw data or to generate delete/update statements):"
  echo "          $SCRIPT_NAME.sh -d ckw -g fodb -s numericId -t tablename --outfile 1 -f ops-1.sql"
  echo ""
  echo "      Load data INFILE (files should be exist before running this command):"
  echo "          $SCRIPT_NAME.sh -d ckw -g fodb -s numericId -t tablename --loaddata 1 --from-table tablename"
  echo ""
  echo "      Apply per shard SQL files (ie. run delete/update statements) (files should be exist before running this command):"
  echo "          $SCRIPT_NAME.sh -d ckw -g fodb -s numericId -t tablename"
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
      if [[ ${args[$i]:0:1} == "-" && ${args[$i+1]:0:1} != "-" ]]
      then
          case ${args[$i]} in
              -d | --data-center )       V_DATA_CENTER=${args[$i+1]};;
              -g | --group )             V_GROUP=${args[$i+1]};;
              -n | --instance-number )   V_INSTANCE_NUMBER=${args[$i+1]};;
              -s | --schema )            V_SCHEMA=${args[$i+1]};;
              -f | --file )              V_SQL_FILE=${args[$i+1]};;
              -t | --table-name )        V_TABLE_NAME=${args[$i+1]};;
              -h | --hostname )          V_HOSTNAME=${args[$i+1]};;
              -l | --logical-shards )    V_LOGICAL_SHARDS=${args[$i+1]};;
              -p | --parallel )          V_PARALLEL=${args[$i+1]};;
              --outfile )                V_OUTFILE="Y";;
              --loaddata )               V_LOADDATA="Y";;
              --from-table )             V_FROM_TABLE=${args[$i+1]};;
              -o | --osc )               V_OSC="Y";;
              *)                         echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      else
          case ${args[$i]} in
              --outfile )                V_OUTFILE="Y";;
              --loaddata )               V_LOADDATA="Y";;
              -o | --osc )               V_OSC="Y";;
          esac
          i=$(($i+1))
      fi
  done
 
  SHARD_GROUPS="fldb fodb budb"

  [ -z "${V_SCHEMA}" ] && echo "Please specify 'Schema Group' for -s option. Please see --help for help." && exit 1
  [ ! -z "${V_DATA_CENTER}" ] && [ -z "${V_GROUP}" ] && echo "Please specify 'Shard Group' for -g option. Please see --help for help." && exit 1
  [ ! -z "${V_GROUP}" ] && [ -z "${V_DATA_CENTER}" ] && echo "Please specify 'Data Center' for -d option. Please see --help for help." && exit 1
  ! [[ $SHARD_GROUPS =~ $V_GROUP ]] && echo "Allowed Shard group names are 'fldb', 'fodb', or 'budb'. Please see --help for help." && exit 1
  [ -z "${V_LOGICAL_SHARDS}" ] && V_LOGICAL_SHARDS=8
  [ -z "${V_OSC}" ] && V_OSC="N"
  [[ -z "${V_PARALLEL}" || $V_PARALLEL -eq 0 ]] && V_PARALLEL=1
  [[ $V_PARALLEL -gt 8 ]] && V_PARALLEL=8
  [ ! -z "${V_OUTFILE}" ] && [ ! -z "${V_LOADDATA}" ] && echo "Both --outfile and --loaddata options not allowed togather." && exit 1
  [ ! -z "${V_OUTFILE}" ] && [ -z "${V_TABLE_NAME}" ] && echo "--outfile should be used injuction with -t option." && exit 1
  [ ! -z "${V_LOADDATA}" ] && [ -z "${V_TABLE_NAME}" ] && [ -z "${V_FROM_TABLE}" ] && echo "--loaddata should be used injuction with -t and --from-table options." && exit 1
  [ ! -z "${V_LOADDATA}" ] && [ ! -z "${V_SQL_FILE}" ]  && echo "--loaddata can not be used with -f option. Please see --help for help" && exit 1
  
  RANGE=""
  [ ! -z "${V_DATA_CENTER}" ] && DCENTERS=`echo $V_DATA_CENTER | sed "s/,/','/g"` && RANGE="where dataCenter in ('$DCENTERS')"
  [ ! -z "${V_GROUP}" ] && GRPS=`echo $V_GROUP | sed "s/,/','/g"` && RANGE="$RANGE and groupName in ('$GRPS')"
  [ ! -z "${V_INSTANCE_NUMBER}" ] && RANGE="$RANGE and shardNumber in (`echo $V_INSTANCE_NUMBER | awk 'BEGIN { RS=","; FS="-"; ORS="" } NR > 1 { print "," } NF > 1  { for (i=$1; i<$2; ++i) { print i "," } print $2; next } { print $1 }'`)"
  [ ! -z "${V_HOSTNAME}" ] && HOSTS=`echo $V_HOSTNAME | sed "s/,/','/g"` && RANGE="$RANGE and hostname in ('$HOSTS')"

  # Targeting servers by finding out masters based on consul masterlock or by command line args.
  if [[ -z "${V_DATA_CENTER}" && -z "${V_GROUP}" ]]
  then
      echo "Populating target master list..."
      mysql -NB -e"select concat(instanceName, \":\", port, \":\", shardNumber) from $ADMIN_SCHEMA.$ADMIN_TABLE where groupname = 'fldb' group by port order by port" > $TMP_FILE
      [ ! -s $TMP_FILE ] && echo "No records found." && exit 1
      
      rm -f $HOST_FILE

      while read LINE
      do
          INSTANCENAME=`echo $LINE | cut -d":" -f1`
          PORT=`echo $LINE | cut -d":" -f2`
          SHARDNUMBER=`echo $LINE | cut -d":" -f3`
  
          SESSION_ID_WITH_LOCK=$(curl -s http://127.0.0.1:8500/v1/kv/masterlock/$INSTANCENAME/.lock | python -m json.tool | grep Session | cut -f4 -d'"')
          [ "$SESSION_ID_WITH_LOCK" = "" ] && echo "ERROR: masterlock not found for $INSTANCENAME. Please try again" && exit 1

          MASTER_HOST=$(curl -s http://127.0.0.1:8500/v1/session/info/${SESSION_ID_WITH_LOCK} | python -m json.tool |grep Node | cut -f4 -d '"')
          [ "$MASTER_HOST" = "" ] && echo "ERROR: masterhost not found for $INSTANCENAME. Please try again" && exit 1
          
          echo "$MASTER_HOST:$PORT:$SHARDNUMBER" >> $HOST_FILE 
      done < $TMP_FILE
  else
      mysql -NB -e"select concat(fqdn, \":\", port, \":\", shardNumber) from $ADMIN_SCHEMA.$ADMIN_TABLE $RANGE" > $HOST_FILE
      [ ! -s $HOST_FILE ] && echo "Please check if 'Data Center' and/or 'Shard Group' is valid." && exit 1
  fi
  
  return 0
}

#-------------------------------------------------------------- execute_sql --
execute_sql() {

  CURRENT_DIR=`pwd`
  #SQL_FILE=$CURRENT_DIR/${V_SQL_FILE}
  WRAPPER_FILE=$CURRENT_DIR/execute-load.sh
 
  [ -f $V_SQL_FILE ] && SQL_FILE=$V_SQL_FILE

  echo "SQL(s)"
  echo "---------------------------------------------------------------------------------------------------------"
  if [[ ! -z $V_LOADDATA && ! -z $V_TABLE_NAME  && ! -z $V_FROM_TABLE ]]
  then
      echo "Load data local INFILE '/var/log/mysql_export/${V_FROM_TABLE}_${V_SCHEMA}_XXXX.out' into table $V_TABLE_NAME;"
  
  elif [[ ! -z $V_OUTFILE && -f $V_SQL_FILE ]]
  then
      echo "`cat $SQL_FILE` (into outfile)"
  elif [ -f $SQL_FILE ] 
  then
      cat $SQL_FILE
  fi
  echo "---------------------------------------------------------------------------------------------------------"

cat > $WRAPPER_FILE << EOL
#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
COMMON_FUNC_FILE="${SCRIPT_DIR}/common_functions.sh"

. \${COMMON_FUNC_FILE}

RED=\`tput setaf 1\`
GREEN=\`tput setaf 2\`
NOCOLOR='\e[0m'

CURRENT_DIR=\`pwd\`

# notify mysql-change-log slack channel                                                                                                                                      
if [[ ! -z "${V_SQL_FILE}" && `cat $V_SQL_FILE |grep -i "password\|identified" |wc -l` -eq 0 ]] 
then
    mysql_change_log "$SCRIPT_NAME.sh $options [command(s): `cat $V_SQL_FILE`]" 
else
    mysql_change_log "$SCRIPT_NAME.sh $options"
fi

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
      
      TOTAL_SCHEMA=""
      TOTAL_SCHEMA=`$ADMIN_AUTH -NB -h$HOSTNAME -P$PORT -e"SHOW DATABASES LIKE '${V_SCHEMA}%'"`
      
      if [ "$TOTAL_SCHEMA" != "" ]
      then
          FILENUM=$(( $PORT % $V_PARALLEL ))
          CMD_FILE=$CURRENT_DIR/run_shard_${HOSTNAME}_$FILENUM_$$.sh
          LOG_FILE=$CURRENT_DIR/run_shard_${HOSTNAME}_$FILENUM_$$.log
          echo "" >> $CMD_FILE 
          
          for DBNAME in $TOTAL_SCHEMA
          do
      	     echo "$DBNAME"
             echo "echo \`date \"+%Y-%m-%d %H:%M:%S\"\` 'SQL for $HOSTNAME($PORT):$DBNAME running...'" >> $CMD_FILE
         
             if [ ! -z "${V_LOADDATA}" ] 
             then
                 OUTPUT_FILE="/var/log/mysql_export/${V_FROM_TABLE}_${DBNAME}.out"
         
             elif [ ! -z "${V_OUTFILE}" ] 
             then
                 OUTPUT_FILE="/var/log/mysql_export/${V_TABLE_NAME}_${DBNAME}.out"
         
             elif [ -f $SQL_FILE ]
             then
                 OUTPUT_FILE=$SQL_FILE
             fi

             if [ "$V_OSC" != "Y" ]
             then
                 #1. outfile to the sql format as per give sql file
                 if [[ ! -z $V_OUTFILE && -f $V_SQL_FILE ]]
                 then
                     echo "$ADMIN_AUTH -NB -h$HOSTNAME -P$PORT -A $DBNAME < $SQL_FILE > $OUTPUT_FILE " >> $CMD_FILE

                 #2. load data from file
                 elif [ ! -z $V_LOADDATA ]
                 then
                     echo "$ADMIN_AUTH -vvv -h$HOSTNAME -P$PORT -A $DBNAME -e \"load data local infile '$OUTPUT_FILE' into table $V_TABLE_NAME\" " >> $CMD_FILE
             
                 #3. Apply per shard sql file
                 else
                     echo "$ADMIN_AUTH -vvv -h$HOSTNAME -P$PORT -A $DBNAME < $OUTPUT_FILE " >> $CMD_FILE
                 fi
             else
                 SQL=`cat $SQL_FILE |tr '\n' ' ' |sed 's/;//g'`
                 TABLENAME=`echo $SQL | cut -d' ' -f3 | sed 's/\`//g'`
                 STMT=`echo $SQL | cut -d' ' -f4-`
                 echo "/usr/bin/pt-online-schema-change --execute --alter-foreign-keys-method=none --no-check-replication-filters --recurse=0 --alter '$STMT' h=$HOSTNAME,u=$USER,p=$PASSWD,P=$PORT,D=$DBNAME,t=$TABLENAME" >> $CMD_FILE
             fi
         
             echo "if [ \$? -eq 0 ];then" >> $CMD_FILE
          	 echo "    echo \`date \"+%Y-%m-%d %H:%M:%S\"\` 'SUCCESS: SQL for $HOSTNAME($PORT):$DBNAME completed'" >> $CMD_FILE
             echo "else" >> $CMD_FILE
             echo "    echo \`date \"+%Y-%m-%d %H:%M:%S\"\` 'ERROR: SQL for $HOSTNAME($PORT):$DBNAME failed (bad exit code, see log).'" >> $CMD_FILE
             echo "fi" >> $CMD_FILE
             echo "" >> $CMD_FILE
             echo "" >> $CMD_FILE
         done
      fi
      chmod 700 $CMD_FILE
      [ `cat $WRAPPER_FILE |grep "$CMD_FILE" |wc -l` -eq 0 ] && echo "sh $CMD_FILE >> $LOG_FILE 2>&1 &" >> $WRAPPER_FILE
  done < $HOST_FILE
  
cat >> $WRAPPER_FILE << EOL
echo "\`date \"+%Y-%m-%d %H:%M:%S\"\` All threads Started..."

progress

wait

echo "\`date \"+%Y-%m-%d %H:%M:%S\"\` All threads Done."

SUCCESS=\`cat run_shard_*_$$.log |grep "SUCCESS:" |wc -l\`
ERR=\`cat run_shard_*_$$.log |grep "ERROR:" |wc -l\`
echo "--------------"
printf "Total   : %4s\n" "\`cat \$CURRENT_DIR/run_shard*_$$.sh |grep -v "^#" |grep running |wc -l\`"
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
  execute_sql
  return 0
}

main $*
