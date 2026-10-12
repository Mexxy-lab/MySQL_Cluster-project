#!/usr/bin/python -tt

from __future__ import print_function
import os,re,sys,subprocess,time,datetime,socket,logging,threading,smtplib
import MySQLdb

sys.path.append("/usr/local/ops/bin/pydb")

from opsdb_host_info import send_email_alert,parameter,opsdb,host_info,slave_status

def shardn():
  qshard = []
  for i in sys.argv:
    try:
      int(i)
      if 1 <= int(i) <= 8:
      	qshard.append(int(i))
    except ValueError:
      None
  return qshard

def flush_tables(dbcnx,n_sec):

  def slave_tag():

    query = ("show master status")
    cursor.execute(query)
    for (output) in cursor:
      binlogfile = output[0]
      binlogpos = output[1]

    query = ("show variables like 'hostname'")
    cursor.execute(query)
    for (output) in cursor:
  	  targethost = output[1]

    query = ("show variables like 'port'")
    cursor.execute(query)
    for (output) in cursor:
  	  targetport = output[1]

    query = ("show slave status")
    cursor.execute(query)
    for (output) in cursor:
        masterhost = output[1]
        masterport = output[3]
        masterlogread = output[5]
        masterlogposread = output[6]
        relaylog = output[7]
        relaylogpos = output[8]
        relaymasterlog = output[9]
        execmasterlogpos = output[21]
        slaveiothread = output[10]
        slavesqlthread = output[11]
        retrieved_gtid_set = output[51]
        executed_gtid_set = output[52]

    query = ("select h.role,h.dataCenter from host_info h where h.ipAddress='%s' and h.port=%d" % (masterhost,int(masterport)));
    opsdbcursor.execute(query)
    for (output) in opsdbcursor:
      mrole = output[0]
      mdc = output[1]

    try:
      mdc
    except:
      query = ("select h.role,h.dataCenter from host_info h where h.fqdn='%s' and h.port=%d" % (masterhost,int(masterport)));
      opsdbcursor.execute(query)
      for (output) in opsdbcursor:
        mrole = output[0]
        mdc = output[1]

    add_to_catalog = ("INSERT INTO snapshot_catalog "
        "(backupHost,backupPort,masterHost,masterPort,dataCenter,role,binlog_file,binlog_file_pos,master_log_read,master_log_pos_read,"
        "relay_log,relay_log_pos,relay_master_log,exec_master_log_pos,slave_io_running,slave_sql_running,retrieved_gtid_set,executed_gtid_set) "
        "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)")

    snapshot_data = (targethost,targetport,masterhost,masterport,mdc,mrole,binlogfile,binlogpos,masterlogread,masterlogposread,\
        relaylog,relaylogpos,relaymasterlog,execmasterlogpos,slaveiothread,slavesqlthread,retrieved_gtid_set,executed_gtid_set)

    opsdbcursor.execute(add_to_catalog,snapshot_data)

    get_snapid = ("select snapid from snapshot_catalog where backupHost=%s and backupPort=%s and status=1 order by autoTs desc limit 1")
    get_snapid_for = (targethost,targetport)

    opsdbcursor.execute(get_snapid,get_snapid_for)
    snapid = opsdbcursor.fetchone()[0]

    return snapid

  dbcnx.autocommit(True)
  cursor = dbcnx.cursor()

  if slave_status(dbcnx,11) == 'Yes':
    try:
      cursor.execute('stop slave sql_thread')
    except MySQLdb.Error as err:
      print("MySQL Error: %s" % str(err))
      pass
    else:
      time.sleep(1)
      cursor.execute('set global sync_relay_log=1')
      cursor.execute('set global sync_relay_log_info=1')
      cursor.execute('set global sync_master_info=1')
      cursor.execute('set global sync_binlog=1')
      cursor.execute('flush tables with read lock')
      cursor.execute('flush logs')
      time.sleep(1)
      snapid = slave_tag()
      time.sleep(n_sec)
      cursor.execute('unlock tables')
      cursor.execute('set global sync_relay_log=0')
      cursor.execute('set global sync_relay_log_info=0')
      cursor.execute('set global sync_master_info=0')
      cursor.execute('set global sync_binlog=0')
      cursor.execute('start slave sql_thread')
  else:
    print("Warning: Slave SQL Thread is Down or Missing...")
    cursor.execute('flush tables with read lock')
    time.sleep(1)
    cursor.execute('flush logs')
    snapid = slave_tag()
    time.sleep(n_sec)
    cursor.execute('unlock tables')

  print("Releasing %s, snapshot id %s at" % (threading.current_thread(),snapid), datetime.datetime.now())

  snap_status = ("update snapshot_catalog set status=0 where snapid=%d" % int(snapid))
  opsdbcursor.execute(snap_status)

  cursor.close()
  dbcnx.close()

def snapshot(vmax,script):
  try:
    psnap = subprocess.Popen(['ssh', '-q', '%s' % vmax, '/home/snapvx/%s' % script], stdout=subprocess.PIPE)
    out, err = psnap.communicate()
    print(out)
  except:
    print("Unexpected Error creating snapshot")
    send_email_alert('Unexpected Error creating snapshot')
  else:
    psnap.wait()
    time.sleep(1)
    return psnap

def main():

  global opsdbcnx,opsdbcursor

  logging.basicConfig(filename='/tmp/test.log',format='(asctime)s: %(message)s',level=logging.INFO)

  dc_domain = re.sub('^[\w]+.','',socket.gethostname())

  opsdbcnx = opsdb()
  opsdbcursor = opsdbcnx.cursor()

  if dc_domain == 'prod.iad1.ckint.io':
    vmax_admin = '10.99.200.64'
  elif dc_domain == 'sjc1.creditkarma.com':
    vmax_admin = '10.101.200.48'
  else:
    print("Unknown Domain - %s" % dc_domain)
    sys.exit(1)

  if re.search(r'--exclude-mono',sys.argv[-1]):
    excludetype = 'mono'
  elif re.search(r'--exclude-shard',sys.argv[-1]):
    excludetype = 'shard'
  else:
    excludetype = ''

  if int(datetime.datetime.now().isocalendar()[2]) == 7 \
  	      and int(datetime.datetime.now().hour) == 0 \
          and int(datetime.datetime.now().minute < 15):
    ss_type = 'weekly'
  elif int(datetime.datetime.now().hour) % 4 == 0 and \
          int(datetime.datetime.now().minute < 15):
    ss_type = 'daily'
  else:
    ss_type = 'hourly'

  flush_threads = []
  hostline = [1,2,3,4,5,6,7,8]
  print("--------------------------------------")
  start_time = time.time()

  for i in hostline:

    dbhost = 'budb00' + str(i) + '.' + dc_domain
    dbports = host_info(dbhost,excludetype,'N')

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
        print(dbhost, iport, ": ", end="")
        print("MySQL Error: %s" % str(err))
        continue
      else:
        if i in shardn():
          print("Quiescing %s, port %d: " % (dbhost, iport), end="")
          print(datetime.datetime.now())
          flush_thread = threading.Thread(target=flush_tables, args=(cnx,80,))
          flush_thread.daemon = True
          flush_thread.start()
          flush_threads.append(flush_thread)
        else:
          print("Skipping quiescing %s, port %d: " % (dbhost, iport), end="")
          print(datetime.datetime.now())
          cnx.close()
        time.sleep(0.5)

  if len(flush_threads) == (threading.active_count() - 1) or len(flush_threads) == 0:
    ss_script = ss_type + '_shard_snaps.sh'
    time.sleep(1)
    print("Active Quiescing Threads: %d - " % (threading.active_count() - 1), end="")
    end_time = time.time()
    print("%.3f seconds" % (end_time - start_time))
    print("%s start time: " % ss_script, end="")
    print(datetime.datetime.now())
    snapshot(vmax_admin, ss_script)
    print("%s end time: " % ss_script, end="")
    print(datetime.datetime.now())
    print("--------------------------------------")
  else:
    print("Expected Number of Threads: %d - " % len(flush_threads), end="")
    print("Actual Number of threads: %d - " % (threading.active_count() - 1))
    print("Some DB quiescing threads are missing. Snapshot is canceled")
    send_email_alert('DB quiescing step failed. Snapshot is canceled')

    # Restarting SQl Threads that were brought down
    for i in hostline:
      dbhost = 'budb00' + str(i) + '.' + dc_domain
      dbports = host_info(dbhost,excludetype,'N')
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
          print(dbhost, iport, ": ", end="")
          print("MySQL Error: %s" % str(err))
        else:
          print("Restarting Replication on %s, port %d: " % (dbhost, iport), datetime.datetime.now())
          if slave_status(cnx,10) == 'Yes' and slave_status(cnx,11) == 'No':
            cnx.cursor().execute("start slave sql_thread")

  for i in flush_threads:
    i.join()

  opsdbcursor.close()
  opsdbcnx.close()

if __name__ == '__main__':
  main()
