#!/bin/bash
# =============================================================================
# {% for line in fileBanner %}
# {{line}} {% endfor %}
# =============================================================================

###############################################################################
#
# Auther : Ashok Jivani
# Purpose: This script should be used to run backups using xtrabackup. 
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

BKP_MYCNF=/root/.my.cnf.$$
TMPFILE="/tmp/innobackupex-runner.$$.tmp"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"
[ -f $PARAMETER_FILE ] && . ${PARAMETER_FILE}

TODAY=`date "+%Y-%m-%dT%T%z"`

#---------------------------------------------------------------------- help --
help(){
  echo "" 
  echo "This script should be used to backup given database instance using xtrabackup."
  echo ""
  echo "Usage:"
  echo ""
  echo "sh $SCRIPT_NAME.sh < REQUIRED > [ OPTIONAL ]"
  echo ""
  echo "  Required:"
  echo "      -i | --instance-name  Instance Name (ie. mdb, sdb1)"
  echo ""
  echo "  Optional:"
  echo "      -r | --retention      Retention Period in Days. Default 30 days (ie. 15)"
  echo "      -p | --prepare        To run Prepare phase. Default No"
  echo "      -m | --memory         Memory required for Prepare phase. Default 16G (ie. 1G, 16G)"
  echo ""
  echo "  Example:"
  echo ""
  echo "     sh $SCRIPT_NAME.sh -i sdb1 --retention 30" 
  echo ""
  exit 1
}

#--------------------------------------------------------------------- debug --
debug() { 
    echo "`date "+%Y-%m-%d %H:%M:%S"` $1 $2" >> $LOG_FILE 2>&1
    [ "$1" == "[Error]" ] && rm -f $TMPFILE $BKP_MYCNF && exit 1
}

#-------------------------------------------------------------- process_args --
process_args() {

  options=$@

  # An array with all the arguments
  args=($options)

  [[ $args == "--help" || $args == "" ]] && help && exit 1

  V_PREPARE="N"
  i=0
  for arg in $options
  do
      if [[ ${args[$i]:0:1} == "-" && ${args[$i+1]:0:1} != "-" ]]
      then
          case ${args[$i]} in
            -i | --instance-name )    V_INSTANCE_NAME=${args[$i+1]};;
            -r | --retention )        V_RETENTION=${args[$i+1]};;
            -m | --memory )           V_MEMORY=${args[$i+1]};;   
            -p | --prepare )          V_PREPARE="Y";;
             *)                       echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      else
          case ${args[$i]} in
            -p | --prepare )           V_PREPARE="Y";;
          esac    
          i=$(($i+1))
      fi
  done

  [ -z "${V_INSTANCE_NAME}" ] && debug "[Error]" "Please specify 'Instance Name' for -i or --instance-name option. See --help for help"
  
  [ -z "${V_RETENTION}" ] && V_RETENTION=30
  [ -z "${V_MEMORY}" ] && V_MEMORY=16G

  LOG_FILE=/var/log/${SCRIPT_NAME}-${V_INSTANCE_NAME}.log
  V_GROUP=`cat /etc/my.cnf |grep "\[mysqld\|datadir" |grep "$V_INSTANCE_NAME" -B 1 |head -1 |tr -d "[]"`
  V_SOCKET=`sed -n "/\[$V_GROUP\]/,/\[/p" /etc/my.cnf |grep "socket" |awk -F"=" '{print $2}' |sed -e 's/^ *//' -e 's/ *$//'`
  V_DATADIR=`sed -n "/\[$V_GROUP\]/,/\[/p" /etc/my.cnf |grep "datadir" |awk -F"=" '{print $2}' |sed -e 's/^ *//' -e 's/ *$//'`
  
  [ ! -d $V_DATADIR ] && debug "Error"
  V_BASEDIR=`dirname $V_DATADIR`

cat > $BKP_MYCNF << EOL
!include /etc/my.cnf
[client]
user=$BACKUP_USER
password=$BACKUP_PASSWD
socket=$V_SOCKET
EOL
}

#----------------------------------------------------------------- innobackup --
innobackup(){

  BKP_STARTED_AT=`date +%s`
  FULLBACKUPDIR=/backup/xtrabackup-${V_INSTANCE_NAME}/full
  mkdir -p $FULLBACKUPDIR

  /usr/bin/innobackupex --defaults-file=$BKP_MYCNF --defaults-group=$V_GROUP --parallel=4 --slave-info $FULLBACKUPDIR > $TMPFILE 2>&1
 
  if [ -z "`tail -1 $TMPFILE | grep 'completed OK!'`" ] ; then
      debug "[Error]" "Backup=Failed host=`hostname` instance=$V_INSTANCE_NAME"
  else
      debug "[Info]" "Backup=Completed Backup_Time=$(( `date +%s` - BKP_STARTED_AT )) host=`hostname` instance=$V_INSTANCE_NAME"
  fi

 
  THISBACKUP=`awk -- "/Backup created in directory/ { split( \\\$0, p, \"'\" ) ; print p[2] }" $TMPFILE`

  if [ "$V_PREPARE" == "Y" ]
  then
     PREPARE_STARTED_AT=`date +%s`
     /usr/bin/innobackupex --ibbackup=xtrabackup_55 --use-memory=$V_MEMORY --apply-log $THISBACKUP > $TMPFILE 2>&1 
     
     if [ -z "`tail -1 $TMPFILE | grep 'completed OK!'`" ] 
     then
        debug "[Error]" "Prepare=Failed host=`hostname` instance=$V_INSTANCE_NAME"
     else
        touch $THISBACKUP/xtrabackup_is_prepared
        debug "[Info]" "Prepare=Completed Prepare_Time=$(( `date +%s` - PREPARE_STARTED_AT )) host=`hostname` instance=$V_INSTANCE_NAME"
     fi
  fi
}

#-------------------------------------------------------------------- cleanup --
cleanup(){
  CLEANUP_STARTED_AT=`date +%s`
  find $FULLBACKUPDIR -maxdepth 1 -type d -mtime +$V_RETENTION  -exec rm -rf {} \; 
  debug "[Info]" "Cleanup=Completed Cleanup_Time=$(( `date +%s` - CLEANUP_STARTED_AT )) host=`hostname` instance=$V_INSTANCE_NAME"
  rm -f $TMPFILE $BKP_MYCNF
}

#----------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  innobackup
  cleanup
  return 0
}

main $*
