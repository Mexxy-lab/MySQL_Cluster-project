#!/bin/bash
# =============================================================================
  {% for line in fileBanner %}
# {{line}} {% endfor %}
# =============================================================================

###############################################################################
#
# Auther : Ashok Jivani
# Purpose: This script should be used to find MAX ID for auto_increment columns 
#          in shards and monolithic. 
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
TMP_FILE=/tmp/tracking_max_id.tmp
TMP_FILE2=/tmp/tracking_max_id2.tmp
RESULT_FILE=/tmp/tracking_max_id.result
HTML_FILE=/tmp/tracking_max_id.html

LOCAL_AUTH="mysql"
DBNAME="prod_tracking"
TABLE_NAME="maxIdTracking"

TODAY=`date "+%Y-%m-%d"`

DBA_EMAIL="dba@creditkarma.com"
EMAILS="dba@creditkarma.com"

#-------------------------------------------------------------------- help --
help(){
  echo "" 
  echo "This script should be used to log max tracking id and send email notification if any of the column is about to max out."
  echo ""
  echo "Usage:"
  echo ""
  echo "sh $SCRIPT_NAME.sh < REQUIRED > [ OPTIONAL ]"
  echo ""
  echo "  Required:"
  echo "      --remote-host    Remote Hostname (ie. budb1.sjc1)"
  echo "      --remote-port    Remote Port (ie.3305)"
  echo "      --days           Remaining Days (ie 180)"
  echo "      --growth-pct     Growth rate in pct (ie 5, 7)"
  echo ""
  echo "  Optional:"
  echo ""
  echo "  Example:"
  echo ""
  echo "      sh $SCRIPT_NAME.sh --remote-host budb1.sjc1 --remote-port 3305 --days 180 --growth-pct 5"
  echo ""
  exit 1
}

#------------------------------------------------------------ process_args --
process_args() {
  
  options=$@

  # An array with all the arguments
  arguments=($options)

  [[ $arguments == "--help" || $arguments == "" ]] && help && exit 1

  index=0
  for argument in $options
  do
      index=`expr $index + 1`
      
      case $argument in
        --remote-host )     V_REMOTE_HOST=${arguments[index]};;    
        --remote-port )     V_REMOTE_PORT=${arguments[index]};;
        --schema-name )     V_SCHEMA_NAME=${arguments[index]};;
        --days )            V_DAYS=${arguments[index]};;
        --growth-pct )      V_GROWTH_PCT=${arguments[index]};;
      esac
  done
  
  [ -z "${V_REMOTE_HOST}" ] && echo "Please specify 'Remote Hostname' for --remote-host option. See --help for help" && exit 1
  [ -z "${V_REMOTE_PORT}" ] && echo "Please specify 'Remote Port' for --remote-port option. See --help for help" && exit 1
  [ -z "${V_SCHEMA_NAME}" ] && echo "Please specify 'Schema Name' for --schema-name option. See --help for help" && exit 1
  [ -z "${V_DAYS}" ] && echo "Please specify 'Remaining Days Threshold' for --days option. See --help for help" && exit 1
  [ -z "${V_GROWTH_PCT}" ] && echo "Please specify 'Growth Rate in %' for --growth-pct option. See --help for help" && exit 1
  
  SCHEMA_FILTER=""
  [ ! -z "${V_SCHEMA_NAME}" ] && SCHEMA_LIST=`echo $V_SCHEMA_NAME | sed "s/,/','/g"` SCHEMA_FILTER=" table_schema in ('$SCHEMA_LIST')"

  REMOTE_AUTH="mysql -u$USER -p$PASSWD -h$V_REMOTE_HOST -P$V_REMOTE_PORT"
  
  return 0
}

#------------------------------------------------------------------- debug --
debug() {
  echo "$1" | /bin/mail -s "ERROR!! Tracking MAX ID script Failed" "$DBA_EMAIL"
  return 0
}

#-------------------------------------------------------------- send_email --
send_email() {
  (
  echo "From: root@`hostname`"
  echo "Subject: ALERT!!! Tables approaching Out of Range values as of $TODAY"
  echo "To: $EMAILS"
  echo "Content-type: text/html"
  echo "<br>Below Table(s) are approaching out of range integer values in near future. </br>"
  echo "<br><i><b>Note:</b> 'DAYS_REMAINING' is calculated on basis of ${V_GROWTH_PCT}% growth rate. </i></br>"
  echo "<br/>"
  printf "<!DOCTYPE html>\n<html>\n<head>\n<style>\ntable,th,td\n{\nborder:1px solid black; \n padding:5px; \n font-family: verdana; \n font-size: 10pt; \nborder-collapse:collapse;\n}\n</style>\n</head>\n<Body>\n<table>"
  
  cat $TMP_FILE | awk 'NR==1 { print "<tr>" ; for (i=1;i<=NF;i++) print "<td bgcolor=#EDEDED></b>" $i "</td>" ; print "</tr>" }'
  cat $TMP_FILE | awk 'NR>1  { print "<tr>" ; for (i=1;i<=NF;i++) if (i==4 || i==5) printf "<td align=center>" "%\047d",$i "</td>" ; else print "<td align=center>" $i "</td>" ;  print "</tr>" }'

  ) > $HTML_FILE

  cat $HTML_FILE | /usr/sbin/sendmail "$EMAILS"
  
  [ $? -ne 0 ] && debug "Error occurred during sending email."

  rm -f $HTML_FILE $TMP_FILE
  return 0
}

#----------------------------------------------------------- record_max_id --
record_max_id() {
  
  # Creating a tracking table if not exists.

  $LOCAL_AUTH -e"CREATE TABLE if not exists $DBNAME.$TABLE_NAME(
    id bigint unsigned NOT NULL AUTO_INCREMENT,
    table_schema varchar(255) NOT NULL,
    table_name varchar(255) NOT NULL,
    column_name varchar(255) NOT NULL,
    currentVal bigint unsigned NOT NULL,
    remaining bigint unsigned NOT NULL,
    autoTs timestamp default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    key idx_autots (autoTs)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8"

  [ $? -ne 0 ] && debug "Error occurred during creating a table '$DBNAME.$TABLE_NAME'"

  # Checking if today's tracking is already logged.
  ARE_RECORDS=`$LOCAL_AUTH -NB -e"select count(1) from $DBNAME.$TABLE_NAME where date(autoTs) = '$TODAY' and $SCHEMA_FILTER"`
  
  [ $? -ne 0 ] && debug "Error occurred during checking if Today's tracking is already logged" 
  if [ $ARE_RECORDS -eq 0 ]
  then
      # Fetching columns with AUTO_INCREMENT property.

      $REMOTE_AUTH -NB -e" 
          select 
          CONCAT(
          'SELECT CONCAT (\"', table_schema, '\", \":\" , \"', table_name,  '\", \":\",  \"', column_name, '\", \":\", ifnull( max(',column_name,'),0), \":\", ', (
          case 
              WHEN column_type like 'tinyint%unsigned'     then 255
              WHEN column_type like 'tinyint%'             then 128
              WHEN column_type like 'smallint%unsigned'    then 65535
              WHEN column_type like 'smallint%'            then 32767
              WHEN column_type like 'mediumint%unsigned'   then 16777215
              WHEN column_type like 'mediumint%'           then 8388607
              WHEN column_type like 'int%unsigned'         then 4294967295
              WHEN column_type like 'int%'                 then 2147483647
              WHEN column_type like 'bigint%unsigned'      then 18446744073709551615
              WHEN column_type like 'bigint%'              then 9223372036854775807
          end
          ) , '- ifnull (max(',column_name,'), 0)) from ',table_schema,'.',table_name,';') as query from information_schema.columns where $SCHEMA_FILTER and extra='auto_increment'" > $TMP_FILE

      [ $? -ne 0 ] && debug "Error occurred during generating insert statements on '$REMOTE_HOST($REMOTE_PORT)'"

      $REMOTE_AUTH -NB < $TMP_FILE > $TMP_FILE2 

      rm -f $RESULT_FILE

      # Preparing INSERT Statements.
      
      while read LINE
      do
          V_TABLE_SCHEMA=`echo $LINE | cut -d":" -f1`
          V_TABLE_NAME=`echo $LINE | cut -d":" -f2`
          V_COLUMN_NAME=`echo $LINE | cut -d":" -f3`
          V_CURRENT_VAL=`echo $LINE | cut -d":" -f4`
          V_REMAINING=`echo $LINE | cut -d":" -f5`

          echo "INSERT INTO $DBNAME.$TABLE_NAME (table_schema, table_name, column_name, currentVal, remaining) values ('$V_TABLE_SCHEMA', '$V_TABLE_NAME', '$V_COLUMN_NAME', $V_CURRENT_VAL, $V_REMAINING);" >> $RESULT_FILE

      done < $TMP_FILE2

      # Inserting into tracking table

      [ -s $RESULT_FILE ] && $LOCAL_AUTH -A $DBNAME < $RESULT_FILE
      [ $? -ne 0 ] && debug "Error occurred during inserting into '$DBNAME.$TABLE_NAME'"
  
  fi

  return 0
}

#------------------------------------------------------ monitor_max_values --
monitor_max_values() {
  
  V_WEEK=1
  V_MONTH=1
  DAYS=`$LOCAL_AUTH -NB -e"select datediff(curdate(), min(date(autoTs))) from $DBNAME.$TABLE_NAME;"`

  [ $? -ne 0 ] && debug "Error occurred during checking how much data been logged."

  [[ $DAYS -ge 3 && $DAYS -lt 7 ]] && V_WEEK=1 && V_MONTH=3
  [[ $DAYS -ge 7 && $DAYS -lt 14 ]] && V_WEEK=3 && V_MONTH=7
  [[ $DAYS -ge 14 && $DAYS -lt 30 ]] && V_WEEK=7 && V_MONTH=14
  [ $DAYS -ge 30 ] && V_WEEK=7 && V_MONTH=30

  $LOCAL_AUTH -A $DBNAME -e"
    select
        curr.table_schema TABLE_SCHEMA,
        curr.table_name TABLE_NAME,
        curr.column_name COLUMN_NAME,
        if(week.remaining > curr.remaining, ifnull(round((week.remaining - curr.remaining)/$V_WEEK, 0), 0), 0) DAILY_INSERTS_LAST_${V_WEEK}d,
        if(month.remaining > curr.remaining, ifnull(round((month.remaining - curr.remaining)/$V_MONTH, 0), 0), 0) DAILY_INSERTS_LAST_${V_MONTH}d,
        if(week.remaining > curr.remaining, ifnull(round(curr.remaining/( (week.remaining - curr.remaining) * ((100 + $V_GROWTH_PCT )/100) / $V_WEEK), 2), 0), 0) DAYS_REMAINING_${V_WEEK}d,
        if(month.remaining > curr.remaining, ifnull(round(curr.remaining/( (month.remaining - curr.remaining) * ((100 + $V_GROWTH_PCT )/100) / $V_MONTH), 2), 0), 0) DAYS_REMAINING_${V_MONTH}d
    from 
        (select * from $DBNAME.$TABLE_NAME where date(autoTs) = curdate()) curr join
        (select * from $DBNAME.$TABLE_NAME where date(autoTs) = date_sub(curdate(), interval $V_WEEK day)) week using (table_schema, table_name, column_name) join
        (select * from $DBNAME.$TABLE_NAME where date(autoTs) = date_sub(curdate(), interval $V_MONTH day)) month  using (table_schema, table_name, column_name) 
    where 
        curr.currentVal != 0 
        and (curr.currentVal*100/(curr.currentVal+curr.remaining)) > 0 
        and (month.remaining > curr.remaining or week.remaining > curr.remaining)
    having 
        if(DAYS_REMAINING_${V_WEEK}d >= DAYS_REMAINING_${V_MONTH}d, DAYS_REMAINING_${V_WEEK}d, DAYS_REMAINING_${V_MONTH}d) between 1 and $V_DAYS
    order by  
        DAYS_REMAINING_${V_WEEK}d" > $TMP_FILE
 
  [ $? -ne 0 ] && debug "Error occurred during calculating out of range values."
  
  [[ $V_SCHEMA_NAME == "ck" && -s $TMP_FILE ]] && send_email

  return 0
}


#-------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  record_max_id
  monitor_max_values
  return 0
}
main $*

