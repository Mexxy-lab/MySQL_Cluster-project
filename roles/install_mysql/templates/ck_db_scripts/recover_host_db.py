#!/usr/bin/python -tt

from __future__ import print_function
import os,re,sys,time,threading,subprocess,socket,MySQLdb,argparse,logging

sys.path.append("/usr/local/ops/bin/pydb")

from opsdb_host_info import send_email_alert,parameter,host_info,opsdb,slave_status,slack_hook

def recover_instance(dbcnx,hostnport):

  if slave_status(dbcnx,10) == 'Yes' or slave_status(dbcnx,11) == 'Yes':
    print("Recovery is no allowed while replication is up. Stop slave threads and try again...")
    sys.exit(0)
  else:
      masterhost = slave_status(dbcnx,1)
      masterport = int(slave_status(dbcnx,3))

      opsdbcnx = opsdb()
      opsdbcursor = opsdb().cursor()

# No GTID
      query = ("select count(*) from track_binlog_events where fqdn='%s' and port=%d and status>0 and gtid_next='None'" % (masterhost,masterport))
      opsdbcursor.execute(query)

      if int(opsdbcursor.fetchone()[0]) > 0:
        print("Recovering without GTID")
        query = ("select eventid from track_binlog_events where fqdn='%s' and port=%d and status>0 and gtid_next='None' order by binlog,start_pos" % (masterhost,masterport))
        opsdbcursor.execute(query)

        for i in opsdbcursor.fetchall():
          query = ("select binlog,start_pos from track_binlog_events where eventid=%d" % int(i[0]))
          opsdbcursor.execute(query)
          binloginfo = opsdbcursor.fetchone()

          logging.info("Starting Replication Until Binlog Position %s:%s:%s:%s" % (hostnport[0],hostnport[1],binloginfo[0], binloginfo[1]))

          dbcnx.cursor().execute("start slave until master_log_file='%s', master_log_pos=%d" % (binloginfo[0],int(binloginfo[1])))

          while slave_status(dbcnx,11) == 'Yes':
            time.sleep(10)
            print("SQL Thread is Active. Waiting...")
            dbcnx.cursor().execute("select 'Keep me awake'")
            opsdbcursor.execute("select 'Keep me awake'")

          logging.info("Stopping Replication and Skipping Transaction in %s:%s" % (hostnport[0],hostnport[1]))

          dbcnx.cursor().execute("stop slave")

          dbcnx.cursor().execute("set global sql_slave_skip_counter=1")

          opsdbcursor.execute("update track_binlog_events set status=0 where eventid=%d" % int(i[0]))

# GTID
      query = ("select count(*) from track_binlog_events where fqdn='%s' and port=%d and status>0 and gtid_next<>'None'" % (masterhost,masterport))
      opsdbcursor.execute(query)

      if int(opsdbcursor.fetchone()[0]) > 0:
        print("Recovering with GTID")
        query = ("select eventid from track_binlog_events where fqdn='%s' and port=%d and status>0 and gtid_next<>'None' order by binlog,start_pos" % (masterhost,masterport))
        opsdbcursor.execute(query)

        for i in opsdbcursor.fetchall():
          query = ("select gtid_next from track_binlog_events where eventid=%d" % int(i[0]))
          opsdbcursor.execute(query)
          gtidinfo = opsdbcursor.fetchone()

          logging.info("Starting Replication Until GTID %s:%s:%s" % (hostnport[0],hostnport[1],gtidinfo[0]))

          dbcnx.cursor().execute("start slave until sql_before_gtids = '%s'" % gtidinfo[0])

          while slave_status(dbcnx,11) == 'Yes':
            time.sleep(10)
            print("SQL Thread is Active. Waiting...")
            dbcnx.cursor().execute("select 'Keep me awake'")
            opsdbcursor.execute("select 'Keep me awake'")

          logging.info("Stopping Replication and Injecting Empty Transaction in %s:%s" % (hostnport[0],hostnport[1]))

          dbcnx.cursor().execute("stop slave")

          dbcnx.cursor().execute("set gtid_next='%s'" %  gtidinfo)

          dbcnx.cursor().execute("begin")

          dbcnx.cursor().execute("commit")

          dbcnx.cursor().execute("set gtid_next='AUTOMATIC'")

          opsdbcursor.execute("update track_binlog_events set status=0 where eventid=%d" % int(i[0]))

      logging.info("%s:%s Recovery is complete. Restarting replication." % (hostnport[0],hostnport[1]))
      print("%s:%s Recovery is complete. Restarting replication." % (hostnport[0],hostnport[1]))

      dbcnx.cursor().execute("start slave")

      time.sleep(10)

      if slave_status(dbcnx,10) != 'Yes' or slave_status(dbcnx,11) != 'Yes':
        logging.error("%s:%s Replication is broken. Check the slave status.")

      opsdbcursor.close()
      opsdbcnx.close()

  dbcnx.close()

# Processing input arguments
def process_args():

  parser = argparse.ArgumentParser(description='Performs database recovery skipping statements registred by scan_host_binlog.py', epilog='Log destination - /var/log')
  parser.add_argument("-d", "--datacenter", choices=['cke','ckw'], help="Example: ckw/cke", required=True)
  parser.add_argument("-t", "--targethost", help="Target master host", required=True)
  parser.add_argument("-p", "--targetport", help="Target master port", required=False)
  parser.add_argument("-l", "--logfile", required=False)

  args = parser.parse_args()
  return args

def main():

  email_status = 0

  args = process_args()

  opsdbcnx = opsdb()
  opsdbcursor = opsdbcnx.cursor()

  opsdbcursor.execute("select distinct fqdn from host_info where hostName like '%s%%' and dataCenter = '%s'" % (args.targethost,args.datacenter))
  fqdn = opsdbcursor.fetchall()

  opsdbcursor.close()
  opsdbcnx.close()

  if len(fqdn) == 0:
    print("No matching hosts found")
    sys.exit(1)
  elif len(fqdn) > 1:
    print("Too many hosts matching given name")
    sys.exit(1)
  else:
    fqdn = str(fqdn[0][0])

  if args.targetport:

    dbports = host_info(fqdn,'','N')
    p_range = re.search('([\d]+)-([\d]+)', args.targetport)

    if p_range and int(p_range.group(1)) <= int(p_range.group(2)):
      portline = range(int(p_range.group(1)),int(p_range.group(2))+1)

    elif args.targetport.isdigit():
      portline = [int(args.targetport)]

    elif re.search(',', args.targetport):
      portline = args.targetport.split(',')
      portline = [portn for portn in portline if portn.isdigit()]

    else:
      print("Invalid Port(s): %s" % args.targetport)
      sys.exit(1)

    dbports = [portn for portn in dbports if portn in portline]

  else:
    dbports = host_info(fqdn,'','Y')

  if args.logfile and len(args.logfile.split('/')) > 1:
    if not os.path.exists(os.path.dirname(args.logfile)):
      print("Invalid path for logfile")
      sys.exit(1)
    else:
      logfile = args.logfile
  else:
    logfile = '/var/log/recoverdb.log'

  logging.basicConfig(filename=logfile,format='%(levelname)s|%(asctime)s|%(message)s',level=logging.INFO)

  slack_hook(email_status)

  recover_threads = []

  for iport in dbports:
    dbconnect = {
    'user': parameter()[0],
    'passwd': parameter()[1],
    'host': fqdn,
    'port': iport,
    'db': 'information_schema',
    'use_unicode': True
    }

    try:
      cnx = MySQLdb.connect(**dbconnect)
    except MySQLdb.Error as error:
      mysql_fail(error,(fqdn,iport))
      sys.exit(1)
    else:
      cnx.autocommit(True)

      print(fqdn,iport)
      recover_thread = threading.Thread(target=recover_instance, args=(cnx,(fqdn,iport),))
      recover_thread.daemon = True
      recover_thread.start()
      recover_threads.append(recover_thread)

  for i in recover_threads:
    i.join()

if __name__ == '__main__':
  main()
