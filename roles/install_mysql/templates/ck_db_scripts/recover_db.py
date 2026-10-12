#!/usr/bin/python -tt

from __future__ import print_function
import os,re,sys,time,threading,subprocess,socket,datetime,MySQLdb,logging

sys.path.append("/usr/local/ops/bin/pydb")

from opsdb_host_info import send_email_alert,parameter,host_info,opsdb,slave_status

def recover_instance(dbcnx,dbport):

  if slave_status(dbcnx,10) == 'Yes' or slave_status(dbcnx,11) == 'Yes':
    print("Recovery is no allowed while replication is up...")
    sys.exit(0)
  else:
      masterhost = slave_status(dbcnx,1)

      opsdbcnx = opsdb()
      opsdbcursor = opsdb().cursor()

# No GTID
      query = ("select count(*) from track_binlog_events where fqdn='%s' and port=%d and status>0 and gtid_next='None'" % (masterhost,dbport))
      opsdbcursor.execute(query)

      if int(opsdbcursor.fetchone()[0]) > 0:
        query = ("select eventid from track_binlog_events where fqdn='%s' and port=%d and status>0 and gtid_next='None' order by binlog,start_pos" % (masterhost,dbport))
        opsdbcursor.execute(query)

        for i in opsdbcursor.fetchall():
          query = ("select binlog,start_pos from track_binlog_events where eventid=%d" % int(i[0]))
          opsdbcursor.execute(query)
          binloginfo = opsdbcursor.fetchone()

          print(binloginfo[0], int(binloginfo[1]))

          dbcnx.cursor().execute("start slave until master_log_file='%s', master_log_pos=%d" % (binloginfo[0],int(binloginfo[1])))

          while slave_status(dbcnx,11) == 'Yes':
            time.sleep(60)
            print("SQL Thread is Active. Waiting...")
            dbcnx.cursor().execute("select 'Keep me awake'")
            opsdbcursor.execute("select 'Keep me awake'")

          dbcnx.cursor().execute("stop slave")

          dbcnx.cursor().execute("set global sql_slave_skip_counter=1")

          opsdbcursor.execute("update track_binlog_events set status=0 where eventid=%d" % int(i[0]))

# GTID
      query = ("select count(*) from track_binlog_events where fqdn='%s' and port=%d and status>0 and gtid_next<>'None'" % (masterhost,dbport))
      opsdbcursor.execute(query)

      if int(opsdbcursor.fetchone()[0]) > 0:
        query = ("select eventid from track_binlog_events where fqdn='%s' and port=%d and status>0 and gtid_next<>'None' order by binlog,start_pos" % (masterhost,dbport))
        opsdbcursor.execute(query)

        for i in opsdbcursor.fetchall():
          query = ("select gtid_next from track_binlog_events where eventid=%d" % int(i[0]))
          opsdbcursor.execute(query)
          gtidinfo = opsdbcursor.fetchone()

          print(gtidinfo[0])

          dbcnx.cursor().execute("start slave until sql_before_gtids = '%s'" % gtidinfo[0])

          while slave_status(dbcnx,11) == 'Yes':
            time.sleep(60)
            print("SQL Thread is Active. Waiting...")
            dbcnx.cursor().execute("select 'Keep me awake'")
            opsdbcursor.execute("select 'Keep me awake'")

          dbcnx.cursor().execute("stop slave")

          dbcnx.cursor().execute("set gtid_next='%s'" %  gtidinfo)

          dbcnx.cursor().execute("begin")

          dbcnx.cursor().execute("commit")

          dbcnx.cursor().execute("set gtid_next='AUTOMATIC'")

          opsdbcursor.execute("update track_binlog_events set status=0 where eventid=%d" % int(i[0]))

      print("Data Recovery is complete. Restarting replication")

      dbcnx.cursor().execute("start slave")

      opsdbcursor.close()
      opsdbcnx.close()

  dbcnx.close()

def main():

  dbhost = sys.argv[1]

  hostandport = re.search('(^[\w.]+):([\d,-]+$)', dbhost)

  if hostandport:
    dbhost = hostandport.group(1)
    if len(dbhost.split('.')) == 1:
      dbhost = dbhost + '.' + re.sub('^[\w]+.','',socket.gethostname()) + ':' + hostandport.group(2)
    else:
      dbhost = dbhost + ':' + hostandport.group(2)

  if len(dbhost.split('.')) == 1:
    dbhost = dbhost + '.' + re.sub('^[\w]+.','',socket.gethostname())

  dbports = host_info(dbhost)
  scan_threads = []

  dbhost = dbhost.split(':')[0]

  recover_threads = []

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
    except MySQLdb.Error as error:
      print("MySQL Error: %s" % str (error))
      sys.exit(1)
    else:
      cnx.autocommit(True)

      recover_thread = threading.Thread(target=recover_instance, args=(cnx,iport,))
      recover_thread.daemon = True
      recover_thread.start()
      recover_threads.append(recover_thread)

  for i in recover_threads:
    i.join()

if __name__ == '__main__':
  main()
