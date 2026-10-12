#!/bin/bash
# =============================================================================
#
# Purpose : Script to run compaction on Sharded MySQL Database 
# =============================================================================

#--------------------------------------------------------------------------help---

help(){
  echo '''
  This script is used for table compaction on Sharded MySQL DB
  
  Usage:
   sh db_compaction.sh -d cke -g budb 

  Optional:
    -n instance
    -s schema_prefix
  '''
}

#Variables

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="/usr/local/ops/bin/parameter.txt"
TS=`date +"%Y%m%d%H%M"`

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`

LOGDIR=/var/log/compaction/${TS}/logs
mkdir -p $LOGDIR

#Debug

debug() {
  if [ "$1" == "[Error]" ]
  then
      echo "$2 Exiting..."
      #rm -f $TMP_FILE $HOST_FILE $DONE_LIST $TOOLS_MYCNF $SOURCE_MYCNF $LOCAL_MYCNF $WRAPPER_FILE /tmp/${SCRIPT_NAME}_wrap_*.$$
      exit 1
  fi
}

#Read Arguments

process_args(){
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
             -d | --datacenter )    V_DC=${args[$i+1]};;
             -g | --group )         V_GROUP=${args[$i+1]};;
             -n | --instance )      V_INSTANCE=${args[$i+1]};;
             -s | --schema )        V_SCHEMA=${args[$i+1]};;
             -r | --resume )        V_RESUME=${args[$i+1]};; 
             *)                     echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      fi
  done  

  [ -z "${V_GROUP}" ] && debug "[Error]" "Please specify 'group' for -g | --group option. See --help for help." && exit 1
  [ -z "${V_DC}" ] && debug "[Error]" "Please specify 'datacenter' for -d | --datacenter option. See --help for help." && exit 1

  if [[ $V_RESUME != "" ]]
  then
  RESUME_CHECK=`mysql -NB -e"select count(1) from INFORMATION_SCHEMA.TABLES where table_schema='compaction' and table_name = '${V_RESUME}'"`

  if [[ $RESUME_CHECK -eq 0 ]]; then
    echo "Invalid Table name provided. Please make sure that the table exists on compaction database on opsdb"
    exit 99;
  fi
  fi

  if [[ -z "${V_INSTANCE}" ]]
  then
    FIRST_INSTANCE=1
  else
    FIRST_INSTANCE=`echo $V_INSTANCE | awk 'BEGIN { RS=""; FS="-"; ORS="" } NR > 1 { print "," }  { print $1 }'`
  fi
  
    METADATA_HOST=`mysql -NB -u$USER -p$PASSWD -h$LOCAL_OPSDB --connect_timeout=10 -e"select concat(fqdn,'|', port) from ckadmin.host_info where datacenter = '${V_DC}' and groupName = '$V_GR
OUP' and shardNumber = '$FIRST_INSTANCE'" 2>/dev/null` 
      
    METADATA_FQDN=`echo ${METADATA_HOST} |cut -d '|' -f1`
    METADATA_PORT=`echo ${METADATA_HOST} |cut -d '|' -f2`
    METADATA_TABNAME=${V_GROUP}_${V_DC}_compaction_${TS}

}

#-------------------------------CHECK FOR READ ONLY-------------------------------------------
#-------------------------------CHECK FOR VALID GROUP NAMES-----------------------------------
#-------------------------------CHECK FOR VALID DC--------------------------------------------
#-------------------------------CHECK FOR VALID INSTANCE--------------------------------------


compaction_prepare()
{
    TABLE="CREATE TABLE compaction.${METADATA_TABNAME} (id bigint(20) unsigned NOT NULL AUTO_INCREMENT, tableSchema varchar(255) NOT NULL, tableName varchar(255) NOT NULL,tableSizeBefore flo
at, tableSizeAfter float, dataCenter varchar(20), groupName varchar(20), startTime timestamp DEFAULT NULL, endTime timestamp DEFAULT NULL, status varchar(20) DEFAULT NULL, autoTS timestamp N
OT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (id),UNIQUE KEY (tableSchema, tableName), KEY autoTs (autoTs)) ENGINE=InnoDB DEFAULT CHARSET=latin1"

    if [[ -z "$V_SCHEMA" ]]

    then
        SCHEMALIST=`mysql -NB -u$USER -p$PASSWD -h$LOCAL_OPSDB --connect_timeout=10 -e"select distinct schemaName from ckadmin.schema_info where isSharded='Y'" 2>/dev/null`
    else
        SCHEMALIST=`mysql -NB -u$USER -p$PASSWD -h$LOCAL_OPSDB --connect_timeout=10 -e"select distinct schemaName from ckadmin.schema_info where isSharded='Y' and schemaName like '$V_SCHEMA%
'" 2>/dev/null`
    fi

    for SCHEMA in $SCHEMALIST

    do
        mysql -NB -u$USER -p$PASSWD -h $METADATA_FQDN -P $METADATA_PORT --connect_timeout=10 -e"select distinct concat('$SCHEMA,', table_name,',', ROUND(avg((DATA_LENGTH + INDEX_LENGTH) / 10
24 / 1024),1),',${V_DC},${V_GROUP}') from INFORMATION_SCHEMA.TABLES where engine = 'InnoDB' and table_type='BASE TABLE' and table_schema like '${SCHEMA}%' GROUP BY table_name;">>$LOGDIR/comp
action_tablist_${V_GROUP}_${TS}.dat 2>/dev/null
    done

    #Create table for compaction and load data
    mysql -NB -u$USER -p$PASSWD -h$LOCAL_OPSDB --connect_timeout=10 -e"${TABLE};LOAD DATA INFILE '$LOGDIR/compaction_tablist_${V_GROUP}_${TS}.dat' INTO TABLE compaction.${METADATA_TABNAME} F
IELDS TERMINATED BY ',' (tableSchema, tableName, tableSizeBefore, dataCenter, groupName);" 2>/dev/null

}

#------------------------------------------------Compaction for Single DB-------------

compaction_execute()
{

   # Check if DIR exists and exist if it is present -- to be added --

    mkdir -p $LOG_PATH/$V_DB/
    mkdir -p $SQL_PATH/$V_DB/
         
    TABLIST=`mysql -NB -u$USER -p$PASSWD -h$LOCAL_OPSDB --connect_timeout=10 -e"select distinct concat(tableSchema,'|',tableName) from compaction.${METADATA_TABNAME} WHERE status is NULL ord
er by tableSizeBefore asc"`
        for TAB in ${TABLIST}
        do

            SCHEMA=`echo $TAB |cut -d '|' -f1`
            TABLE=`echo $TAB |cut -d '|' -f2`
            start_time=`date +"%Y-%m-%d %H:%M:%S"`

            #update start time on opsdb
            mysql -NB -u$USER -p$PASSWD -h$LOCAL_OPSDB --connect_timeout=10 -e"UPDATE compaction.${METADATA_TABNAME} SET startTime='$start_time' WHERE tableSchema = '$SCHEMA' and tableName='
$TABLE'" 2>/dev/null
            
            if [[ -z "${V_INSTANCE}" ]]
            then
                exec_sql_shards.py -g $V_GROUP -d $V_DC -q -s $SCHEMA -e "set global super_read_only=0;set sql_log_bin=0;alter table $TABLE engine=innodb , lock=none ,algorithm=inplace;set g
lobal super_read_only=1;" -l $LOGDIR/${SCHEMA}_${TABLE}.log 
            else
                exec_sql_shards.py -g $V_GROUP -d $V_DC -q -n $V_INSTANCE -s $SCHEMA -e "set global super_read_only=0;set sql_log_bin=0;alter table $TABLE engine=innodb , lock=none ,algorith
m=inplace;set global super_read_only=1;" -l $LOGDIR/${SCHEMA}_${TABLE}.log
            
            rcode=`grep "ERROR|FAIL" ${LOGDIR}/${SCHEMA}_${TABLE}.log | wc -l`
            end_time=`date +"%Y-%m-%d %H:%M:%S"`
            fi

            if [[ $rcode -eq 0 ]]
            then 
               STATUS='SUCCESS'
            else
               STATUS='FAILED'
            fi   
                                                                                                 
            mysql -NB -u$USER -p$PASSWD -h$LOCAL_OPSDB --connect_timeout=10 -e"UPDATE compaction.${METADATA_TABNAME} SET endTime='$end_time', status='$STATUS' WHERE tableSchema = '$SCHEMA' a
nd tableName='$TABLE'" 2>/dev/null
             
         done    
    
}

compaction_validation()
{

    TOTAL_COUNT=`mysql -NB -u$USER -p$PASSWD -h$LOCAL_OPSDB --connect_timeout=10 -e"SELECT COUNT(*) FROM  compaction.${METADATA_TABNAME}" 2>/dev/null`
    SUCCESS_COUNT=`mysql -NB -u$USER -p$PASSWD -h$LOCAL_OPSDB --connect_timeout=10 -e"SELECT COUNT(*) FROM  compaction.${METADATA_TABNAME} WHERE status = 'SUCCESS'" 2>/dev/null`
    FAILED_COUNT=`mysql -NB -u$USER -p$PASSWD -h$LOCAL_OPSDB --connect_timeout=10 -e"SELECT COUNT(*) FROM  compaction.${METADATA_TABNAME} WHERE status != 'SUCCESS'" 2>/dev/null`

    echo TOTAL COUNT: $TOTAL_COUNT  
    echo SUCCESS COUNT: $SUCCESS_COUNT
    echo FAILED COUNT: $FAILED_COUNT

    #create temporary table to get table sizes
    mysql -NB -u$USER -p$PASSWD -h$LOCAL_OPSDB --connect_timeout=10 -e"CREATE TABLE compaction.${METADATA_TABNAME}_temp LIKE compaction.${METADATA_TABNAME};"  2>/dev/null

    if [[ -z "$V_SCHEMA" ]]

    then
        SCHEMALIST=`mysql -NB -u$USER -p$PASSWD -h$LOCAL_OPSDB --connect_timeout=10 -e"select distinct schemaName from ckadmin.schema_info where isSharded='Y'" 2>/dev/null`
    else
        SCHEMALIST=`mysql -NB -u$USER -p$PASSWD -h$LOCAL_OPSDB --connect_timeout=10 -e"select distinct schemaName from ckadmin.schema_info where isSharded='Y' and schemaName like '$V_SCHEMA%
'" 2>/dev/null`
    fi

    for SCHEMA in $SCHEMALIST

    do
        mysql -NB -u$USER -p$PASSWD -h $METADATA_FQDN -P $METADATA_PORT --connect_timeout=10 -e"select distinct concat('$SCHEMA,', table_name,',', ROUND(avg((DATA_LENGTH + INDEX_LENGTH) / 10
24 / 1024),1),',${V_DC},${V_GROUP}') from INFORMATION_SCHEMA.TABLES where engine = 'InnoDB' and table_type='BASE TABLE' and table_schema like '${SCHEMA}%' GROUP BY table_name;">>$LOGDIR/comp
action_tablist_${V_GROUP}_${TS}_temp.dat 2>/dev/null
    done

    #Create table for compaction and load data
    mysql -NB -u$USER -p$PASSWD -h$LOCAL_OPSDB --connect_timeout=10 -e"LOAD DATA INFILE '$LOGDIR/compaction_tablist_${V_GROUP}_${TS}_temp.dat' INTO TABLE compaction.${METADATA_TABNAME}_temp 
FIELDS TERMINATED BY ',' (tableSchema, tableName, tableSizeBefore, dataCenter, groupName);" 2>/dev/null

    #Update the main table to reflect after table size

    mysql -NB -u$USER -p$PASSWD -h$LOCAL_OPSDB --connect_timeout=10 -e"UPDATE compaction.${METADATA_TABNAME} A JOIN compaction.${METADATA_TABNAME}_temp B ON A.tableSchema = B.tableSchema and
 A.tableName = B.tableName SET A.tableSizeAfter = B.tableSizeBefore WHERE A.tableSizeAfter is NULL;" 2>/dev/null

    #DROP the temp table 
    mysql -NB -u$USER -p$PASSWD -h$LOCAL_OPSDB --connect_timeout=10 -e"DROP TABLE IF EXISTS compaction.${METADATA_TABNAME}_temp;" 2>/dev/null
    rm -f $LOGDIR/compaction_tablist_${V_GROUP}_${TS}_temp.dat

}
 main()
{

 process_args $*
    
 if [[ -z "$V_RESUME" ]]
 then
   compaction_prepare
   compaction_execute
   compaction_validation
 else
   METADATA_TABNAME=${V_RESUME}
   compaction_execute
   compaction_validation  
 fi

}

main $*
