#!/bin/bash

logdir=/var/log/mysql_stats/percona_script
archivelogdir=/db/data/mdb/percona_script

if [[ ! -d $logdir ]]; then
    mkdir $logdir
fi

if [[ ! -d $archivelogdir ]]; then
    mkdir $archivelogdir
fi

function plist {
# PIDs spawned by the script
plist=$(/usr/bin/pgrep -f percona_collect_stats)
echo $plist
}

function pzapper {

# Killing all gzip sessions started by the script
for i in $(plist); do
    pkill -TERM -P $i gzip
    pkill -TERM -P $i mysqladmin
done

sleep 10

/usr/bin/pkill -TERM -f percona_collect_stats

if [[ $? == 0 ]]; then
    echo "Percona stats collector has been terminated"
else
	echo "Failed to kill"
	exit 1
fi
}

while [[ $(plist) ]]; do
    pzapper
    sleep 5
done

# Archiving old logs
if [[ $(ls $logdir) ]]; then
    mv $logdir/* $archivelogdir
fi

# Recycling archived logs
find $archivelogdir -maxdepth 1 -ctime +7 | /usr/bin/xargs rm -rf

sleep 10

# Restarting the script
/usr/local/ops/bin/percona_collect_stats_v2.sh $logdir ctrlc >> /tmp/percona_collect.out 2>&1 &
