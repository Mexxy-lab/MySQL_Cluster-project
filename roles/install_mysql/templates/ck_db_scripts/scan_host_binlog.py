#!/bin/env python

from __future__ import print_function
import os,re,sys,socket,subprocess,threading,MySQLdb,argparse,logging

sys.path.append("/usr/local/ops/bin/pydb")

from opsdb_host_info import parameter,host_info,opsdb,slack_hook

def trackevents(dbcnx,hostnport,binlogs):

  targetcursor = dbcnx.cursor()

  for binlog in binlogs:
    logging.debug("Processing binlog %s" % str(binlog))
    print("Processing %s" % str(binlog))
    try:
      targetcursor.execute("show binlog events in '%s'" % binlog)
    except MySQLdb.Error as err:
      mysql_fail(err,hostnport)
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

          opsdbcursor.execute("select count(*) from track_binlog_events where binlog='%s' and start_pos=%s and port=%d" % (str(binlogevent[0]),str(binlogevent[1]),int(hostnport[1])))

          newevent = int(opsdbcursor.fetchone()[0])

          if newevent == 0:
            track_binlog_events = ("insert into track_binlog_events (fqdn,port,binlog,start_pos,gtid_next,end_pos,statement,previous_statement) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)")
            binlog_data = (hostnport[0],int(hostnport[1]),str(binlogevent[0]),int(binlogevent[1]),str(gtid_next),int(binlogevent[4]),str(binlogevent[5]),str(beforebinlogevent[5]))
            opsdbcursor.execute(track_binlog_events,binlog_data)

            logging.info("%s:%s:%s:%s" % (hostnport[0],hostnport[1],binlog,binlogevent[5]))

          opsdbcursor.close()
          opsdb().close()

    logging.debug("Finished processing %s, binlog %s at" % (threading.current_thread(),binlog))

  targetcursor.close()
  dbcnx.close()

# Processing input arguments
def process_args():

  parser = argparse.ArgumentParser(description='Scans Master Binlogs for truncate/drop statements', epilog='Log destination - /var/log')
  group = parser.add_mutually_exclusive_group(required=True)
  parser.add_argument("-d", "--datacenter", choices=['cke','ckw'], help="Example: ckw/cke", required=True)
  parser.add_argument("-t", "--targethost", help="Target master host", required=True)
  parser.add_argument("-p", "--targetport", help="Target master port", required=False)
  parser.add_argument("-l", "--logfile", required=False)
  group.add_argument("--scan", metavar='n', type=int, const=1, nargs='?')
  group.add_argument("--list", metavar='n', type=int, const=1, nargs='?')
  parser.add_argument("-o", "--offset", help="Optional offset parameter to be used with --scan", metavar='n', type=int, const=0, nargs='?')

  args = parser.parse_args()
  return args

def main():

  email_status = 0

  args = process_args()

  if args.offset is not None and args.scan is None:
    print('OFFSET can only be used along with SCAN.')
    sys.exit(1)
  elif args.offset is not None:
    offset = args.offset
  else:
    offset = 0

  if args.list is not None and int(args.list) > 0:
    depth = int(args.list)

  if args.scan is not None and int(args.scan) > 0:
    depth = int(args.scan)

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

  if args.logfile and len(args.logfile.split('/')) > 1:
    if not os.path.exists(os.path.dirname(args.logfile)):
      print("Invalid path for logfile")
      sys.exit(1)
    else:
      logfile = args.logfile
  else:
    logfile = '/var/log/scanbinlog.log'

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

  slack_hook(email_status)

  scan_threads = []

  logging.basicConfig(filename=logfile,format='%(levelname)s|%(asctime)s|%(message)s',level=logging.INFO)

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
    except MySQLdb.Error as err:
      mysql_fail(err,(fqdn,iport))
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

      if args.list:
        print(fqdn+':'+str(iport),'- ', end="")
        for i in binlogs[0:depth]:
          print(i, end=" ")
        print()
        cnx.close()

      if args.scan:
        scan_thread = threading.Thread(target=trackevents, args=(cnx,(fqdn,iport),binlogs[offset:offset+depth],))
        scan_thread.daemon = True
        scan_thread.start()
        scan_threads.append(scan_thread)

  for i in scan_threads:
    i.join()

  print('----------------------------------')
  logging.info('----------------------------------------------------')
  print("Execution Log File: %s" % logfile)

if __name__ == '__main__':
  try:
    main()
  except KeyboardInterrupt:
    print('<Interrupted>')
    try:
      sys.exit(0)
    except SystemExit:
      os._exit(0)
