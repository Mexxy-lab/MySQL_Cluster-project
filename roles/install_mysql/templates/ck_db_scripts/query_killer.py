#!/usr/bin/python
#Yevgeniy Gorbatenko, May 25,2016, query killer script
#The script is currently hardcoded to kill any select queries that have been running over 300 seconds on target host
#The killing functionality is currently disabled (cursor1.execute(killquery) since we don't have a clear, bullet-proof way to dtermine master server
#
#import mysql.connector
import MySQLdb
import datetime
import re
import mmap
import sys
import smtplib
import socket
#parameterfile = "/home/yevgeniy.gorbatenko/parameterlocal.txt"

class CredentialParser:
    def __init__(self,localhostname, port):
        if localhostname.startswith("mdb"):
            parameterfile = "/root/.my.cnf"
            with open (parameterfile, 'r+') as creds:
                allcreds = mmap.mmap(creds.fileno(),0)
                self.usermatch = re.search('user=(.*)', allcreds)
                self.passwordmatch = re.search('password=(.*)',allcreds)
                self.user=self.usermatch.group(1)
                self.password = self.passwordmatch.group(1)[1:-1]
                self.socket = "/db/data/mdb/mysql/mysql.sock"
                self.host = "localhost"
#            print localhostname + "mono"
        elif localhostname.startswith("vdb"):
            parameterfile = "/root/.my.cnf"
            with open (parameterfile, 'r+') as creds:
                allcreds = mmap.mmap(creds.fileno(),0)
                self.usermatch = re.search('user=(.*)', allcreds)
                self.passwordmatch = re.search('password=(.*)',allcreds)
                self.user=self.usermatch.group(1)
                self.password = self.passwordmatch.group(1)[1:-1]
                self.socket = "/db/data/vdb/mysql/mysql.sock"
                self.host = "localhost"
#            print localhostname + "vdb"
        elif localhostname.startswith("fldb") or localhostname.startswith("fodb"):
            parameterfile="/root/msdb" +str(int(port)-3300)
            with open (parameterfile, 'r+') as creds:
                allcreds = mmap.mmap (creds.fileno(),0)
                self.usermatch = re.search ('-u (.*) -p', allcreds)
                self.passwordmatch = re.search (' -p(.*)', allcreds)
                self.user = self.usermatch.group(1)
                self.password= self.passwordmatch.group(1)
                self.socket = "/db/data/sdb"+str(int(port)-3300)+"/mysql.sock"
                self.host = "localhost"
#            print localhostname + "shard"
        elif localhostname.startswith("opsdb"):
            parameterfile = "usr/local/ops/bin/parameter.txt"
            with open (parameterfile, 'r+') as creds:
                allcreds = mmap.mmap(creds.fileno(),0)
                self.user = re.search('USER=(.*)', allcreds)
                self.password = re.search('PASSWD=(.*)',allcreds)
            self.user = self.user[1:-1]
            self.password = self.password [1:-1]
#            print localhostname + "opsdb"
        elif localhostname.startswith("tkdb"):
            parameterfile = "/root/.my.cnf"
            with open (parameterfile, 'r+') as creds:
                allcreds = mmap.mmap(creds.fileno(),0)
                self.usermatch = re.search('user=(.*)', allcreds)
                self.passwordmatch = re.search('password=(.*)',allcreds)
            self.user=self.usermatch.group(1)
            self.password = self.passwordmatch.group(1)[1:-1]
            self.socket = "/db/data/tkdb"+str(int(localhostname[4:7]))+"/mysql/mysql.sock"
            self.host = "localhost"
            #            print localhostname + "ticket"
        else:
            print localhostname+" :no active config found, exiting"
            exit()


parameterfile = "/usr/local/ops/bin/parameter.txt"



if len(sys.argv) > 3:
    email=str(sys.argv[3])
else:
    errormessage="Usage: " + str(sys.argv[0]) + " minexecutiontime " + " <port> " + " <email> "
    print errormessage
    exit()

if __name__== '__main__':
    ourhostname=str(socket.gethostname())
    ourminquerytime=int(sys.argv[1])
    #print ourhostname
    credentials=CredentialParser(ourhostname,sys.argv[2])

    # Establishing connection to db
    try:
        ourcn1 = MySQLdb.connect(host='localhost',user=credentials.user,passwd=credentials.password, unix_socket=credentials.socket,port=int(sys.argv[2]) )
    except:
        exit (1)
    cursor1 = ourcn1.cursor()

    query1 = ("select id,user,host,db,command,time,state,info,rows_sent,rows_examined from information_schema.processlist where time>" + str(ourminquerytime) + " and Command not like 'Sleep'")
#    print query1
    cursor1.execute (query1)
    processlist = cursor1.fetchall()
    emailstring = 'Subject: slow queries\n\n'
    emailstringinitial = emailstring
    for row in processlist:
        if ( row[5] > ourminquerytime and re.search('^select',str(row[7]),re.IGNORECASE)):
 #          print row[0], row[5], row[7]
            killquery="kill " + str(row[0]) +";"
 #          cursor1.execute(killquery)
            emailstring=emailstring + "ProcessID: " + str(row[0]) + "  " + "User: " + str(row[1]) + "  " + "Host: " + str(row[2]) + "  " + "DB: " + str(row[3]) + "  " + "Duration: " + str(row[5]) + " sec   " + "Query: " + str(row[7])[:30] + " ; query will be killed " + "\n"
 #   print emailstring
    if (emailstring != emailstringinitial):
        ourmailer=smtplib.SMTP('localhost')
        ourmailer.sendmail(ourhostname,email,emailstring)
        ourmailer.quit()
    ourcn1.close()


