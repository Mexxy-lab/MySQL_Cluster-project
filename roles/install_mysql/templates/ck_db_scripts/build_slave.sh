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
# Purpose: This script should be used to build slaves of monolithic and shards
#          from one of the opsdb servers.
# Usage  : Please run script_name.sh --help on how to run the script.
#
###############################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
DT=`date "+%Y-%m-%d_%H%M%S"`
HOST_FILE=/tmp/hostfile_${SCRIPT_NAME}.$$
TMP_FILE=/tmp/tmpfile_${SCRIPT_NAME}.$$
export DONE_LIST=/tmp/done_${SCRIPT_NAME}.$$

TOOLS_MYCNF=${HOME}/.tools.$$.cnf
cat > $TOOLS_MYCNF << EOL
!include /etc/my.cnf
[client]
user=$TOOLS_USER
password=$TOOLS_PASSWD
EOL

SOURCE_MYCNF=${HOME}/.source.$$.cnf
cat > $SOURCE_MYCNF << EOL
!include /etc/my.cnf
[client]
user=$USER
password=$PASSWD
EOL

LOCAL_MYCNF=${HOME}/.local.$$.cnf
cat > $LOCAL_MYCNF << EOL
!include /etc/my.cnf
[client]
user=$BACKUP_USER
password=$BACKUP_PASSWD
EOL

export SOURCE_AUTH="mysql --defaults-extra-file=$SOURCE_MYCNF"
export TOOLS_AUTH="mysql --defaults-extra-file=$TOOLS_MYCNF"
export LOCAL_AUTH="mysql --defaults-extra-file=$LOCAL_MYCNF"

export SOURCE_MYCNF TOOLS_MYCNF LOCAL_MYCNF

export BKPUSER=`whoami`
export SLACK_EMAIL="k6a1q8d6f6d2z2b7@ckcorp.slack.com" 

debug() {
  if [ "$1" == "[Error]" ]
  then
      echo "$2 Exiting..."
      rm -f $TMP_FILE $HOST_FILE $DONE_LIST $TOOLS_MYCNF $SOURCE_MYCNF $LOCAL_MYCNF $WRAPPER_FILE /tmp/${SCRIPT_NAME}_wrap_*.$$
      exit 1
  fi
}

send_notification_build_slave(){
    host=$(hostname)
    subject=${1}
    body="${2}\n${@}"
    timeout 4 curl -X POST --data-urlencode "payload={\"channel\": \"#uk-db-jobs-notifications\", \"username\": \"${host} - ${0}\", \"text\": \"${subject}\n${body}.\", \"icon_emoji\": \":ghost:\"}"   ${UK_SLACK_WEBHOOK}
}

#---------------------------------------------------------------------- help --
help(){
  echo '''
  This script should be used to build a slave from given source.
  
  Usage:
      sh $SCRIPT_NAME.sh < REQUIRED > [ OPTIONAL ]
  
      Required:
             -r | --role              MySQL Role (ie. mono, shard, ticket, monovp)
             -s | --source            Source Hostname or source datacenter.groupname (ie. fodb001.sjc1, ckw.fodb)
             -t | --target            Target Hostname or target datacenter.groupname (ie. fldb001.sjc1, ckw.budb)
   
      Optional:
             --topology               Slave topology. Default: child. (ie. child, sibling)
             -m | --memory            Memory required for Prepare phase. Default: 16G. (ie. 1G, 16G)
             -n | --instance-number   Instance Number. Default: All shards. (ie 1,3 , 1-4)
             --parallel               Parallelism. Default: 1 (ie. 2, 4)
             --serialize              Serialize. Only one build at a time.
             --force                  Option to run innobackup even if the source is R/W Master (ie. 1)
             --compress               uses xtrabackup compression, requires qpress installed on target server
  
      Example:
              sh $SCRIPT_NAME.sh --role mono --source mdb001.sjc1 --target mdb002.sjc1
              sh $SCRIPT_NAME.sh --role shard --source fldb001.sjc1 --target budb001.sjc1 --topology sibling --instance-number 5-6 --parallel 2
              sh $SCRIPT_NAME.sh --role ticket --source ckw.fldb --target ckw.budb -n 1-30
  '''
}

#-------------------------------------------------------------- process_args --
process_args() {

  options=$@

  # An array with all the arguments
  args=($options)

  [[ $args == "--help" || $args == "" ]] && help && exit 1

  V_FORCE="N"
  V_SERIALIZE="N"
  V_COMPRESS="N"
  i=0
  for arg in $options
  do
      if [[ ${args[$i]:0:1} == "-" && ${args[$i+1]:0:1} != "-" ]]
      then
          case ${args[$i]} in
              -r | --role )             V_ROLE=${args[$i+1]};;
              -s | --source )           V_SOURCE_HOSTNAME=${args[$i+1]};;
              -t | --target )           V_TARGET_HOSTNAME=${args[$i+1]};;
              --topology )              V_TOPOLOGY=${args[$i+1]};;
              -m | --memory )           V_MEMORY=${args[$i+1]};;
              --parallel )              V_PARALLEL=${args[$i+1]};;
              --serialize )             V_SERIALIZE="Y";;
              --compress )              V_COMPRESS="Y";;
              -n | --instance-number )  V_INSTANCE_NUMBER=${args[$i+1]};;
              --force )                 V_FORCE="Y";;
               *)                       echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      else
          case ${args[$i]} in
              --force )                 V_FORCE="Y";;                                                                                                                        
              --serialize )             V_SERIALIZE="Y";;
              --compress )              V_COMPRESS="Y";; 
          esac    
          i=$(($i+1))
      fi
  done

  [ -z "${V_ROLE}" ] && debug "[Error]" "Please specify 'Role' for --role option. See --help for help." && exit 1
  [ -z "${V_TARGET_HOSTNAME}" ] && debug "[Error]" "Please specify 'Target Hostname' for --target option. See --help for help." && exit 1
  [ -z "${V_SOURCE_HOSTNAME}" ] && debug "[Error]" "Please specify 'Source Hostname' for --source option. See --help for help." && exit 1
  [ -z "${V_TOPOLOGY}" ] && V_TOPOLOGY="child"
  [ -z "${V_MEMORY}" ] && V_MEMORY=16G
  [ -z "${V_PARALLEL}" ] && V_PARALLEL=1

  RANGE=""                                                                                                                                                                                
  if [ ! -z "${V_INSTANCE_NUMBER}" ]
  then
      RANGE="and s.shardNumber in (`echo $V_INSTANCE_NUMBER | awk 'BEGIN { RS=","; FS="-"; ORS="" } NR > 1 { print "," } NF > 1  { for (i=$1; i<$2; ++i) { print i "," } print $2; next } { print $1 }'`)"
  fi    
  
  if [[ "${V_ROLE}" == *"shard"* ]] 
  then
      if [[ "${V_SOURCE_HOSTNAME}" == *"euw2"* ]]
      then
         S_DC=`echo $V_SOURCE_HOSTNAME | cut -d '.' -f1`
         S_GROUP=`echo $V_SOURCE_HOSTNAME | cut -d '.' -f2`
         RANGE="$RANGE and s.dataCenter = '$S_DC' and s.groupName = '$S_GROUP'"
      else
         RANGE="$RANGE and s.hostName='$V_SOURCE_HOSTNAME' and t.hostName='$V_TARGET_HOSTNAME'"
      fi   
      if [[ "${V_TARGET_HOSTNAME}" == *"euw2"* ]]
      then
         T_DC=`echo $V_TARGET_HOSTNAME | cut -d '.' -f1`
         T_GROUP=`echo $V_TARGET_HOSTNAME | cut -d '.' -f2`
         RANGE="$RANGE and t.dataCenter = '$T_DC' and t.groupName = '$T_GROUP'"                                                                                            
      else
         RANGE="$RANGE and s.hostName='$V_SOURCE_HOSTNAME' and t.hostName='$V_TARGET_HOSTNAME'"
      fi
      RANGE-"$RANGE and s.instanceName = t.instanceName"
  else
      RANGE="$RANGE and s.hostName=  '$V_SOURCE_HOSTNAME' and t.hostName='$V_TARGET_HOSTNAME'"
      T_DC=`echo $V_TARGET_HOSTNAME | cut -d '.' -f2`
  fi

  if [[ "${T_DC}" == "iad1" || "${T_DC}" == *"cke"* ]]
  then
    export DBA_EMAIL="dba@creditkarma.com,storeng@creditkarma.com"
  else
    export DBA_EMAIL="dba@creditkarma.com"
  fi

  $TOOLS_AUTH -NB -e"select concat(s.fqdn, \":\", s.port, \":\", s.multiInstance, \":\", t.fqdn, \":\", t.port, \":\", t.multiInstance) from $ADMIN_SCHEMA.$ADMIN_TABLE s, $ADMIN_SCHEMA.$ADMIN_TABLE t where s.role = t.role and t.role = '$V_ROLE' and s.shardNumber=t.shardNumber $RANGE" 2>/dev/null > $HOST_FILE
  [ ! -s $HOST_FILE ] && debug "[Error]" "Please check if 'Data Center' and/or 'Shard Group' is valid. It could be possible that you are initiating the build script from r/w master which is not allowed by default. Use --force to override."

  return 0
}

#----------------------------------------------------------- display_layout --
display_layout(){
  SLACK_EMAIL_FILE="/tmp/emailslack.$$"

  echo ""
  echo " -----------------------------------------------------------------------------------------------------------------------------------------"
  echo "|                BACKUP_SOURCE                |                  BUILD_TARGET               |                   NEW_MASTER                |"
  echo " -----------------------------------------------------------------------------------------------------------------------------------------"
  NUM=1
  while read LINE
  do
      S_HOST=`echo $LINE | cut -d":" -f1`
      S_PORT=`echo $LINE | cut -d":" -f2`
      S_INSTANCE_TYPE=`echo $LINE | cut -d":" -f3`
      T_HOST=`echo $LINE | cut -d":" -f4`
      T_PORT=`echo $LINE | cut -d":" -f5`
      T_INSTANCE_TYPE=`echo $LINE | cut -d":" -f6`
      
      if [ "$V_FORCE" == "N" ]
      then
          READ_ONLY=`$SOURCE_AUTH -h$S_HOST -P$S_PORT -NB -e"select @@global.read_only;" 2>/dev/null`
          [[ "$READ_ONLY" == "0" ]] && echo "Looks like '$S_HOST($S_PORT)' is master right now. Either change source or run as --force" && exit 
      fi 

      [ "$S_INSTANCE_TYPE" == "Y" ] && S_INSTANCE_TYPE="multi" || S_INSTANCE_TYPE="single"
      [ "$T_INSTANCE_TYPE" == "Y" ] && T_INSTANCE_TYPE="multi" || T_INSTANCE_TYPE="single"

      FILENUM=$(($NUM % $V_PARALLEL))

      $SOURCE_AUTH -h$S_HOST -P$S_PORT -e"show slave status\G" > $TMP_FILE
      NM_FQDN=`cat $TMP_FILE | grep "Master_Host" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      NM_PORT=`cat $TMP_FILE | grep "Master_Port" | cut -d":" -f2 |sed -e 's/^ *//' -e 's/ *$//'`
      
      NM_HOST=`$TOOLS_AUTH -NB -e"select fqdn from $ADMIN_SCHEMA.$ADMIN_TABLE where fqdn = '$NM_FQDN' group by hostName;" 2>/dev/null`

      [ "$NM_PORT" == "" ] && NM_PORT="-"
      [ "$NM_HOST" == "" ] && NM_HOST="-"

      if [ "$V_TOPOLOGY" == "child" ]
      then
          NM_PORT=$S_PORT
          NM_HOST=$S_HOST
      fi

      printf "| %38s:%s | %38s:%s | %38s:%s |\n" $S_HOST $S_PORT $T_HOST $T_PORT $NM_HOST $NM_PORT
      
      echo "$S_HOST($S_PORT) ---> $T_HOST($T_PORT)" >> $SLACK_EMAIL_FILE

      if [ "$V_SERIALIZE" == "Y" ]
      then
        RUNME=/tmp/${SCRIPT_NAME}_wrap.$$
      else
        RUNME=/tmp/${SCRIPT_NAME}_wrap_${S_HOST}_${FILENUM}.$$
      fi
      if [ "$V_COMPRESS" == "Y" ]
      then
          echo "sh $SCRIPT_DIR/source_${SCRIPT_NAME}.sh --role $V_ROLE --source $S_HOST,$S_PORT,$S_INSTANCE_TYPE --target $T_HOST,$T_PORT,$T_INSTANCE_TYPE --topology $V_TOPOLOGY --memory $V_MEMORY --compress &" >> $RUNME
          echo "wait" >> $RUNME
      else
          echo "sh $SCRIPT_DIR/source_${SCRIPT_NAME}.sh --role $V_ROLE --source $S_HOST,$S_PORT,$S_INSTANCE_TYPE --target $T_HOST,$T_PORT,$T_INSTANCE_TYPE --topology $V_TOPOLOGY --memory $V_MEMORY &" >> $RUNME
          echo "wait" >> $RUNME
      fi 
      NUM=$(( $NUM+1 ))
  
  done < $HOST_FILE
  echo " -----------------------------------------------------------------------------------------------------------------------------------------"

  WRAPPER_FILE=/tmp/wrapper.$$
  echo "#!/bin/bash" >> $WRAPPER_FILE
  echo ""
  echo "Below files will run commands in parallel"
  echo "" 
  for file in `ls /tmp |grep $SCRIPT_NAME | grep wrap | grep $$`
  do
     echo "# /tmp/$file"
     echo "--------------------------------"
     cat /tmp/$file |grep -v "wait"
     echo ""
     echo "sh /tmp/$file &" >> $WRAPPER_FILE
  done
  echo "wait" >> $WRAPPER_FILE

  return 0
}

#----------------------------------------------------------------- build_slaves --
build_slaves() {

  PASSWD_FILE=$HOME/.ssh-${V_TARGET_HOSTNAME}.$$.key
  # Starting ssh-agent
  ssh-agent -s > $PASSWD_FILE
  . $PASSWD_FILE > /dev/null
  ssh-add

  WHO=`logname`
  TOTAL=`cat $SLACK_EMAIL_FILE |wc -l`
  notification_body=$(cat $SLACK_EMAIL_FILE)
  send_notification_build_slave "$WHO has initiated $TOTAL Slave Build(s).", ${notification_body}
  # cat $SLACK_EMAIL_FILE | mail -s "$WHO has initiated $TOTAL Slave Build(s)." "$SLACK_EMAIL,$DBA_EMAIL"
  rm -f $SLACK_EMAIL

  sh $WRAPPER_FILE

  wait

  DONE=`cat $DONE_LIST | grep "Replication started" |wc -l`                                                                                                                  
  cat /dev/null > $SLACK_EMAIL_FILE
  if [ $DONE -gt 0 ] 
  then
      echo "Completed:" > $SLACK_EMAIL_FILE
      cat $DONE_LIST |grep -v "FAILED" >> $SLACK_EMAIL_FILE
      echo "" >> $SLACK_EMAIL_FILE
  fi
  if [ `cat $DONE_LIST |grep "FAILED" |wc -l` -gt 0 ] 
  then 
      echo "Failed:" >> $SLACK_EMAIL_FILE 
      cat $DONE_LIST |grep "FAILED" |cut -d ':' -f1,2 >> $SLACK_EMAIL_FILE
  fi
  notification_body=$(cat $SLACK_EMAIL_FILE)
  send_notification_build_slave "$WHO has completed $DONE/$TOTAL Slave Build(s).", ${notification_body}
  # cat $SLACK_EMAIL_FILE | mail -s "$WHO has completed $DONE/$TOTAL Slave Build(s)." "$SLACK_EMAIL,$DBA_EMAIL"

  # Stopping ssh-agent
  ssh-add -D > /dev/null 2>&1
  ssh-agent -k > /dev/null 2>&1
  rm -f $PASSWD_FILE

  # Removing temp files.
  rm -f $TMP_FILE $HOST_FILE $DONE_LIST $TOOLS_MYCNF $SOURCE_MYCNF $LOCAL_MYCNF $WRAPPER_FILE /tmp/${SCRIPT_NAME}_wrap_*.$$
  
  return 0
}

#----------------------------------------------------------------------- main --
# Main Script Processing
#
main () {
  process_args $*
  display_layout
  build_slaves
  return 0
}

main $*
