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
# Purpose: This script should be used to migrate shard ie. 1024 schema to 16 schema 
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
HOST_FILE=/tmp/${SCRIPT_NAME}_hostfile.$$
TMP_FILE=/tmp/${SCRIPT_NAME}_tmpfile.$$
FROM_LIST=/tmp/${SCRIPT_NAME}_from.$$
TO_LIST=/tmp/${SCRIPT_NAME}_to.$$
RESULT_FILE=/tmp/${SCRIPT_NAME}_result.$$
help(){
  echo "###############################################################################"
  echo ""
  echo "This script should be used to run queries against shard tables."
  echo ""
  echo "Usage:"
  echo ""
  echo "$SCRIPT_NAME.sh --from DATACENTER,SHARDLINE,SCHEMANAME,NUMBEROFSHARDS --to DATACENTER,SHARDLINE,SCHEMANAME,NUMBEROFSHARDS -t TABLENAME"
  echo ""
  echo "  Required:"
  echo "      --from                DataCenter,ShardLine,SchemaName,NumberOfShards (ie. cke,fldb,numericId,1024)"
  echo "      --to                  DataCenter,ShardLine,SchemaName,NumberOfShards (ie. cke,fldb,numericId,16)"
  echo "      -t | --tablename      Table Name"
  echo ""
  echo "  Optional:"
  echo "      -p | --parallel        Parallelism (ie 2, 4, 8). Default is 16"
  echo ""
  echo "  Example:"
  echo "          $SCRIPT_NAME.sh --from ckw,fldb,numericId,1024 --to ckw,fldb,numericId2,16 -t userTbl" 
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
             --from )                   V_FROM=${args[$i+1]};;
             --to )                     V_TO=${args[$i+1]};;
             -t | --tablename )         V_TABLENAME=${args[$i+1]};;
             -p | --parallel )          V_PARALLEL=${args[$i+1]};;
           *)                           echo "Invalid option '${args[$i]}'" && exit 1;;
        esac
    fi
    i=$(($i+2))
  done
 
  FROM_DATACENTER=`echo $V_FROM | cut -d ',' -f1`
  FROM_GROUPNAME=`echo $V_FROM | cut -d ',' -f2`
  FROM_SCHEMANAME=`echo $V_FROM | cut -d ',' -f3`
  FROM_LOGICAL_SHARDS=`echo $V_FROM | cut -d ',' -f4`

  TO_DATACENTER=`echo $V_TO | cut -d ',' -f1`
  TO_GROUPNAME=`echo $V_TO | cut -d ',' -f2`
  TO_SCHEMANAME=`echo $V_TO | cut -d ',' -f3`
  TO_LOGICAL_SHARDS=`echo $V_TO | cut -d ',' -f4`
 
  [[ $FROM_SCHEMANAME == $TO_SCHEMANAME ]] && echo "FROM_SCHEMANAME and TO_SCHEMANAME must be different. Exiting..." && exit 1
  [[ -z "${V_TABLENAME}" ]] && echo "Please specify Table Name" && exit 1
  [[ -z "${V_PARALLEL}" || $V_PARALLEL -eq 0 ]] && V_PARALLEL=16
  [[ $V_PARALLEL -gt 16 ]] && V_PARALLEL=16
 
  echo "`date \"+%Y-%m-%d %H:%M:%S\"` [Info] Preparing shard migration mapping..."
  # Prepare From list:

  cat /dev/null > $FROM_LIST
  mysql -NB -e"select concat(fqdn,\":\" ,port, \":\", shardnumber) from $ADMIN_SCHEMA.$ADMIN_TABLE where dataCenter = '$FROM_DATACENTER' and groupname = '$FROM_GROUPNAME' group by port order by shardnumber" 2>/dev/null > $TMP_FILE
  [ ! -s $TMP_FILE ] && echo "No records found." && exit 1
      
  if [ $FROM_LOGICAL_SHARDS -eq 1024 ]
  then
      FROM_PER_HOST_SHARDS=8
      while read LINE
      do
          HOST=`echo $LINE | cut -d':' -f1`
          PORT=`echo $LINE | cut -d':' -f2`
          SHARDNUMBER=`echo $LINE | cut -d':' -f3`

          MAX_SHARD=$(( $SHARDNUMBER * $FROM_PER_HOST_SHARDS ))
          MIN_SHARD=$(( $MAX_SHARD - $FROM_PER_HOST_SHARDS ))

          MIN_SCHEMA=`printf "%04d\n" "$MIN_SHARD"`
          MAX_SCHEMA=`printf "%04d\n" "$(( $MAX_SHARD-1 ))"`
      
          for ((i=$MIN_SHARD; i<$MAX_SHARD; i++))
          do
              SCHEMANUMBER=`printf "%04d\n" "$i"`
              printf "%s:%d:%s_%04d\n"  "$HOST" "$PORT" "$FROM_SCHEMANAME" "$i" >> $FROM_LIST
          done
      done < $TMP_FILE
  fi

  # Prepare TO list:

  cat /dev/null > $TO_LIST
  mysql -NB -e"select concat(fqdn,\":\" ,port, \":\", shardnumber) from $ADMIN_SCHEMA.$ADMIN_TABLE where dataCenter = '$TO_DATACENTER' and groupname = '$TO_GROUPNAME' group by port order by shardnumber" 2>/dev/null > $TMP_FILE                                                               
  [ ! -s $TMP_FILE ] && echo "No records found." && exit 1
      
  [[ $TO_LOGICAL_SHARDS -eq 1024 ]] && TO_PER_HOST_SHARDS=8
  [[ $TO_LOGICAL_SHARDS -eq 16 ]] && TO_PER_HOST_SHARDS=0.5
 
  j=0
  while read LINE
  do
      HOST=`echo $LINE | cut -d':' -f1`
      PORT=`echo $LINE | cut -d':' -f2`
      SHARDNUMBER=`echo $LINE | cut -d':' -f3`

      if [ $TO_LOGICAL_SHARDS -eq 16 ]
      then
          if (( $SHARDNUMBER % 8 == 1 )) 
          then
              printf "%s:%d:%s_%04d\n"  "$HOST" "$PORT" "$TO_SCHEMANAME" "$j" >> $TO_LIST 
              j=$(( $j+1 ))
          fi
      fi      
  done < $TMP_FILE

  # Generate final list

  NUM=1
  while read LINE1
  do
    FROM_HOST=`echo $LINE1 | cut -d':' -f1`
    FROM_PORT=`echo $LINE1 | cut -d':' -f2`
    FROM_SCHEMANUMBER=`echo $LINE1 | cut -d':' -f3 | awk -F"_" '{print $NF}' |bc`

    FILENUM=$(( $FROM_PORT % $V_PARALLEL  ))
    FINAL_LIST=/tmp/${SCRIPT_NAME}_runme_${FILENUM}.$$
    while read LINE2
    do
        TO_SCHEMANUMBER=`echo $LINE2 | cut -d':' -f3 | awk -F"_" '{print $NF}' |bc`
        if (( $FROM_SCHEMANUMBER % $TO_LOGICAL_SHARDS == $TO_SCHEMANUMBER ))
        then

          echo $LINE1:$LINE2 >> $FINAL_LIST
          break
        fi
    done < $TO_LIST
  done < $FROM_LIST
  
  rm -f $FROM_LIST $TO_LIST  
 
  return 0

}

#------------------------------------------------------------------- progress --
progress() {

DONE=0  
while [ $DONE -lt 1024 ]
do
    if [ -f $RESULT_FILE ]
    then
        DONE=`cat $RESULT_FILE |grep "IMPORT completed" |wc -l`
        PCT=$(( $DONE*100/1024 ))
        printf "`date \"+%Y-%m-%d %H:%M:%S\"` [Info] - Migration completed %3d%%\n" "$PCT"
    fi
    sleep 3
done
}
#----------------------------------------------------------------- f_migrator --
f_migrator() {

EXPORT_PATH=/db/data/backup
while read LINE
do
    FROM_HOST=`echo $LINE | cut -d':' -f1`
    FROM_PORT=`echo $LINE | cut -d':' -f2`
    FROM_SCHEMA=`echo $LINE | cut -d':' -f3`
    TO_HOST=`echo $LINE | cut -d':' -f4`
    TO_PORT=`echo $LINE | cut -d':' -f5`
    TO_SCHEMA=`echo $LINE | cut -d':' -f6`

    # Export
    EXPORT_FILE=/db/data/backup/${FROM_HOST}_${FROM_PORT}_${FROM_SCHEMA}_${V_TABLENAME}.dmp
    # echo "SET SESSION SQL_LOG_BIN=0;" > $EXPORT_FILE
    mysqldump -u$USER -p$PASSWD -h$FROM_HOST -P$FROM_PORT $FROM_SCHEMA $V_TABLENAME --no-create-info --set-gtid-purged=off --skip-add-locks 2>/dev/null >> $EXPORT_FILE 
    [ $? -eq 0 ] && echo "`date \"+%Y-%m-%d %H:%M:%S\"` [Info] Export completed from $FROM_HOST:$FROM_PORT:$FROM_SCHEMA" >> $RESULT_FILE 
   
    # Rename original table to _old and _new to original
    # Code here
 
    # Load
    mysql -NB -u$USER -p$PASSWD -h$TO_HOST -P$TO_PORT -A $TO_SCHEMA 2>/dev/null < $EXPORT_FILE
    if [ $? -eq 0 ] 
    then
        echo "`date \"+%Y-%m-%d %H:%M:%S\"` [Info] IMPORT completed on $TO_HOST:$TO_PORT:$TO_SCHEMA" >> $RESULT_FILE
    else
       echo "`date \"+%Y-%m-%d %H:%M:%S\"` [Info] IMPORT failed on $TO_HOST:$TO_PORT:$TO_SCHEMA" >> $RESULT_FILE
    fi   
done  < /tmp/$1
    
}
#------------------------------------------------------------------- migrator --
migrator() {

  
   DISP=/tmp/${SCRIPT_NAME}_display.$$
   # Display
   for file in `ls /tmp |grep $SCRIPT_NAME | grep runme | grep $$`
   do
       cat /tmp/$file >> $DISP
   done

   cat $DISP | sort |awk -F":" '{print $1 "(" $2 "):" $3 " -------> "$4 "(" $5 "):" $6}'
  
   echo "Do you want to contine(yes/no)?"
   read CONFIRM                                                                                                                                                                                
   [ "$CONFIRM" != "yes" ] && exit 1
 
   for file in `ls /tmp |grep $SCRIPT_NAME | grep runme | grep $$`
   do
      f_migrator $file &
   done
  
   progress
   
   wait
   echo "Done..."
   rm -f /tmp/${SCRIPT_NAME}_runme*
}
#----------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  migrator
  return 0
}

main $*
