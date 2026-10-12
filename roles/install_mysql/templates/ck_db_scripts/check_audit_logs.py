#!/usr/bin/python -tt

import sys
import re
import os
import time
import datetime
import smtplib

def scan_audit(filename,tf):

  global alert
  global auditstring

  auditstring = ""

  if not os.path.isfile(filename):
    print 'Audit Log File %s is missing' % filename
    sys.exit(2)

  currtime = int(time.time())
  f = open(filename,'rU')
  list = f.readlines()
  f.close()

  list.reverse()

  for line in list:
    ts = re.search(r'date\":\"\d\d\d\d\d\d\d\d\d\d', line)
    ts = ts.group().replace('date\":\"','')
    if int(ts) > (currtime - tf):
      dropevent = re.search(r'drop_table',line.lower())
      setevent = (re.search(r'set_option',line.lower()) and re.search(r'set global',line.lower()))
      alterevent = (re.search(r'alter_table',line.lower()) and re.search(r'drop',line.lower()))
      killevent = re.search(r'kill',line.lower())

      if dropevent:
        temptab = re.search(r'"name":"_[\w]+old"',line.lower())
        if temptab == None:
          print "Critical: Drop event found in",filename, '-', time.ctime(int(ts))
          auditstring = auditstring+line
          alert = 1

      if setevent:
        expected_set = re.search(r'"cmd":"set_option","query":"set global slow_query_log',line.lower())
        set_day = datetime.datetime.fromtimestamp(int(ts)).strftime('%A')
        set_hour = datetime.datetime.fromtimestamp(int(ts)).strftime('%H')

        if expected_set == None or set_day != 'Monday' or set_hour != '00':
          print "Critical: Set global event found in",filename, '-', time.ctime(int(ts))
          auditstring = auditstring+line
          alert = 1

      if killevent:
        print "Critical: Kill event found in",filename, '-', time.ctime(int(ts))
        auditstring = auditstring+line
        alert = 1

      if alterevent:
        print "Critical: Alter table drop event found in",filename, '-', time.ctime(int(ts))
        auditstring = auditstring+line
        alert = 1

      else:
        break

def send_email_alert(audits):

  sender = 'DBAudit'
  receivers = ['dba@creditkarma.com']
  message = """From: DBAudit
To: DBAs <dba@creditkarma.com>
Subject: DB Audit triggered alert
%s
\n
%s
\n
""" % (auditfile,audits)
  try:
    smtpObj = smtplib.SMTP('localhost')
    smtpObj.sendmail(sender, receivers, message)
  except SMTPException:
    print "Error: Unable to send email"

def main():

  timeframe = 3600
  global alert
  global auditfile
  global auditstring

  state = 0

  if len(sys.argv) == 2 and sys.argv[1].isdigit():
    timeframe = int(sys.argv[1])

  if not os.path.isfile('/etc/my.cnf'):
    print 'MySQL config file not found'
    sys.exit(2)
  else:
    f = open('/etc/my.cnf','rU')
    audit = re.findall(r'(?<!#)datadir\s*=\s*\/.+',f.read())
    f.close()

    if len(audit) == 0:
      print "Audit is not configured"
      sys.exit(2)

    for i in audit:
      alert = 0
      auditfile = re.sub(r'\s*datadir\s*=\s*','',i) + '/' + 'mysql-audit.json'
      print auditfile
      scan_audit(auditfile,timeframe)
      if alert == 1:
        send_email_alert(auditstring)
        print auditstring
        state = 1

    if state == 1:
      sys.exit(2)
    else:
      print "OK"
      sys.exit(0)

if __name__ == '__main__':
  main()
