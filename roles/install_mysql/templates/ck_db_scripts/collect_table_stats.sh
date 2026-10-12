#!/bin/bash
# =============================================================================
# {% for line in fileBanner %}
# {{line}} {% endfor %}
# =============================================================================

# This script should be used to persist mysql table statistics into a given table on a scheduled interval for analysic purpose. 

MY_AUTH="mysql"
DBNAME="temp"
TODAY=`date "+%Y-%m-%d"`
CURRENT_DATE=`date --date "$TODAY" +%Y_%m`
OLD_DATE=`date --date "$TODAY -2 month" +%Y_%m`
CURRENT_TABLE="table_stats_$CURRENT_DATE"
OLD_TABLE="table_stats_$OLD_DATE"
SPLUNK_LOG=/var/log/tablestats

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"

. ${PARAMETER_FILE}

#Create directory

mkdir -p /var/log/tablestats/

if [[ $1 == "TABLE" ]]

then

# Create stats table if not exists.
  
$MY_AUTH -e"SET SESSION sql_log_bin=0; CREATE DATABASE IF NOT EXISTS $DBNAME; CREATE TABLE IF NOT EXISTS $DBNAME.$CURRENT_TABLE(
      TABLE_SCHEMA           varchar(192)        NOT NULL DEFAULT '',
      TABLE_NAME             varchar(192)        NOT NULL DEFAULT '',
      ROWS_READ              bigint(21) unsigned NOT NULL DEFAULT '0',
      ROWS_CHANGED           bigint(21) unsigned NOT NULL DEFAULT '0',
      ROWS_CHANGED_X_INDEXES bigint(21) unsigned NOT NULL DEFAULT '0',
      autoTs                 timestamp           NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      KEY schema_name (TABLE_SCHEMA, TABLE_NAME),
      KEY autoTs (autoTs)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8"
[ $? -ne 0 ] && echo "Error occurred during creating a table '$DBNAME.$CURRENT_TABLE'" && exit 1

# Insert data from TABLE_STATISTICS to table_stats

$MY_AUTH -e"SET SESSION sql_log_bin=0; INSERT INTO $DBNAME.$CURRENT_TABLE (TABLE_SCHEMA,TABLE_NAME,ROWS_READ,ROWS_CHANGED,ROWS_CHANGED_X_INDEXES) select TABLE_SCHEMA, TABLE_NAME, ROWS_READ, ROWS_CHANGED, ROWS_CHANGED_X_INDEXES from information_schema.TABLE_STATISTICS"

[ $? -ne 0 ] && echo "Error occurred during Inserting into table '$DBNAME.$CURRENT_TABLE'" && exit 1

# Clean Up old table on 1st of the month during mid night.

IS_FIRST=`date '+%d%H'`

if [ "$IS_FIRST" == "0101" ]
then
   $MY_AUTH -e"SET SESSION sql_log_bin=0; DROP TABLE IF EXISTS $DBNAME.$OLD_TABLE"
   [ $? -ne 0 ] && echo "Error occurred during Dropping table '$DBNAME.$OLD_TABLE'" && exit 1
fi

elif [[ $1 == "LOG" ]]

then

    port_count=`cat /etc/my.cnf|grep -i port|wc -l`

    if [[ $port_count == 0 ]]

    then
        port="3306"
        host=`hostname`
        socket=`mysql -h ${LOCAL_OPSDB} -u $SPLUNK_USER -p$SPLUNK_PASSWD -NB -e"select socket from ckadmin.host_info where fqdn = '$host' and port = '$port'"`

        mysql -u $SPLUNK_USER -p$SPLUNK_PASSWD -S $socket -h $host -NB -e"select concat(date_format(now(), '%Y-%m-%dT%T'), ' p=${port}', ' s=', TABLE_SCHEMA, ' t=', TABLE_NAME, ' r=', ROWS_READ, ' w=', ROWS_CHANGED) from information_schema.table_statistics;" > ${SPLUNK_LOG}/tablestats_$port.log

        [ $? -ne 0 ] && echo "Error occurred while fetching data from information_schema" && exit 1


    else

    cat /etc/my.cnf|grep -i port|awk '{print $3}'|head -1|while read port

do
    
    host=`hostname`
    socket=`mysql -h ${LOCAL_OPSDB} -u $SPLUNK_USER -p$SPLUNK_PASSWD -NB -e"select socket from ckadmin.host_info where fqdn = '$host' and port = '$port'"`

    echo $socket
    #Generate logs for Splunk
    mysql -u $SPLUNK_USER -p$SPLUNK_PASSWD -P $port -S $socket -h $host -NB -e"select concat(date_format(now(), '%Y-%m-%dT%T'), ' p=${port}', ' s=', TABLE_SCHEMA, ' t=', TABLE_NAME, ' r=', ROWS_READ, ' w=', ROWS_CHANGED) from information_schema.table_statistics;" > ${SPLUNK_LOG}/tablestats_$port.log

    [ $? -ne 0 ] && echo "Error occurred while fetching data from information_schema" && exit 1

done

fi

fi

