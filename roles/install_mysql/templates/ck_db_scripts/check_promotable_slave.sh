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
# Purpose: This scrip should be executed as a cron to check that every 
#          database cluster has atleast 1 promotable slave.
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ORC_CONFIG_FILE=/etc/orchestrator.conf.json
RESULT_FILE=/tmp/check_promotable_slave_result.$$
TOTAL_CLUSTERS=/tmp/check_promotable_slave_total_clusters.$$
PD_EMAIL="dba@creditkarma.pagerduty.com"
DEBUG_EMAIL="dba@creditkarma.com"

#------------------------------------------------------------------- debug --
debug() {
    echo "$1" | mail -s "ALERT from Orchestrator" "$DEBUG_EMAIL" && exit 1
}

LOCAL_DC=`salt-call grains.get ck_datacenter |tail -1 | sed -e 's/^ *//' -e 's/ *$//'`
[ $? -ne 0 ] && debug "Unable to execute salt command 'salt-call grains.get ck_datacenter'"
ACTIVE_DC=`salt-call pillar.get active_datacenter |tail -1 | sed -e 's/^ *//' -e 's/ *$//'`
[ $? -ne 0 ] && debug "Unable to execute salt command 'salt-call pillar.get active_datacenter'"

# If local datacenter != active datacenter then terminate.
[[ "${LOCAL_DC}" != "${ACTIVE_DC}" ]] && exit

[[ "${LOCAL_DC}" == "ckeast" ]] && LOCAL_DC_ALIAS="iad1"
[[ "${LOCAL_DC}" == "ckwest" ]] && LOCAL_DC_ALIAS="sjc1"
[[ "${LOCAL_DC}" == "us-central1" ]] && LOCAL_DC_ALIAS="us-central1"

THISHOST=`hostname -f`
RUNHERE=`/usr/bin/orchestrator -c active-nodes 2>/dev/null | cut -d ';' -f1 | sort |uniq | head -1`
[ $? -ne 0 ] && debug "Unable to execute orchestrator command 'orchestrator -c active-nodes'"

# If this host != first active node then terminate. This code is to make sure that the cron job only run from one active orchestrator node.
[[ "${THISHOST}" != "${RUNHERE}" ]] && exit

# Prepare a list of servers which shouldn't promoted at masters from the config file.
EXCLUDE_HOSTS=`awk '/],/ {f=0;next} {$f=$f};f; /PromotionIgnoreHostnameFilters/ {f=1}' $ORC_CONFIG_FILE | sed 's/[",]//g' | xargs | sed -e 's/ /\\|/g'`

# Fetching List of all database clusters
/usr/bin/orchestrator -c clusters > $TOTAL_CLUSTERS
[ $? -ne 0 ] && debug "Unable to execute orchestrator command 'orchestrator -c clusters'"

cat /dev/null > $RESULT_FILE

# Looping through each database cluster to look for promotable slave(s)."
while read CLUSTERNAME
do
    if [[ $CLUSTERNAME == *"$LOCAL_DC_ALIAS"* ]]
    then
        COUNT_PROMOTABLE_SLAVES=`/usr/bin/orchestrator -c which-slaves -i $CLUSTERNAME --quiet |grep -v -E "${EXCLUDE_HOSTS}" |grep "$DC" |wc -l`
        [ $? -ne 0 ] && debug "Unable to execute orchestrator command 'orchestrator -c which-slaves'"
        [[ $COUNT_PROMOTABLE_SLAVES -eq 0 ]] && echo "$CLUSTERNAME" >> $RESULT_FILE
    fi
done < $TOTAL_CLUSTERS

[ -s $RESULT_FILE ] && cat $RESULT_FILE | mail -s "ALERT from Orchestrator. Promotable Failover Candidate(s) not available." "$PD_EMAIL,$DEBUG_EMAIL"

rm -f $TOTAL_CLUSTERS $RESULT_FILE
