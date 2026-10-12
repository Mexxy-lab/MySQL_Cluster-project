#!/bin/bash
# =============================================================================
  {% for line in fileBanner %}
# {{line}} {% endfor %}
# =============================================================================

###############################################################################
#
# Auther : Ashok Jivani
# Purpose: This script should be used to track database growth. 
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
TMP_FILE=/tmp/tracking_db_growth.tmp
RESULT_FILE=/tmp/tracking_db_growth.result
HTML_FILE=/tmp/tracking_db_growth.html

TOOLS_MYCNF=${HOME}/.tools.$$.cnf
cat > $TOOLS_MYCNF << EOL
!include /etc/my.cnf
[client]
user=$TOOLS_USER
password=$TOOLS_PASSWD
EOL

TOOLS_AUTH="mysql --defaults-extra-file=$TOOLS_MYCNF -h $LOCAL_OPSDB"

DBNAME="prod_tracking"
TABLE_NAME="tracking_db_growth"

TODAY=`date "+%Y-%m-%d"`

DBA_EMAIL="dba@creditkarma.com"
EMAILS="dba@creditkarma.com"
EMAILS="ashok.jivani@creditkarma.com"

#-------------------------------------------------------------------- help --
help(){
  echo "" 
  echo "This script should be used to log database growth and send email notification."
  echo ""
  echo "Usage:"
  echo ""
  echo "sh $SCRIPT_NAME.sh < REQUIRED > [ OPTIONAL ]"
  echo ""
  echo "  Required:"
  echo "      --type           DB type (ie mdb, sdb1)"
  echo "      --days           Remaining Days (ie 180)"
  echo "      --growth-pct     Growth rate in pct (ie 5, 7)"
  echo ""
  echo "  Optional:"
  echo ""
  echo "  Example:"
  echo ""
  echo "      sh $SCRIPT_NAME.sh --days 180 --growth-pct 5"
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
        --type )            V_TYPE=${arguments[index]};;
        --days )            V_DAYS=${arguments[index]};;
        --growth-pct )      V_GROWTH_PCT=${arguments[index]};;
      esac
  done
  
  [ -z "${V_TYPE}" ] && echo "Please specify 'DB Type' for --type option. See --help for help" && exit 1
  [ -z "${V_DAYS}" ] && echo "Please specify 'Remaining Days Threshold' for --days option. See --help for help" && exit 1
  [ -z "${V_GROWTH_PCT}" ] && echo "Please specify 'Growth Rate in %' for --growth-pct option. See --help for help" && exit 1
  
  return 0
}

#------------------------------------------------------------------- debug --
debug() {
  echo "$1" | /bin/mail -s "ERROR!! tracking DB GROWTH script Failed" "$DBA_EMAIL"
  
  rm -f $TMP_FILE $RESULT_FILE $HTML_FILE
  return 0
}

#-------------------------------------------------------------- send_email --
send_email() {

  (
  echo "From: root@`hostname`"
  echo "Subject: ALERT!!! DB Growth as of $TODAY"
  echo "To: $EMAILS"
  echo "Content-type: text/html"
  echo "<br>Below Database(s) are approaching max. storage capacity in near future.</br>"
  echo "<br><i><b>Note:</b> 'DAYS_REMAINING' is calculated on basis of ${V_GROWTH_PCT}% growth rate. </i></br>"
  echo "<br/>"
  printf "<!DOCTYPE html>\n<html>\n<head>\n<style>\ntable,th,td\n{\nborder:1px solid black; \n padding:5px; \n font-family: verdana; \n font-size: 10pt; \nborder-collapse:collapse;\n}\n</style>\n</head>\n<Body>\n<table>"
  
  cat $TMP_FILE | awk 'NR==1 { print "<tr>" ; for (i=1;i<=NF;i++) print "<td bgcolor=#EDEDED></b>" $i "</td>" ; print "</tr>" }'
  cat $TMP_FILE | awk 'NR>1  { print "<tr>" ; for (i=1;i<=NF;i++) print "<td align=center>" $i "</td>" ;  print "</tr>" }'

  ) > $HTML_FILE

  cat $HTML_FILE | /usr/sbin/sendmail "$EMAILS"
  
  [ $? -ne 0 ] && debug "Error occurred during sending email."

  rm -f $HTML_FILE $TMP_FILE
  return 0
}

#---------------------------------------------------------- record_db_size --
record_db_size() {
  
  # Creating a tracking table if not exists.

  $TOOLS_AUTH -e"CREATE TABLE if not exists $DBNAME.$TABLE_NAME (
    id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
    instance_name varchar(255) NOT NULL,
    partition_name varchar(255) NOT NULL,
    used_data bigint(20) unsigned NOT NULL,
    used_logs bigint(20) unsigned NOT NULL,
    remaining bigint(20) unsigned NOT NULL,
    autoTs timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_autots (autoTs)
  ) ENGINE=InnoDB"

  [ $? -ne 0 ] && debug "Error occurred during creating a table '$DBNAME.$TABLE_NAME'"

  # Checking if today's db size is already logged.
  ARE_RECORDS=`$TOOLS_AUTH -NB -e"select count(1) from $DBNAME.$TABLE_NAME where date(autoTs) = '$TODAY'"`
  [ $? -ne 0 ] && debug "Error occurred during checking if todays data already been logged."

  if [ $ARE_RECORDS -eq 0 ]
  then
     [ "$V_TYPE" == "mdb" ] && V_INSTANCE_NAME="Monolithic"
     [ "$V_TYPE" == "sdb1" ] && V_INSTANCE_NAME="Shard"

     V_DATADIR=/db/data/$V_TYPE 
     V_TOTAL_SIZE=`df $V_DATADIR |grep "$V_DATADIR" | awk '{print $2*1024}'`
     V_CURR_DATA=`du -sb $V_DATADIR/mysql | awk '{print $1}'`
     V_CURR_LOGS=`du -sb $V_DATADIR/logs | awk '{print $1}'`
     V_REMAINING=$(( V_TOTAL_SIZE - ( V_CURR_DATA + V_CURR_LOGS )))

     
     $TOOLS_AUTH -e"insert into $DBNAME.$TABLE_NAME (instance_name, partition_name, used_data, used_logs, remaining)
         values ('$V_INSTANCE_NAME', '$V_DATADIR', $V_CURR_DATA, $V_CURR_LOGS, $V_REMAINING)"
     
     [ $? -ne 0 ] && debug "Error occurred during inserting into a table '$DBNAME.$TABLE_NAME'"
  fi

  return 0
}

#--------------------------------------------------------- monitor_db_size --
monitor_db_size() {
  
  V_WEEK=1
  V_MONTH=1
  DAYS=`$TOOLS_AUTH -NB -e"select datediff(curdate(), min(date(autoTs))) from $DBNAME.$TABLE_NAME;"`

  [ $? -ne 0 ] && debug "Error occurred during checking how much data been logged."

  [[ $DAYS -ge 3 && $DAYS -lt 7 ]] && V_WEEK=1 && V_MONTH=3
  [[ $DAYS -ge 7 && $DAYS -lt 14 ]] && V_WEEK=3 && V_MONTH=7
  [[ $DAYS -ge 14 && $DAYS -lt 30 ]] && V_WEEK=7 && V_MONTH=14
  [ $DAYS -ge 30 ] && V_WEEK=7 && V_MONTH=30
  
  $TOOLS_AUTH -A $DBNAME -e"
     select
         curr.instance_name DB,
         if(week.remaining > curr.remaining, concat(ifnull(round((week.remaining - curr.remaining)/(1024*1024*1024*$V_WEEK), 2), 0), 'GB'), 0) DAILY_GROWTH_LAST_${V_WEEK}d,
         if(month.remaining > curr.remaining, concat(ifnull(round((month.remaining - curr.remaining)/(1024*1024*1024*$V_MONTH), 2), 0), 'GB'), 0) DAILY_GROWTH_LAST_${V_MONTH}d,
         if(week.remaining > curr.remaining, ifnull(round(curr.remaining/( (week.remaining - curr.remaining) * ((100 + $V_GROWTH_PCT )/100) / $V_WEEK), 2), 0), 0) DAYS_REMAINING_${V_WEEK}d,
         if(month.remaining > curr.remaining, ifnull(round(curr.remaining/( (month.remaining - curr.remaining) * ((100 + $V_GROWTH_PCT )/100) / $V_MONTH), 2), 0), 0) DAYS_REMAINING_${V_MONTH}d
     from 
         (select * from $DBNAME.$TABLE_NAME where date(autoTs) = curdate()) curr join
         (select * from $DBNAME.$TABLE_NAME where date(autoTs) = date_sub(curdate(), interval $V_WEEK day)) week using (instance_name) join
         (select * from $DBNAME.$TABLE_NAME where date(autoTs) = date_sub(curdate(), interval $V_MONTH day)) month  using (instance_name) 
     where 
         curr.used_data != 0 
         and ((curr.used_data + curr.used_logs)*100/(curr.used_data + curr.used_logs + curr.remaining)) > 0 
         and (month.remaining > curr.remaining or week.remaining > curr.remaining)
    having 
        if(DAYS_REMAINING_${V_WEEK}d >= DAYS_REMAINING_${V_MONTH}d, DAYS_REMAINING_${V_WEEK}d, DAYS_REMAINING_${V_MONTH}d) between 1 and $V_DAYS
    order by  
        DAYS_REMAINING_${V_WEEK}d" > $TMP_FILE
 
  [ $? -ne 0 ] && debug "Error occurred during calculating the db growth"
  
  [[ -s $TMP_FILE ]] && send_email

  return 0
}


#-------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  record_db_size
  monitor_db_size
  return 0
}
main $*

