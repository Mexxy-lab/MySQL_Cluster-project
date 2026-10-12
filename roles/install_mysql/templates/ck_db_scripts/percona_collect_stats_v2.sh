#!/bin/bash

dir=$1
duration=$2

if [ "$3" == "" ]; then
  savedir=$(hostname)
else
  savedir="$3"
fi

outputdir="${dir}/${savedir}_metrics_$(date +%Y-%m-%d_%H-%M-%S)"
min_free_bytes=1073741824 # 1GB
min_free_pct=10           # 10%


function usage {
  echo ""
  echo "Usage: $0 dir/ {duration|ctrlc} [hostname]"
  echo ""
  echo "Arguments:"
  echo "  - duration is in minutes, ctrlc option can be given to collect data forever (or until ctrl-c)."
  echo "  - dir is the directory to store the data. In the directory, a subdirectory with a"
  echo "        timestamp will be created using the local hostname."
  echo "  - hostname is an optional string to override the name used in the subdirectory."
  echo ""
  echo "Examples:"
  echo "  - $0 /home/gryp ctrlc    # until ctrl-c"
  echo "  - $0 /tmp/ 60            # 60 minutes"
  echo "  - $0 /tmp/ 45 myRdsHost  # 45 minutes, /tmp/myRdsHost_metrics_TIMESTAMP"
  echo ""
  echo "Magical Environment variables:"
  echo "  - COLLECTSLAVESTATUS=1  collect SHOW SLAVE STATUS"
  echo "  - COLLECTPROCESSLIST=1  collect SHOW FULL PROCESSLIST"
  echo "  - COLLECTTOKUDB=1       collect SHOW ENGINE TOKUDB STATUS"
  echo "  - ISRDS=1               won't collect any [io|mp|vm]stat"
  echo "  - MYSQL_OPTIONS="..."   set any mysql options"
  echo ""
  echo "Examples:"
  echo "  - export ISRDS=1"
  echo "  - export MYSQL_OPTIONS=\"-h rds-host.compute-west.amazonaws.com -u myuser -pthepass\""
  echo "  - export MYSQL_OPTIONS=\"--defaults-file=/root/.my.cnf.multiinstanceconf\""
  echo ""
}
bg_jobs=();

if [ $# -lt 2 ]; then
    echo "ERROR: Invalid amount of arguments given"
  usage
    exit 1
fi

function kill_collection() {
  echo "Collecting last pieces of data ... wait a bit."
  date "+%Y-%m-%d %H:%M:%S" > ${outputdir}/collection_stop
  for pid in "${bg_jobs[@]}"
  do
    echo "Killing pid $pid"
    kill -9 $pid >/dev/null 2>&1
    ps -p $pid >/dev/null 2>&1
    if [ "$?" == "0" ]; then
      wait $pid
    fi
  done
  sleep 3
  exit 0
}


function check_disk_space() {
  set -e
  local disk_space=$(df -P -k $dir | tail -n 1)

  local free_bytes=$(echo $disk_space | perl -ane 'print $F[3] * 1024')
  local pct_used=$(echo $disk_space | perl -ane 'print ($F[4] =~ m/(\d+)/)')
  local pct_free=$((100 - $pct_used))

  local real_free_bytes=$free_bytes
  local real_pct_free=$pct_free

   set +e
  if [ $free_bytes -lt $min_free_bytes -o $pct_free -lt $min_free_pct ]; then
    echo "ERROR: Not enough free disk space:
  Limit: ${min_free_pct}% free, ${min_free_bytes} bytes free
 Actual: ${real_pct_free}% free, ${real_free_bytes} bytes free
"
   kill_collection
   fi
   return 0  # disk space is OK
}


function check_binary() {
  binary=$1
  which $binary &> /dev/null
  if [ "$?" != "0" ]; then
    echo "ERROR: Could not find $binary or it is not executable"
    exit 1

  fi
}

check_binary mysqladmin
check_binary mysql
check_binary cat
check_binary gzip
check_binary tar

if [ "${ISRDS}" == "" ]; then
   check_binary mpstat
   check_binary vmstat
   check_binary iostat
fi

## Test MySQL privileges before doing anything else ##
function check_privileges() {
  base="show engine innodb status;"

  if [ "${COLLECTSLAVESTATUS}" != "" ]; then
    base="$base show slave status;"
  fi

  if [ "${COLLECTPROCESSLIST}" != "" ]; then
    base="$base show full processlist;"
  fi

  if [ "${COLLECTTOKUDB}" != "" ]; then
    base="$base show engine tokudb status;"
  fi

  mysql ${MYSQL_OPTIONS} -e "${base}" >/dev/null
  if [ "$?" != "0" ]; then
    echo "ERROR: Missing some privileges."
    exit 1
  fi
}
check_privileges

## get mysql version, to see if we should fetch 5.6 specific data
MYSQLVERSION=`mysql ${MYSQL_OPTIONS} -Ne"select replace(left(version(), 3), '.', '');"`

if [ "$duration" == 'ctrlc' ]; then
  echo "Will collect data until ctrlc is pressed";
else
  if [[ "$duration" =~ ^[0-9]+$ ]]; then
    echo "Will collect data for $duration minutes";
  else
    echo "ERROR: Invalid duration given: $duration";
    usage
    exit 1
  fi
fi

if [ ! -d ${outputdir} ]; then
  mkdir -p ${outputdir}
fi

# before we start let's check disk space first
check_disk_space

echo "Writing all data to $outputdir"

trap kill_collection INT

date "+%Y-%m-%d %H:%M:%S" > ${outputdir}/collection_start

## PUT ALL THE NECESSARY TESTS IN HERE

if [ "${ISRDS}" == "" ]; then
    mpstat 1 | gzip > ${outputdir}/mpstat.out.gz &
    vmstat 1 | gzip > ${outputdir}/vmstat.out.gz &
    iostat -mx 1 | gzip > ${outputdir}/iostat.out.gz &
fi

mysqladmin ${MYSQL_OPTIONS} ext -i1 | gzip > ${outputdir}/mysqladmin.out.gz &

# uncomment to enable
#./pcs-collect-queryresponsetime.sh |gzip > ${outputdir}/queryresponsetime.out.gz &

function capture_innodb_metrics() {
  interval=1
  while [ ! -f ${outputdir}/collection_stop ]
  do
    mysql ${MYSQL_OPTIONS} -e "select name, subsystem, count, status from information_schema.INNODB_METRICS WHERE status='enabled'" \
            | gzip >> $outputdir/innodb_metrics.out.gz
    echo "" | gzip >> $outputdir/innodb_metrics.out.gz
    sleep ${interval}
  done
}
if [ "$MYSQLVERSION" -ge "56" ]; then
  capture_innodb_metrics &
fi

function capture_innodb_status () {
  interval=60

  while [ ! -f ${outputdir}/collection_stop ]
  do
    mysql ${MYSQL_OPTIONS} -e "show engine innodb status\G" \
      | gzip >> $outputdir/innodb_status.out.gz
    sleep ${interval}
  done
}
capture_innodb_status &

function capture_processlist () {
  interval=60

  while [ ! -f ${outputdir}/collection_stop ]
  do
    (echo "#TS $(date '+%Y-%m-%d_%H-%M-%S')"; mysql ${MYSQL_OPTIONS} -e "show full processlist\G";) \
      | gzip >> $outputdir/processlist.out.gz
    sleep ${interval}
  done
}
if [ "$COLLECTPROCESSLIST" != "" ]; then
  capture_processlist &
fi

function capture_psauxf () {
  interval=10

  while [ ! -f ${outputdir}/collection_stop ]
  do
    (echo "#TS $(date '+%Y-%m-%d_%H-%M-%S')"; ps auxf;) \
      |  gzip >> $outputdir/psauxf.out.gz
    sleep ${interval}
  done
}
capture_psauxf &

function capture_slave_status () {
  interval=1

  mysql ${MYSQL_OPTIONS} -e "show slave status" \
      | gzip >> $outputdir/slave_status.out.gz
  sleep ${interval}

  while [ ! -f ${outputdir}/collection_stop ]
  do
    mysql ${MYSQL_OPTIONS} --skip-column-names -e "show slave status" \
      | gzip >> $outputdir/slave_status.out.gz
    sleep ${interval}
  done
}
if [ "$COLLECTSLAVESTATUS" != "" ]; then
  capture_slave_status &
fi

function collect_diskstats {
  INTERVAL=1
  while true; do
     sleep=$(date +%s.%N | awk "{print $INTERVAL - (\$1 % $INTERVAL)}")
     sleep $sleep
     date +"TS %s.%N %F %T" | gzip >> ${outputdir}/diskstats.out.gz 
     cat /proc/diskstats | gzip >> ${outputdir}/diskstats.out.gz
  done  
}
if [ "$ISRDS" == "" ]; then
    collect_diskstats &
fi

function capture_tokudb_status () {
  interval=1

  while [ ! -f ${outputdir}/collection_stop ]
  do
    (echo "#TS $(date '+%Y-%m-%d_%H-%M-%S')"; mysql ${MYSQL_OPTIONS} -e "show engine tokudb status";) \
      | gzip >> $outputdir/tokudb_status.out.gz
    sleep ${interval}
  done
}
if [ "$COLLECTTOKUDB" != "" ]; then
  capture_tokudb_status &
fi

# get all bg jobs to kill
for i in $(jobs -p )
do 
  bg_jobs+=("$i")
done

################################


if [ "$duration" == "ctrlc" ]; then
  
  while true; 
  do
    check_disk_space
    sleep 60;
  done

else
  counter=0
  while [ "$counter" -le "$duration" ]; 
  do
    check_disk_space
    counter=$(($counter+1))
    sleep 60
  done
fi

kill_collection
