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
# Purpose: This script should be used to build slaves in monolithic and shards. 
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

#---------------------------------------------------------------- create_dirs --
create_dirs () {
    
    # Removing old directories if any 
    [ -d $T_DATADIR/mysql ] && rm -rf $T_DATADIR/mysql
    [ -d $T_DATADIR/incoming ] && rm -rf $T_DATADIR/incoming/*
    [ -d $T_DATADIR/tmp ] && rm -rf $T_DATADIR/tmp
    [ -d $T_DATADIR/logs/binlogs ] && rm -rf $T_DATADIR/logs/binlogs
    [ -d $T_DATADIR/relaylogs ] && rm -rf $T_DATADIR/relaylogs
    [ -d $T_DATADIR/generallogs ] && rm -rf $T_DATADIR/generallogs

    mkdir -p $T_DATADIR/{incoming,tmp,logs} 
    mkdir -p $T_DATADIR/logs/{binlogs,slowlogs,relaylogs,generallogs} 
    chown -R $BKPUSER:{{ dbadmin_group }} $T_DATADIR/incoming $T_DATADIR/tmp
    chown -R {{ db_os_user }}:{{ dbadmin_group }} $T_DATADIR/logs
}
#-------------------------------------------------------------- open_listener --
#open_listener(){
#    
#    OPTS=""
#    [[ `/usr/bin/xtrabackup -v 2>&1 |grep "2.4.9"` ]] && OPTS="--parallel=8"
#
#    # Opening a listening port on this machine.
#    nc -j -l $T_PORT | xbstream $OPTS -x -C /db/data/$T_INSTANCENAME/incoming
#    
#    chown -R $BKPUSER:$BKPUSER /db/data/$T_INSTANCENAME/incoming
#}

#---------------------------------------------------------------- start_slave --
start_slave () {

    [ "$T_DATADIR" == "" ] && echo "Datadir is not specified." && exit 1
    [ "$T_INSTANCE_TYPE" == "" ] && echo "Instance Type is not specified." && exit 1

    [ ! -d $T_DATADIR/incoming ] && echo "Incoming directory does not exits." && exit 1 

    mv $T_DATADIR/incoming $T_DATADIR/mysql
    chown -R {{ db_os_user }}:{{ dbadmin_group }} $T_DATADIR
    chmod 755 $T_DATADIR/mysql

    # Starting MySQL

    if [[ "$T_INSTANCE_TYPE" == "single" ]] 
    then
        nohup service {{lc_sid}} start &
    else
        T_INSTANCENUM=$(($T_PORT % 3300))
        mysqld_multi start $T_INSTANCENUM
    fi

    # Keep checking every 5 seconds for 1 hour until MySQL gets started.

    for i in {1..720}
    do  
        [ `netstat -lnt | awk '$4 ~ /:'$T_PORT'$/' |wc -l` -gt 0 ] && exit
        sleep 5
    done

    # Sending signal that MySQL failed to start.
    exit 1
}

#--------------------------------------------------------------- process_args --
process_args () {

    # Processing incoming parameters.
    T_DATADIR="$1"
    T_PORT="$2"
    T_INSTANCE_TYPE="$3"
    BKPUSER=$4
    RUNME="$5"
    $RUNME
}

#----------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  return 0
}

main $*
