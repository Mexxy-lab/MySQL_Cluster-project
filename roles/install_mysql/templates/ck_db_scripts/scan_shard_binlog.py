#!/bin/env python

from __future__ import print_function
import os,re,sys,datetime,socket,logging,threading,Queue,MySQLdb,argparse

sys.path.append("/usr/local/ops/bin/pydb")

from opsdb_host_info import slack_hook,parameter,host_info,opsdb

def trackevents(dbcnx,binlog):

  targetcursor = dbcnx.cursor()

  logging.info("Processing binlog %s" % str(binlog))
  try:
    targetcursor.execute("show binlog events in '%s'" % binlog)
  except MySQLdb.Error as err:
    logging.error("MySQL Error: %s" % str(err))
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

        opsdbcursor.execute("select count(*) from track_binlog_events where binlog='%s' and start_pos=%s and port=%d" % (str(binlogevent[0]),str(binlogevent[1]),int(hostnport[1])))

        newevent = int(opsdbcursor.fetchone()[0])

        if newevent == 0:
          track_binlog_events = ("insert into track_binlog_events (fqdn,port,binlog,start_pos,gtid_next,end_pos,statement,previous_statement) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)")
          binlog_data = (str(hostnport[0]),int(hostnport[1]),str(binlogevent[0]),int(binlogevent[1]),str(gtid_next),int(binlogevent[4]),str(binlogevent[5]),str(beforebinlogevent[5]))
          opsdbcursor.execute(track_binlog_events,binlog_data)

          logging.info("Alert: Drop/Truncate events found in %s:%s:%s:" % (str(hostnport[0]),str(hostnport[1]),str(binlog)))
          logging.info("%s" % str(binlogevent[5]))
          print("Alert: Drop/Truncate events found in %s:%s:%s:%s" % (str(hostnport[0]),str(hostnport[1]),str(binlog),str(binlogevent[5])))

        opsdbcursor.close()
        opsdb().close()

    logging.info("Finished processing binlog %s" % str(binlog))

  targetcursor.close()
  dbcnx.close()
  scan_thread_queue.task_done()

# Processing input arguments
def process_args():

  parser = argparse.ArgumentParser(description='Scans Shard Binlogs for truncate/drop statements', epilog='Log destination - /var/log/shards')
  parser.add_argument("-d", "--datacenter", choices=['cke','ckw'], help="Example: ckw/cke", required=True)
  parser.add_argument("-g", "--shardgroup", choices=['budb','fodb','fldb','restore'], help="Example: budb/fldb/fodb", required=True)
  parser.add_argument("-n", "--shardinstance", help="Example: 24/1-8/121-128", required=False)
  parser.add_argument("-l", "--logfile", help="Example: fodb_binlog.log", required=False)
  parser.add_argument("-z", "--serialize", help="Fully Sequential Mode", action='store_true', required=False)
  parser.add_argument("--scan", metavar='n', type=int, nargs='?')

  args = parser.parse_args()
  return args

def main():

  global scan_thread_queue
  global hostnport

  email_status = 0

  cmdstr = ' '.join(i for i in sys.argv)

  args = process_args()

  if args.scan and args.scan > 0:
    depth = args.scan
  else:
    depth = 0

  if not args.logfile:
    logfile = 'scanbinlog.log'
  else:
    logfile = args.logfile

  if os.path.isfile('/var/log/shards/' + logfile):
    os.remove('/var/log/shards/' + logfile)

  logging.basicConfig(filename='/var/log/shards/%s' % logfile,format='%(levelname)s|%(asctime)s|%(message)s',level=logging.DEBUG)

# Range of shard instances
  if args.shardinstance:
    s_range = re.search('([\d]+)-([\d]+)', args.shardinstance)

    if s_range and int(s_range.group(1)) >= 1 and int(s_range.group(2)) <= 128 and int(s_range.group(1)) <= int(s_range.group(2)):
      shardline = range(int(s_range.group(1)),int(s_range.group(2))+1)

    elif args.shardinstance.isdigit() and int(args.shardinstance) > 0 and int(args.shardinstance) <= 128:
      shardline = [int(args.shardinstance)]

  else:
    shardline = range(1,129)

  opsdbcursor = opsdb().cursor()
  scan_thread_queue = Queue.Queue()

  for sn in [int(i) for i in shardline]:
    opsdbcursor.execute("select fqdn,port from host_info where groupName='%s' and role='shard' and shardNumber=%d and dataCenter='%s'" \
                        % (str(args.shardgroup), sn, str(args.datacenter.lower())))
    hostnport = opsdbcursor.fetchone()

    instanceconnect = {
    'user': parameter()[0],
    'passwd': parameter()[1],
    'host': hostnport[0],
    'port': int(hostnport[1]),
    'db': 'information_schema',
    'use_unicode': True
    }
    try:
      shardcnx = MySQLdb.connect(**instanceconnect)
    except MySQLdb.Error as err:
      logging.error("{0}:{1}".format(hostnport[0],hostnport[1]))

    else:
      cursor = shardcnx.cursor()
      cursor.execute("show binary logs")
      output = cursor.fetchall()
      binlogs = []
      for (output) in output:
        binlogs.append((output[0]))
      binlogs.reverse()
      cursor.close()

      scaninstance = threading.Thread(target=trackevents, args=(shardcnx,binlogs[depth],))
      scaninstance.daemon = 'True'
      scan_thread_queue.put(scaninstance)

  while not scan_thread_queue.empty():
    i = scan_thread_queue.get()
    logging.debug("Starting thread: %s" % i)
    i.start()

    if args.serialize:
      i.join()
      while i.is_alive() > 0:
        print("Waiting for thread to finish")
        time.sleep(2)

  scan_thread_queue.join()

  opsdbcursor.close()

  slack_hook(email_status)

  logging.info('-------------------------------------------------------------')

if __name__ == '__main__':
  try:
    main()
  except KeyboardInterrupt:
    print('<Interrupted>')
    try:
      sys.exit(0)
    except SystemExit:
      os._exit(0)
