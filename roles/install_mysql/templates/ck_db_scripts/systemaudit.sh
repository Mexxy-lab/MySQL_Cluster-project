#!/bin/bash
# =============================================================
#
# Purpose : To check system config 
#
# =============================================================

RED='\033[31m'
NC='\033[0m'

help(){
  echo '''
  This script is used to audit system config on db servers 
  
  Usage:
      sh $SCRIPT_NAME.sh [all|pass|fail] 
      Example:
              sh $SCRIPT_NAME.sh all
              sh $SCRIPT_NAME.sh pass 
              - pass will print passed checks 
              - fail will print failed checks
              - all  will print both pass and fail

  System checks :

   1. IO Scheduler should be set to noop

   2. Cpuspeed should be disabled

   3. Open file limit should be set to 65535 for root user

   4. NUMA should be disabled

   5. Transparent Huge Pages (TPH) should be disabled

   6. Swap should be disabled

   7. Set aio-max-nr to 1048576 on budb servers

   8. Selinux should be either disabled or if enabled then mode should be permissive.

  '''
}

# Check arguments 

if [ -z "$1" -o "$1" == "" ]
then
      echo "Please pass the required arguments"
      help
      exit 3

    elif [ "$1" == "pass" -o "$1" == "fail" -o "$1" == "all" ]
    then

      modeval=$1
    else
      help
      exit 3
fi

process_checks()
{
rm /tmp/passchecks.log
rm /tmp/failchecks.log

swapvalue=`cat /etc/sysctl.conf | grep -i swappiness | cut -d'=' -f2`

if [ "$swapvalue" -eq  0  ]

then
   echo "swappiness:$swapvalue:0:PASS" > /tmp/passchecks.log ;
 else
   echo "swappiness:$swapvalue:0:FAIL" > /tmp/failchecks.log ;
fi


thpvalue=`cat /sys/kernel/mm/transparent_hugepage/enabled | cut -d "[" -f2 | cut -d "]" -f1`

if [ "$thpvalue" == "never"  ]

then 
      echo "THP:$thpvalue:never:PASS " >> /tmp/passchecks.log ;
      else
           echo "THP:$thpvalue:never:FAIL" >> /tmp/failchecks.log ;
         fi


ioschedval=`cat /sys/block/sdb/queue/scheduler | cut -d "[" -f2 | cut -d "]" -f1`



if [ "$ioschedval" == "noop"  ]

then
     echo "IO Scheduler:$ioschedval:noop:PASS" >> /tmp/passchecks.log ;
else
      echo "IO Scheduler:$ioschedval:noop:FAIL" >> /tmp/failchecks.log ;
    fi



filelim=`grep -i root /etc/security/limits.conf | awk '{print $4}' | grep -c 65535`
filelimv=`grep -i root /etc/security/limits.conf | awk '{print $4}' | xargs | sed -e 's/ /,/g'`

if [ "$filelim" -eq 2 ]

then
    echo -e "OpenFilelim:$filelimv:65535,65535:PASS" >> /tmp/passchecks.log ; 
  else
    echo -e "OpenFilelim:$filelimv:65535,65535:FAIL" >> /tmp/failchecks.log ;
    

  fi     


checksel=`getenforce`

if [ "$checksel" == "Enforcing" ]
   then 
     echo -e "selinux:`getenforce`:Disabled:FAIL" >> /tmp/failchecks.log
   else 
     echo -e "Selinux:`getenforce`:Disabled:PASS" >> /tmp/passchecks.log
   fi


aioval=`cat /proc/sys/fs/aio-max-nr`

if [ "$aioval" -eq 1048576 ]
   then
     echo -e "asynchronousio:`cat /proc/sys/fs/aio-max-nr`:1048576:PASS" >> /tmp/passchecks.log

   else
     echo -e "asynchronousio:`cat /proc/sys/fs/aio-max-nr`:1048576:FAIL" >> /tmp/failchecks.log


fi



cpuspeedchk=`service cpuspeed status | grep -c stopped`

if [ "$cpuspeedchk" -eq 1 ]
    then 
      echo -e "cpuspeedcheck: `service cpuspeed status`:cpuspeed is stopped:PASS" >> /tmp/passchecks.log
    else
      echo -e "cpuspeedcheck: `service cpuspeed status`:cpuspeed is stopped:FAIL" >> /tmp/failchecks.log
fi


chknuma=`numactl --hardware | grep -i available | grep -c '1 nodes'`

if [ "$chknuma" -eq 1 ]
    then
      echo -e "NUMA settings : Enabled : Enabled :PASS" >> /tmp/passchecks.log
    else  
      echo -e "NUMA settings : Disabled  : Enabled :FAIL" >> /tmp/failchecks.log
   fi

sleep 1
touch /tmp/allchecks.log
cat /tmp/passchecks.log /tmp/failchecks.log > /tmp/allchecks.log 

}



display_layout()
{

  
if [ "$modeval" == "pass" ]   
then
  displayfile='/tmp/passchecks.log'
elif [ "$modeval" == "fail" ]
then
  displayfile='/tmp/failchecks.log'
elif [ "$modeval" == "all" ]
then 
  displayfile='/tmp/allchecks.log'
fi

echo " -----------------------------------------------------------------------------------------"
printf "| %20s | %20s | %20s | %20s |\n" "Parameter" "Found" "Expected" "Status"
echo " -----------------------------------------------------------------------------------------"
#printf "| %20s | %20s | %20s | %20s |\n" "--------------------" "------------------" "-----------------" "--------------------"
while read LINE
do

    P_NAME=`echo $LINE | cut -d":" -f1`
    C_VALUE=`echo $LINE | cut -d":" -f2`
    E_VALUE=`echo $LINE | cut -d":" -f3`
    C_STATUS=`echo $LINE | cut -d":" -f4`
    printf "| %20s | %20s | %20s | %20s |\n" "$P_NAME" "$C_VALUE" "$E_VALUE" "$C_STATUS"

        done < $displayfile 
}
echo ""
echo ""


main()
{
  process_checks
  display_layout

}


main $*
