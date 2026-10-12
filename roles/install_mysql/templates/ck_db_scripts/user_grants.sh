#!/bin/bash

###############################################################################
#
# Author : Nived
# Purpose: Used to create users and Grant permissions specific to host groups
# Usage  : sh user_grants.sh -d cke -g {groupname}
#
###############################################################################

tstamp=`date +'%Y_%m_%d_%H%M%S'`
date=`date +'%Y%m%d%H%M%S'`
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARAMETER_FILE="${SCRIPT_DIR}/parameter.txt"

. ${PARAMETER_FILE}

SCRIPT_NAME=`basename $0 | sed -e "s/.sh$//"`
HOST_FILE=/tmp/${SCRIPT_NAME}_hostfile.$$
RESULT_FILE=/tmp/${SCRIPT_NAME}_resultfile.$$

# colors
RED=`tput setaf 1`
GREEN=`tput setaf 2`
NOCOLOR='\e[0m'

#---------------------------------------------------------------------- help --
help(){
  echo "###############################################################################"
  echo ""
  echo "This script should be used to grant user privileges and drop unknown users."
  echo ""
  echo "Usage:"
  echo ""
  echo "sh $SCRIPT_NAME.sh -d <DATA_CENTER> -g <SHARD_GROUP> "
  echo ""
  echo "  Required:"
  echo "      -d        Data Center code (ie. ckw, cke)"
  echo "      -g        Group (ie. mono, tkdb, fldb, fodb, budb, ipdb)"
  echo ""
  echo "  Optional:"
  echo "      -h or --hostname          Hostname (ie mdb001.iad1, fodb9.sjc1)"
  echo "      -u or --user              User (Ex: root, appserver). Should be used with -f"
  echo "      -f or --force             Drops and recreates the user"
  echo "      -r or --rollback          Used to rollback DROP user statements. Need to specify the backup directory"
  echo ""
  echo "  Example:" 
  echo "      sh $SCRIPT_NAME.sh -d ckw -g budb"
  echo "      sh $SCRIPT_NAME.sh -r grants_201701011200"
  echo ""
  echo "###############################################################################"
  exit 1
}

#-------------------------------------------------------------- process_args --

process_args() {

  options=$@

  # An array with all the arguments
  args=($options)

  [[ $args == "--help" || $args == "" ]] && help && exit 1
  
  force="N"
  i=0
  for arg in $options
  do
      if [[ ${args[$i]:0:1} == "-" && ${args[$i+1]:0:1} != "-" ]]
      then
          case ${args[$i]} in
             -d | --data-center )       datacenter=${args[$i+1]};;
             -g | --group )             group=${args[$i+1]};;
             -h | --hostname )          hostname=${args[$i+1]};;
             -u | --username )          username=${args[$i+1]};; 
             -f | --force )             force="Y" ;; 
             -i | --instance )          instance=${args[$i+1]};;
             -r | --rollback )          rollback=${args[$i+1]};;
             *)                         echo "Invalid option '${args[$i]}'" && exit 1;;
          esac
          i=$(($i+2))
      else
          case ${args[$i]} in
             -f | --force )          force="Y";;
          esac    
          i=$(($i+1))
      fi
  done

  return 0

}

verify_inputs() {

    dc=`mysql -NB -A ckadmin -e"select count(*) from $ADMIN_TABLE where dataCenter = '"$datacenter"'"`
    gn=`mysql -NB -A ckadmin -e"select count(*) from $USER_TABLE where groupName = '$group'"`
    hn=`mysql -NB -A ckadmin -e"select distinct hostName from $ADMIN_TABLE where hostName = '$hostname'"`
    in=`mysql -NB -A ckadmin -e"select distinct instanceName from $ADMIN_TABLE where instanceName = '$instance'"`

    if [[ "${username}" != "" && "${force}" != "Y" ]]; then
        
        echo -e "${RED}Cannot use -u without -f option ${NOCOLOR}"
        exit 99

    elif [[ "${datacenter}" == "" || "${dc}" == 0 ]]; then 

        echo -e "${RED}Invalid datacenter: ${datacenter} ${NOCOLOR}"
        exit 99

    elif [[ "${group}" == "" || "${gn}" == 0 ]]; then

        echo -e "${RED}Invalid Group: ${group} ${NOCOLOR}"
        exit 99

    elif [[ "${hn}" != "${hostname}" ]]; then

        echo -e "${RED}Invalid Hostname: ${hostname} ${NOCOLOR}"
        exit 99

    elif [[ "${in}" != "${instance}" ]]; then
               
        echo -e "${RED}Invalid instance: ${instance} ${NOCOLOR}"
        exit 99

    fi

}

fetch_hosts() {

    if [[ "${hostname}" == "" && "${instance}" == "" ]]; then 

        mysql -NB -A ckadmin -e"select concat(hostName, \":\", ipAddress, \":\", port) from $ADMIN_TABLE where groupName = '${group}' and dataCenter = '${datacenter}'" > $HOST_FILE
        [ $? -ne 0 ] && echo -e "${RED}Invalid Group: ${group} ${NOCOLOR}" && exit 99

    elif [[ "${hostname}" == "" && "${instance}" != "" ]]; then

        mysql -NB -A ckadmin -e"select concat(hostName, \":\", ipAddress, \":\", port) from $ADMIN_TABLE where groupName = '${group}' and dataCenter = '${datacenter}' and instanceName = '${instance}'" > $HOST_FILE
        [ $? -ne 0 ] && echo -e "${RED}Invalid Group: ${group} ${NOCOLOR}" && exit 99

    elif [[ "${hostname}" != "" && "${instance}" != "" ]]; then

        mysql -NB -A ckadmin -e"select concat(hostName, \":\", ipAddress, \":\", port) from $ADMIN_TABLE where hostName = '${hostname}' and groupName = '${group}' and dataCenter = '${datacenter}' and instanceName = '${instance}'" > $HOST_FILE
        [ $? -ne 0 ] && echo -e "${RED}Invalid host/group $hostname : $group'${NOCOLOR}" && exit 99

    elif [[ "${hostname}" != "" && "${instance}" == "" ]]; then

        mysql -NB -A ckadmin -e"select concat(hostName, \":\", ipAddress, \":\", port) from $ADMIN_TABLE where groupName = '${group}' and dataCenter = '${datacenter}' and hostName = '${hostname}'" > $HOST_FILE
        [ $? -ne 0 ] && echo -e "${RED}Invalid Group: ${group} ${NOCOLOR}" && exit 99

    fi

}


host_users() {

    cat $HOST_FILE|while read host

do

hname=`echo $host|cut -d ':' -f1`
hostip=`echo $host|cut -d ':' -f2`
hostport=`echo $host|cut -d ':' -f3`

    if [[ "${username}" == "" ]]; then
        mysql -NB -A ckadmin -e"select distinct concat(\"'\", userName, \"'@'\", userHost, \"'|\", \"'\", password, \"'\") from $USER_TABLE WHERE isDefault = 'Y' and dataCenter = '${datacenter}'" >> ${LOGDIR}/tmpgrants_users_${hname}_${hostport}.txt 
        mysql -NB -A ckadmin -e"select distinct concat(\"'\", userName, \"'@'\", userHost, \"'|\", \"'\", password, \"'\") from $USER_TABLE WHERE isDefault = 'N' and targetHost = '' and groupName = '${group}' and dataCenter = '${datacenter}'" >> ${LOGDIR}/tmpgrants_users_${hname}_${hostport}.txt
        mysql -NB -A ckadmin -e"select distinct concat(\"'\", userName, \"'@'\", userHost, \"'|\", \"'\", password, \"'\") from $USER_TABLE WHERE isDefault = 'N' and targetHost = '${hname}' and groupName = '${group}' and dataCenter = '${datacenter}'" >> ${LOGDIR}/tmpgrants_users_${hname}_${hostport}.txt

    else
        mysql -NB -A ckadmin -e"select distinct concat(\"'\", userName, \"'@'\", userHost, \"'|\", \"'\", password, \"'\") from $USER_TABLE where userName like '${username}' and isDefault = 'Y' and dataCenter = '${datacenter}'" >> ${LOGDIR}/tmpgrants_users_${hname}_${hostport}.txt
        mysql -NB -A ckadmin -e"select distinct concat(\"'\", userName, \"'@'\", userHost, \"'|\", \"'\", password, \"'\") from $USER_TABLE where userName like '${username}' and isDefault = 'N' and targetHost = '' and groupName = '${group}' and dataCenter = '${datacenter}'" >> ${LOGDIR}/tmpgrants_users_${hname}_${hostport}.txt
        mysql -NB -A ckadmin -e"select distinct concat(\"'\", userName, \"'@'\", userHost, \"'|\", \"'\", password, \"'\") from $USER_TABLE where userName like '${username}' and isDefault = 'N' and targetHost = '${hname}' and groupName = '${group}' and dataCenter = '${datacenter}'" >> ${LOGDIR}/tmpgrants_users_${hname}_${hostport}.txt

        [ $? -ne 0 ] && echo -e "${RED}Invalid username: ${username} ${NOCOLOR}"

    fi

done

}

user_comparison() {

        cat $HOST_FILE|while read host

    do

        hname=`echo $host|cut -d ':' -f1`
        hostip=`echo $host|cut -d ':' -f2`
        hostport=`echo $host|cut -d ':' -f3`

            if [[ "${force}" == "Y" && "${username}" != "" ]]; then
                
                mysql -h $hostip -P $hostport -u $USER -p${PASSWD} -A mysql -NB -e"SELECT concat(\"'\", User, \"'@'\", host, \"'\") from user WHERE User = '$username'" >> ${LOGDIR}/tmpgrants_existing_users_${hname}_${hostport}.txt 2>/dev/null
                cat ${LOGDIR}/tmpgrants_users_${hname}_${hostport}.txt >> ${LOGDIR}/tmpgrants_new_users_${hname}_${hostport}.txt 
                touch ${LOGDIR}/tmpgrants_users_retain_${hname}_${hostport}.txt 

            elif [[ "${force}" == "Y" ]]; then

                mysql -h $hostip -P $hostport -u $USER -p${PASSWD} -A mysql -NB -e"SELECT concat(\"'\", User, \"'@'\", host, \"'\") from user" >> ${LOGDIR}/tmpgrants_existing_users_${hname}_${hostport}.txt 2>/dev/null
                cat ${LOGDIR}/tmpgrants_users_${hname}_${hostport}.txt >> ${LOGDIR}/tmpgrants_new_users_${hname}_${hostport}.txt 
                touch ${LOGDIR}/tmpgrants_users_retain_${hname}_${hostport}.txt 

            else

                mysql -h $hostip -P $hostport -u $USER -p${PASSWD} -A mysql -NB -e"SELECT concat(\"'\", User, \"'@'\", host, \"'\") from user" >> ${LOGDIR}/tmpgrants_existing_users_${hname}_${hostport}.txt 2>/dev/null

                grep -vf ${LOGDIR}/tmpgrants_existing_users_${hname}_${hostport}.txt ${LOGDIR}/tmpgrants_users_${hname}_${hostport}.txt >> ${LOGDIR}/tmpgrants_new_users_${hname}_${hostport}.txt
                grep -vf ${LOGDIR}/tmpgrants_new_users_${hname}_${hostport}.txt ${LOGDIR}/tmpgrants_users_${hname}_${hostport}.txt >>${LOGDIR}/tmpgrants_users_retain_${hname}_${hostport}.txt

            fi

    done

}

create_user() {

    cat $HOST_FILE|while read host

do

    hname=`echo $host|cut -d ':' -f1`
    hostip=`echo $host|cut -d ':' -f2`
    hostport=`echo $host|cut -d ':' -f3`

    cat ${LOGDIR}/tmpgrants_new_users_${hname}_${hostport}.txt|while read user

do
    uname=`echo $user|cut -d '|' -f1`

    password=`echo $user|cut -d '|' -f2`

    dbuser=`echo $uname|cut -d '@' -f1`

    if [[ "${dbuser}" == "'ckdba'" || "${dbuser}" == "'root'" ]]; then

        echo -e "CREATE USER $uname IDENTIFIED BY ${password};">> ${CREATE_USER}_${hname}_${hostport}.sql

        mysql -NB -A ckadmin -e"SELECT concat(\"GRANT \", privileges, \" ON \", objectName, \" TO ${uname} WITH GRANT OPTION;\") from $USER_TABLE WHERE concat(\"'\", userName, \"'@'\", userHost, \"'\") = \"${uname}\" and dataCenter = '${datacenter}'" >> ${CREATE_USER}_${hname}_${hostport}.sql

    else

        echo -e "CREATE USER $uname IDENTIFIED BY ${password};">> ${CREATE_USER}_${hname}_${hostport}.sql
        mysql -NB -A ckadmin -e"SELECT concat(\"GRANT \", privileges, \" ON \", objectName, \" TO ${uname};\") from $USER_TABLE WHERE concat(\"'\", userName, \"'@'\", userHost, \"'\") = \"${uname}\" and dataCenter = '${datacenter}' and groupName = '${group}' OR concat(\"'\", userName, \"'@'\", userHost, \"'\") = \"${uname}\" and isDefault = 'Y' and dataCenter = '${datacenter}'" >> ${CREATE_USER}_${hname}_${hostport}.sql

    fi

done

done

}

drop_user() {

    cat $HOST_FILE|while read host

do
    hname=`echo $host|cut -d ':' -f1`
    hostip=`echo $host|cut -d ':' -f2`
    hostport=`echo $host|cut -d ':' -f3`

    cat ${LOGDIR}/tmpgrants_users_retain_${hname}_${hostport}.txt|while read line

    do
        uname=`echo $line|cut -d '|' -f1`

        echo -e "${uname}" >> ${RETAIN_USER}_${hname}_${hostport}.txt

    done

if [[ "${force}" == "Y" && "${username}" != "" ]]; then

    #cat ${LOGDIR}/tmpgrants_new_users_${hname}_${hostport}.txt |cut -d '|' -f1|awk '{print "DROP USER "$1" ;"}'> ${DROP_USER}_${hname}_${hostport}.sql
    cat ${LOGDIR}/tmpgrants_existing_users_${hname}_${hostport}.txt |cut -d '@' -f1|sed "s/'//g"|while read duser

    do

        mysql -h $hostip -P $hostport -u $USER -p${PASSWD} -NB -A mysql -e"select distinct concat(\"'\", User, \"'@'\" , Host, \"'\") from mysql.user where User = '${duser}'" >> ${LOGDIR}/tmpgrants_drop_users_${hname}_${hostport}.sql 2>/dev/null

    done

    cat ${LOGDIR}/tmpgrants_drop_users_${hname}_${hostport}.sql|awk '{print "DROP USER "$1" ;"}'|sort -u > ${DROP_USER}_${hname}_${hostport}.sql

elif [[ "${force}" == "Y" ]]; then

    cat ${LOGDIR}/tmpgrants_existing_users_${hname}_${hostport}.txt |cut -d '@' -f1|sed "s/'//g"|while read duser

    do

        mysql -h $hostip -P $hostport -u $USER -p${PASSWD} -NB -A mysql -e"select distinct concat(\"'\", User, \"'@'\" , Host, \"'\") from mysql.user" >> ${LOGDIR}/tmpgrants_drop_users_${hname}_${hostport}.sql 2>/dev/null

    done

    cat ${LOGDIR}/tmpgrants_drop_users_${hname}_${hostport}.sql|awk '{print "DROP USER "$1" ;"}'|sort -u > ${DROP_USER}_${hname}_${hostport}.sql

else

    touch ${RETAIN_USER}_${hname}_${hostport}.txt
    
    grep -vf  ${RETAIN_USER}_${hname}_${hostport}.txt ${LOGDIR}/tmpgrants_existing_users_${hname}_${hostport}.txt |awk '{print "DROP USER "$1" ;"}'|sort -u > ${DROP_USER}_${hname}_${hostport}.sql

fi

    sro=`mysql -h $hostip -P $hostport -u $USER -p${PASSWD} -NB -e"show variables like 'super_read_only';" 2>/dev/null|awk '{print $2}'`

    if [[ "${sro}" == "ON" ]]; then

    echo "set global super_read_only=OFF;" >>${BACKUPDIR}/grants_backup_${hname}_${hostport}.dat

    fi
    
    echo "SET sql_log_bin = 0;" >> ${BACKUPDIR}/grants_backup_${hname}_${hostport}.dat
    cat ${DROP_USER}_${hname}_${hostport}.sql|grep -vE "root|''"|sed -e "s/DROP USER /SHOW GRANTS FOR /g" > ${BACKUPDIR}/grants_backup_${hname}_${hostport}.sql
    cat ${BACKUPDIR}/grants_backup_${hname}_${hostport}.sql|mysql -h $hostip -P $hostport -u $USER -p${PASSWD} -NB 2>/dev/null|sed -e "s/$/;/g" >> ${BACKUPDIR}/grants_backup_${hname}_${hostport}.dat

    if [[ "${sro}" == "ON" ]]; then

    echo "set global super_read_only=${sro};" >>${BACKUPDIR}/grants_backup_${hname}_${hostport}.dat

    fi

done

}

main() {

echo -e "\n Generating grant statements ...\n"

process_args $*

verify_inputs

fetch_hosts

host_users

user_comparison

drop_user

create_user

cat $HOST_FILE|while read host

do

    hname=`echo $host|cut -d ':' -f1`
    hostip=`echo $host|cut -d ':' -f2`
    hostport=`echo $host|cut -d ':' -f3`

    cat ${DROP_USER}_${hname}_${hostport}.sql|awk '{print $3}'> ${LOGDIR}/tmpgrants_user_drp_${hname}_${hostport}.txt
    touch ${CREATE_USER}_${hname}_${hostport}.sql 
    cat ${CREATE_USER}_${hname}_${hostport}.sql|grep CREATE|awk '{print $3}'> ${LOGDIR}/tmpgrants_user_crt_${hname}_${hostport}.txt

      echo -e " ${GREEN}HOSTNAME: $hname : $hostport\n ${NOCOLOR}" 


   if [[ "${force}" == "Y" ]]; then


       echo " ----------------------------------------------------------------------------------------"
       echo "|                 NEW USERS                |                  DROP USERS                 |"
       echo " ----------------------------------------------------------------------------------------"

       pr -m -t ${LOGDIR}/tmpgrants_user_crt_${hname}_${hostport}.txt ${LOGDIR}/tmpgrants_user_drp_${hname}_${hostport}.txt -w 100

   else

      echo " --------------------------------------------------------------------------------------------------------------------------------------"
      echo "|                 NEW USERS              |                  RETAIN USERS                 |                  DROP USERS                 |"
      echo " --------------------------------------------------------------------------------------------------------------------------------------"

      pr -m -t ${LOGDIR}/tmpgrants_user_crt_${hname}_${hostport}.txt ${RETAIN_USER}_${hname}_${hostport}.txt ${LOGDIR}/tmpgrants_user_drp_${hname}_${hostport}.txt -w 135

  fi

done

    echo "Do you want to contine(yes/no)?"
    read CONFIRM                                                                                                                                                                                
    if [[ "$CONFIRM" != "yes" ]]; then

        echo -e "Exiting ....."  
        rm -fr ${LOGDIR}
        exit 99

    else
        
        cat $HOST_FILE|while read host

        do

            hname=`echo $host|cut -d ':' -f1`
            hostip=`echo $host|cut -d ':' -f2`
            hostport=`echo $host|cut -d ':' -f3`

            sro=`mysql -h $hostip -P $hostport -u $USER -p${PASSWD} -NB -e"show variables like 'super_read_only';" 2>/dev/null|awk '{print $2}'`

            if [[ "${sro}" == "ON" ]]; then

                echo "set global super_read_only=OFF;" >>${LOGDIR}/${hname}_${hostport}.sql

            fi

            echo "SET sql_log_bin = 0;" >> ${LOGDIR}/${hname}_${hostport}.sql

            cat ${DROP_USER}_${hname}_${hostport}.sql ${CREATE_USER}_${hname}_${hostport}.sql>> ${LOGDIR}/${hname}_${hostport}.sql
           
             if [[ "${sro}" == "ON" ]]; then

                echo "set global super_read_only=${sro};" >>${LOGDIR}/${hname}_${hostport}.sql

             fi
            
            #cat ${LOGDIR}/${hname}_${hostport}.sql
            cat ${LOGDIR}/${hname}_${hostport}.sql|mysql -h ${hostip} -P ${hostport} -u $USER -p${PASSWD} -A mysql -vvv 2>/dev/null
            [ $? -ne 0 ] && echo -e "${RED}Error Occured While executing the grants. Exiting ..... ${NOCOLOR}"

        done

        echo -e "\nTo restore from '$SCRIPT_NAME.sh $@' execute: sh ${SCRIPT_NAME}.sh -r ${date}\n"

    fi

}

rollback() {

    if [ -d "/var/log/dblogs/grants_${rollback}" ]; then

    mkdir -p /var/log/dblogs/grants_${rollback}/rollback
    ROLLBACKDIR=/var/log/dblogs/grants_${rollback}/rollback
    BACKUPDIR=/var/log/dblogs/grants_${rollback}/backup

    ls -l ${BACKUPDIR}|awk '{print $9}'|grep -i ".dat"|while read line

        do
            hname=`echo $line|cut -d '_' -f3`
            hport=`echo $line|cut -d '_' -f4|cut -d '.' -f1`
            hostip=`mysql -NB -A ckadmin -e"select ipAddress from host_info where hostName = '${hname}' and port = '${hport}'"`

            echo -e "\nExecuting Rollback on ${hname}:${hport}"

            cat ${BACKUPDIR}/$line|mysql -h ${hostip} -P ${hport} -u $USER -p${PASSWD} -vvv 2>/dev/null|tee ${ROLLBACKDIR}/rollback_${hname}_${hport}.log
            #cat ${BACKUPDIR}/$line |tee ${ROLLBACKDIR}/rollback_${hname}_${hport}.log

        done
else

    echo -e "${RED}Backup Directory does not exist for Rollback ${NOCOLOR}"
    exit 99;

    fi

}

process_args $*

if [[  "$rollback" == "" ]]; then

    mkdir -p /var/log/dblogs/grants_${date}/backup
    LOGDIR=/var/log/dblogs/grants_${date}
    CREATE_USER=${LOGDIR}/create_users_$$
    DROP_USER=${LOGDIR}/drop_users_$$
    RETAIN_USER=${LOGDIR}/retain_users_$$
    BACKUPDIR=${LOGDIR}/backup

    main $* |tee ${LOGDIR}/user_grants_${tstamp}.log
    rm -f ${LOGDIR}/tmpgrants* 

else

    rollback $* 

fi
