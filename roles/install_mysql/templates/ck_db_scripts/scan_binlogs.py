#!/usr/bin/python -tt

from __future__ import print_function
import os,re,sys,datetime,socket,subprocess,threading,MySQLdb

sys.path.append("/usr/local/ops/bin/pydb")

from opsdb_host_info import send_email_alert,parameter,host_info,opsdb,dc_domain

def trackevents(dbcnx,dbport,binlogs):

  targetcursor = dbcnx.cursor()

  for binlog in binlogs:
#    print("Started processing %s, binlog %s at" % (threading.current_thread(),binlog), datetime.datetime.now())
    try:
      targetcursor.execute("show binlog events in '%s'" % binlog)
    except MySQLdb.Error as err:
      print("MySQL Error: %s" % str(err))
      exit(1)
    else:
      output = targetcursor.fetchall()

      for (binlogevent) in output:
        dropevent = re.search(r'(^|\s)drop\s',binlogevent[5].lower())
        truncevent = re.search(r'\struncate\s',binlogevent[5].lower())
        if dropevent or truncevent:

          beforebinlogevent = output[output.index(binlogevent) - 1]
          if re.search(r'SET @@SESSION.GTID_NEXT= ',str(beforebinlogevent[5])):
            gtid_next = re.sub(r'\'','',re.sub(r'SET @@SESSION.GTID_NEXT= ','',str(beforebinlogevent[5])))
          else:
            gtid_next = None

          opsdbcursor = opsdb().cursor()

          opsdbcursor.execute("select count(*) from track_binlog_events where binlog='%s' and start_pos=%s and port=%d" % (str(binlogevent[0]),str(binlogevent[1]),int(dbport)))

          newevent = int(opsdbcursor.fetchone()[0])

          if newevent == 0:
            track_binlog_events = ("insert into track_binlog_events (fqdn,port,binlog,start_pos,gtid_next,end_pos,statement,previous_statement) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)")
            binlog_data = (dbhost,int(dbport),str(binlogevent[0]),int(binlogevent[1]),str(gtid_next),int(binlogevent[4]),str(binlogevent[5]),str(beforebinlogevent[5]))
            opsdbcursor.execute(track_binlog_events,binlog_data)

            print("Alert: Drop/Truncate events found in %s:%s:%s:" % (dbhost,dbport,binlog), datetime.datetime.now())
            print(str(binlogevent[0]),'|',int(binlogevent[1]),'|',int(binlogevent[4]),'|',binlogevent[5],'|',beforebinlogevent[5])

          opsdbcursor.close()
          opsdb().close()

#    print("Finished processing %s, binlog %s at" % (threading.current_thread(),binlog), datetime.datetime.now())

  targetcursor.close()
  dbcnx.close()

def usage():
  print("Usage: %s hostname [--list|--scan] depth | --binlog binlogfilename" % sys.argv[0])
  sys.exit(1)

def main():

  global dbhost

  if len(sys.argv) < 4:
    usage()

  cmdstr = ' '.join(i for i in sys.argv)
  send_email_alert(parameter()[2],'%s executed' % os.getlogin(),cmdstr)

  if sys.argv[2] in ['--list','--scan']:
    try:
      int(sys.argv[3])
    except:
      usage()
    else:
      depth = int(sys.argv[3])
  elif sys.argv[2] == '--binlog':
    if not re.search('-mysql-bin.',str(sys.argv[3])):
      usage()
  else:
    usage()

  try:
    int(sys.argv[3])
  except:
    depth = 1
  else:
    depth = int(sys.argv[3])

  portlist = ""
  dbhost = sys.argv[1]

  if len(dbhost.split(':')) > 1:
    dbhost = dbhost.split(':')[0]
    portlist = ':' + sys.argv[1].split(':')[1]

  if len(dbhost.split('.')) == 1:
    dbhost = dbhost + '.' + dc_domain()
  elif len(dbhost.split('.')) == 2 and dbhost.split('.')[1] == 'sjc1':
    dbhost = dbhost + '.' + 'creditkarma.com'
  elif len(dbhost.split('.')) == 2 and dbhost.split('.')[1] == 'iad1':
      dbhost = dbhost.split('.')[0] + '.' + 'prod.iad1.ckint.io'

  if len(dbhost.split('.')) == 1:
    dbhost = dbhost + '.' + dc_domain()

  dbports = host_info(dbhost + portlist,'','N')
  scan_threads = []

  for iport in dbports:
    dbconnect = {
    'user': parameter()[0],
    'passwd': parameter()[1],
    'host': dbhost,
    'port': iport,
    'db': 'information_schema',
    'use_unicode': True
    }

    try:
      cnx = MySQLdb.connect(**dbconnect)
    except MySQLdb.Error as err:
      print("MySQL Error: %s" % str(err))
      sys.exit(1)
    else:
      cursor = cnx.cursor()
      cursor.execute("show binary logs")
      output = cursor.fetchall()
      binlogs = []
      for (output) in output:
        binlogs.append((output[0]))
      binlogs.reverse()
      cursor.close()

      if sys.argv[2] == '--list':
        print(dbhost+':'+str(iport),'- ', end="")
        for i in binlogs[0:depth]:
          print(i, end=" ")
        print()
        cnx.close()

      elif sys.argv[2] == '--scan':
        scan_thread = threading.Thread(target=trackevents, args=(cnx,iport,binlogs[0:depth],))
        scan_thread.daemon = True
        scan_thread.start()
        scan_threads.append(scan_thread)

      elif sys.argv[2] == '--binlog':
        trackevents(cnx,iport,[str(sys.argv[3])],)

  for i in scan_threads:
    i.join()

#  print('-------------------------------------------------------------')

if __name__ == '__main__':
  try:
    main()
  except KeyboardInterrupt:
    print('<Interrupted>')
    try:
      sys.exit(0)
    except SystemExit:
      os._exit(0)
