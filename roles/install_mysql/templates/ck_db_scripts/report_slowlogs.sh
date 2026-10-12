#!/bin/bash
###############################################################################
#
# Auther : Ashok Jivani
# Purpose: This script should be used to generate slow query logs report and
#          send to DBA team.
# Usage  : script_name.sh
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
RESULT_FILE=/tmp/${SCRIPT_NAME}_resultfile.$$
HTML_FILE=/tmp/${SCRIPT_NAME}_html.$$

DAY_OF_WEEK=$(date +%u)
DAYS=0
[ $DAY_OF_WEEK -eq 1 ] && DAYS="4"
[ $DAY_OF_WEEK -eq 4 ] && DAYS="3"

TODAY=`date "+%Y-%m-%d"`
ENDDATE=`date --date="$TODAY -1 days" "+%Y-%m-%d"`
STARTDATE=`date --date="$ENDDATE -$DAYS days" "+%Y-%m-%d"`
SINCE="$STARTDATE 23:00:00"
UNTIL="$ENDDATE 23:00:00"

EMAILS="h4j7f6s4l8k0e0i9@ckcorp.slack.com"  

declare -a DBLIST=("mono_master" "mono_slave" "shard_master")

(
echo "From: root@`hostname`
Subject: Slow Logs report as of $ENDDATE
To: $EMAILS
Content-type: text/html
<br></br>
<br/>
<!DOCTYPE html>
<html>
  <head>
    <style>table,th,td{border:1px solid black; padding:5px; font-family: verdana; font-size: 10pt; border-collapse:collapse;}
    </style>
  </head>
<Body>"
) > $HTML_FILE

#-------------------------------------------------------------- send_email --
send_email() {

  cat $HTML_FILE | /usr/sbin/sendmail "$EMAILS"
  
  [ $? -ne 0 ] && debug "Error occurred during sending email."

  rm -f $HTML_FILE $RESULT_FILE
  return 0
}

for TABLENAME in "${DBLIST[@]}"
do
    RESULT_FILE=/tmp/${SCRIPT_NAME}
    QRY="select checksum, ts_cnt, round(Query_time_pct_95, 2) as Query_Time from slowlogs.slogs_${TABLENAME} where ts_min >='$SINCE' and ts_max <= '$UNTIL' order by ts_cnt desc, Query_time_pct_95 desc limit 10"
    mysql -e"$QRY" > $RESULT_FILE
    
  if [ -s $RESULT_FILE ]
  then  
      (
      echo "<br><b>$TABLENAME:</b></br><table>"
      cat $RESULT_FILE | awk 'NR==1 { print "<tr>" ; for (i=1;i<=NF;i++) print "<td align=right bgcolor=#EDEDED></b>" $i "</td>" ; print "</tr>" }'
      cat $RESULT_FILE | awk 'NR>1  { print "<tr>" ; for (i=1;i<=NF;i++) print "<td align=right>" $i "</td>" ;  print "</tr>" }'
      echo "</table><br/>"
      ) >> $HTML_FILE
  fi
done

 (echo "<br><b>Query:</b></br>"

  echo "
  <pre>
  SELECT 
    sample, 
    ts_cnt, 
    round(Query_time_pct_95, 2) as Query_Time 
  FROM 
    slowlogs.slogs_tablename 
  WHERE
    ts_min &gt;= '$SINCE' and 
    ts_max &lt;= '$UNTIL' 
  ORDER BY 
    ts_cnt desc, 
    Query_time_pct_95 desc 
  LIMIT 10
  </pre>"
  ) >> $HTML_FILE

[ -s $HTML_FILE ] && send_email 
