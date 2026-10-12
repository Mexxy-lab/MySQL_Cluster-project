#!/bin/bash

# =============================================================================
# =============================================================================

###############################################################################
#
# Author : Nived
# Purpose: Updates Confluence with MySQL Backup information
# Usage  : sh backup_source.sh 
#
###############################################################################

date=`date +'%Y_%m_%d_%H%M%S'`
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
RESULT_FILE=/tmp/${SCRIPT_NAME}_resultfile.$$
LOGDIR=/var/log/dblogs

#Confluence Details
PAGEID='64009649'
ANCESTORID='61218225'

# colors
RED=`tput setaf 1`
GREEN=`tput setaf 2`
NOCOLOR='\e[0m'

#---------------------------------------------------------------------- help --
help(){
  echo "###############################################################################"
  echo ""
  echo "This script will update confluence with the ETL source"
  echo ""
  echo "Usage:"
  echo ""
  echo "sh $SCRIPT_NAME.sh"
  echo ""
  echo ""
  echo "###############################################################################"
  exit 1
}


backup_details()

{

  mysql -A ckadmin -NB -e"select concat(temp.fqdn, \"|\", temp.dc, \"|\", temp.groupName, \"|\", temp.admin, \"|\", temp.sid, \"|\", temp.Last_Executed) from (select a.fqdn as fqdn, a.datacenter as dc, a.groupName as groupName, a.vmax_admin as admin, a.vmax_sid as sid, max(b.autoTs) as Last_Executed from snapshot_host_map a join snapshot_catalog b on a.fqdn = b.backupHost where a.app_consistent_ready = 1 and DATE(b.autoTs) = CURRENT_DATE() group by a.fqdn, DATE(b.autoTs) order by fqdn) temp;" >$LOGDIR/${SCRIPT_NAME}_app_${date}.log

  mysql -A ckadmin -NB -e"select concat(temp.fqdn, \"|\", temp.dc, \"|\", temp.groupName, \"|\", temp.admin, \"|\", temp.sid, \"|\", temp.Last_Executed) from (select a.fqdn as fqdn, a.datacenter as dc, a.groupName as groupName, a.vmax_admin as admin, a.vmax_sid as sid, max(b.autoTs) as Last_Executed from snapshot_host_map a join snapshot_catalog b on a.fqdn = b.backupHost where a.app_consistent_ready = 0 and DATE(b.autoTs) = CURRENT_DATE() group by a.fqdn, DATE(b.autoTs) order by fqdn) temp;" >$LOGDIR/${SCRIPT_NAME}_crash_${date}.log

}

gen_page()

{

    #Getting the current version to Update confluence document
    curl -u ${CONFLUENCE_USER}:${CONFLUENCE_PASSWD} -s https://confluence.creditkarma.com/rest/api/content/${PAGEID}?expand=version|python -mjson.tool>> /tmp/confluence_ver_$date.tmp
    current_version=`cat /tmp/confluence_ver_$date.tmp|grep -i number|cut -d ':' -f2|sed -e "s/,//g"|sed -e "s/ //g"`
    next_version=$(( $current_version + 1 ))

    #echo Next: $next_version

   if [ -s $LOGDIR/${SCRIPT_NAME}_app_${date}.log ]

    then

        printf "{\"id\":\"${PAGEID}\",\"type\":\"page\",\"title\":\"MySQL Backups Info\",\"ancestors\":[{\"id\":${ANCESTORID}}],\"space\":{\"key\":\"DBA\"},\"body\":{\"storage\":{\"value\":\"<p>Last Updated - `date +'%Y-%m-%d %H:%M'`</p><p>&nbsp;</p><p><strong>Application Consistent Backups:</strong></p><p>&nbsp;</p><table><tr><th>Host Name</th><th>Datacenter</th><th>Group Name</th><th>VMAX Admin</th><th>VMAX SID</th><th>Last Executed</th></tr>"
        while read INPUT ; do printf "<tr><td>${INPUT//|/</td><td>}</td></tr>" ; done < $LOGDIR/${SCRIPT_NAME}_app_${date}.log|tr --delete '\n'
        printf "</table>"

    else

        printf "{\"id\":\"${PAGEID}\",\"type\":\"page\",\"title\":\"MySQL Backups Info\",\"ancestors\":[{\"id\":${ANCESTORID}}],\"space\":{\"key\":\"DBA\"},\"body\":{\"storage\":{\"value\":\"<p>Last Updated - `date +'%Y-%m-%d %H:%M'`</p><p>&nbsp;</p><p><strong>Application Consistent Backups:</strong></p><p>&nbsp;</p><p>Application Consistent Snapshots have not been executed Today</p>"

   fi

   if [ -s $LOGDIR/${SCRIPT_NAME}_crash_${date}.log ]

    then

    printf "<p>&nbsp;</p><p><strong>Crash Consistent Backups:</strong></p><p> &nbsp;</p><table><tr><th>Host Name</th><th>Datacenter</th><th>Group Name</th><th>VMAX Admin</th><th>VMAX SID</th><th>Last Executed</th></tr>"
    while read INPUT ; do printf "<tr><td>${INPUT//|/</td><td>}</td></tr>" ; done < $LOGDIR/${SCRIPT_NAME}_crash_${date}.log|tr --delete '\n'
    printf "</table>\",\"representation\":\"storage\"}},\"version\":{\"number\":${next_version}}}"

    else
    
    printf "<p>&nbsp;</p><p><strong>Crash Consistent Backups:</strong></p><p> &nbsp;</p><p>Crash Consistent Snapshots have not been executed Today</p>\",\"representation\":\"storage\"}},\"version\":{\"number\":${next_version}}}"

   fi

}

backup_details

gen_page >> $LOGDIR/${SCRIPT_NAME}_$date.html

cat $LOGDIR/${SCRIPT_NAME}_$date.html| curl -s -u ${CONFLUENCE_USER}:${CONFLUENCE_PASSWD} -X PUT -H 'Content-Type: application/json' -d @- https://confluence.creditkarma.com/rest/api/content/$PAGEID >>/tmp/confluence_ver_$date.tmp

#Removing All the unwanted logs
rm -f $LOGDIR/${SCRIPT_NAME}_`date -d '1 day ago' +'%Y_%m_%d'`*

