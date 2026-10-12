#!/bin/env python
# =============================================================================
#
# WARNING! THIS FILE IS MANAGED BY SALT!
#
# Any edits to this file will be lost next time salt runs.
# If you need to modify this file for any reason please contact ops team.
# operations@creditkarma.com
# =============================================================================

###############################################################################
#
# Owner:   CK DBA
# Purpose: Multi-purpose script for managing MySQL shard databases.
# Usage:   Run with --help.
#
###############################################################################

from __future__ import print_function
import os,re,sys,subprocess,threading,MySQLdb,logging,Queue,argparse,codecs

reload(sys)
sys.setdefaultencoding('utf-8')

# Custom python modules for MySQL and system calls

sys.path.append("/usr/local/ops/bin/pydb")

from opsdb_host_info import parameter,opsdb,host_info,show_db,check_for_cpids,mysql_fail,slack_hook,max_instance_number,shard_groups

def exec_script(dbcnx,queue,s_filter):

# Threads to execute SQL script or statement

  global hostnport

  dbcnx.autocommit(False)
  cursor = dbcnx.cursor()

  for stmt in s_filter:
    try:
      cursor.execute(stmt)
    except MySQLdb.Error as err:
      logging.error("Shard %s%s:%s|Fail" % (str(hostnport[0]),str(hostnport[1]),stmt))
      mysql_fail(err,hostnport)
      dbcnx.rollback()
    else:
      logging.debug("Shard %s%s:%s|OK" % (str(hostnport[0]),str(hostnport[1]),stmt))
      output = cursor.fetchall()
      dbcnx.commit()

      outstring = []

      for (output) in cursor:
        for i in output:
          outrow = ' '.join(str(n).replace('None','Null') for n in output)

        outstring.append(outrow)

        logging.info(str(hostnport[0]) + ':' + str(hostnport[1]) + '|' + '|'.join(outstring))

  cursor.close()
  dbcnx.close()
  queue.task_done()

def scanbinlog(dbcnx,queue,binlogs):

  cursor = dbcnx.cursor()

  for binlog in binlogs:
    logging.info("Processing binlog %s" % str(binlog))
    try:
      cursor.execute("show binlog events in '%s'" % binlog)
    except MySQLdb.Error as err:
      logging.error("MySQL Error: %s" % str(err))
    else:
      output = cursor.fetchall()

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

            logging.info("Alert: Drop/Truncate events found in %s:%s:%s:%s" % (str(hostnport[0]),str(hostnport[1]),str(binlog),str(binlogevent[5])))

          opsdbcursor.close()
          opsdb().close()

    logging.info("Finished processing binlog %s" % str(binlog))

  cursor.close()
  dbcnx.close()
  queue.task_done()

def globalvar(dbcnx,queue,vname='all'):

  cursor = dbcnx.cursor()

  instance_id = '%s_%s' % (hostnport[0].split('.')[0],hostnport[1])

  if vname == 'all':
    query = ("select concat('%s:',variable_name,'=', variable_value) as %s from global_variables \
            order by 1" % (instance_id,instance_id))
  else:
    query = ("select concat('%s:',variable_name,'=', variable_value) as %s from global_variables\
        where variable_name like '%s%%' order by 1" % (instance_id,instance_id,vname))

  cursor.execute(query)

  for (output) in cursor:
    logging.info("%s" % output)

  cursor.close()
  dbcnx.close()
  queue.task_done()

def processlist(dbcnx,queue,user='all',runtime=0,kill='N'):

  global email_status

  cursor = dbcnx.cursor()

  if user == 'all':
    query = ("select id,user,host,info,command,time from processlist where user != 'system user' and time>%d" % int(runtime))
  else:
    query = ("select id,user,host,info,command,time from processlist where user='%s' and time>%d" % (user,int(runtime)))

  proclist = []

  try:
    cursor.execute(query)
  except MySQLdb.Error as err:
    mysql_fail(err,hostnport)
  else:
    output = cursor.fetchall()

    for (output) in cursor:
      outlist = ['%s:%s -' % (hostnport[0],hostnport[1])]
      proclist.append(int(output[0]))

      for i in output:
        outlist.append(str(i))

      outstring = ' '.join(i for i in outlist)
      logging.info(outstring)
      print(outstring)

    if kill and kill == 'Y':
      for i in proclist:
        cursor.execute('kill %d' % int(i))

  cursor.close()
  dbcnx.close()
  queue.task_done()

# Processing input arguments
def process_args():

  parser = argparse.ArgumentParser(description='Script for administering shard instances', epilog='Log destination - /var/log/shards')
  group = parser.add_mutually_exclusive_group(required=True)
  parser.add_argument("-i", "--interactive", action='store_true', required=False)
  parser.add_argument("-d", "--datacenter", choices=['cke','ckw'], help="Example: ckw/cke", required=True)
  parser.add_argument("-g", "--shardgroup", help="Example: budb/fldb/fodb", required=True)
  parser.add_argument("-n", "--shardinstance", help="Example: N1,N2,.../N1-N2, 1<=NN<=128")
  parser.add_argument("-l", "--logfile", help="Example: shards.log", required=False)
  group.add_argument("-p", "--proclist", metavar=('user','runtime'), help="Example: all/etlagent 0", type=str, nargs='+')
  group.add_argument("-v", "--globalvar", help="Example: binlog_format/port/all(for all variables)", type=str, nargs=1)
  group.add_argument("-e", "--execute", metavar="Script/Statement", type=str, nargs=1)
  group.add_argument("-s", "--scanbinlog", metavar='N', help="Binlog Scan Depth. Example: 3", type=int, nargs=1)
  args = parser.parse_args()

  return args

def main():

  global hostnport

  logfile = None
  email_status = 1

  if len(check_for_cpids(sys.argv[0])) > 0:
    print("{0} is already in action. Check for active instances: 'pgrep -lf {0}'".format(sys.argv[0].split('/')[-1]))
    sys.exit(0)

  args = process_args()

  if args.shardgroup not in shard_groups():
    print("%s - Unknown Shard Group" % args.shardgroup)
    sys.exit(1)

# Range of shard instances

  max_instance = max_instance_number(args.datacenter,args.shardgroup)

  if args.shardinstance is not None:
    s_range = re.search('([\d]+)-([\d]+)', args.shardinstance)

    if s_range and int(s_range.group(1)) >= 1 and int(s_range.group(2)) <= max_instance and int(s_range.group(1)) <= int(s_range.group(2)):
      shardline = range(int(s_range.group(1)),int(s_range.group(2))+1)

    elif args.shardinstance.isdigit() and 1<=int(args.shardinstance)<= max_instance:
      shardline = [int(args.shardinstance)]

    elif re.search(',', args.shardinstance):
      shardline = args.shardinstance.split(',')
      shardline = [shardn for shardn in shardline if shardn.isdigit() and 1<=int(shardn)<=max_instance]

    else:
      print("Invalid instance numbers: %s" % args.shardinstance)
      sys.exit(1)
  else:
    shardline = range(1,max_instance_number(args.datacenter,args.shardgroup)+1)

# Log file

  if args.proclist:
    if not args.logfile:
      logfile = 'proclist.log'
    else:
      logfile = args.logfile

  if args.globalvar:
    if not args.logfile:
      logfile = 'globalvar.log'
    else:
      logfile = args.logfile

  if args.scanbinlog:
    if not args.logfile:
      logfile = 'scanbinlog.log'
    else:
      logfile = args.logfile

  if args.execute:
    if not args.logfile:
      logfile = 'exec.log'
    else:
      logfile = args.logfile

  if os.path.isfile('/var/log/shards/' + logfile) and args.interactive:
    gonogo = 'n'
    while gonogo.lower() not in ('q','o'):
      print("/var/log/shards/%s already exists. Overwrite(o), Quit(q):" % logfile,end=' ')
      gonogo = raw_input()
      if gonogo.lower() == 'q':
        sys.exit(0)
      elif gonogo.lower() == 'o':
        os.remove('/var/log/shards/' + logfile)

  elif os.path.isfile('/var/log/shards/' + logfile) and not args.interactive:
    os.remove('/var/log/shards/' + logfile)

  logging.basicConfig(filename='/var/log/shards/%s' % logfile,format='%(levelname)s|%(asctime)s|%(message)s',level=logging.INFO)

  slack_hook(email_status)

  opsdbcursor = opsdb().cursor()

  for sn in [int(i) for i in shardline]:
    opsdbcursor.execute("select fqdn,port from host_info where groupName='%s' and role like '%%shard%%' and shardNumber=%d and dataCenter='%s'" \
                      % (str(args.shardgroup), sn, str(args.datacenter.lower())))
    hostnport = opsdbcursor.fetchone()

    if hostnport is None:
      print("Instance %d is invalid for %s" % (int(sn),str(args.shardgroup)))
      sys.exit(1)

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
      # Global Variables
      if args.globalvar:

        var_thread_queue = Queue.Queue()

        varinstance = threading.Thread(target=globalvar, args=(shardcnx,var_thread_queue,args.globalvar[0],))
        var_thread_queue.put(varinstance)

        while not var_thread_queue.empty():
          i = var_thread_queue.get()
          logging.debug("Starting thread: %s" % i)
          i.start()

        var_thread_queue.join()

      # Scanning Binary Logs to register drop/truncate events
      if args.scanbinlog:
        cursor = shardcnx.cursor()
        cursor.execute("show binary logs")
        output = cursor.fetchall()

        binlogs = []

        for (output) in output:
          binlogs.append((output[0]))
        binlogs.reverse()

        cursor.close()

        scan_thread_queue = Queue.Queue()

        scaninstance = threading.Thread(target=scanbinlog, args=(shardcnx,scan_thread_queue,binlogs[0:int(args.scanbinlog[0])],))
        scan_thread_queue.put(scaninstance)

        while not scan_thread_queue.empty():
          i = scan_thread_queue.get()
          logging.debug("Starting thread: %s" % i)
          i.start()

        scan_thread_queue.join()

      # Process List
      if args.proclist:

        if len(args.proclist) > 1 and not args.proclist[1].isdigit():
          print("Invalid value for runtime - %s. %s --help" % (args.proclist[1],sys.argv[0]))
          sys.exit(1)
        elif len(args.proclist) > 1 and args.proclist[1].isdigit():
          runtime = args.proclist[1]
        else:
          runtime = 0

        if len(args.proclist) > 2 and str(args.proclist[2]) == 'kill':
          zap = 'Y'
        else:
          zap = 'N'

        process_thread_queue = Queue.Queue()

        procinstance = threading.Thread(target=processlist, args=(shardcnx,process_thread_queue,args.proclist[0],runtime,zap,))
        process_thread_queue.put(procinstance)

        while not process_thread_queue.empty():
          i = process_thread_queue.get()
          logging.debug("Starting thread: %s" % i)
          i.start()

        process_thread_queue.join()

    # Execute SQL statements
    if args.execute:

      s_filter = []

      if os.path.isfile(args.execute[0]) and os.access(args.execute[0], os.R_OK):
        script = open(args.execute[0],'rU')
        statements = re.findall(r'.+?;', script.read().replace('\n', ''))

        for stmt in (x for x in statements if not x.startswith('#') and not x.startswith('--')):
          s_filter.append(stmt)

      else:
        if not args.execute[0].startswith('#') and not args.execute[0].startswith('--'):
          s_filter.append(args.execute[0] + ';')

      exec_thread_queue = Queue.Queue()

      execinstance = threading.Thread(target=exec_script, args=(shardcnx,exec_thread_queue,s_filter,))
      exec_thread_queue.put(execinstance)

      while not exec_thread_queue.empty():
        i = exec_thread_queue.get()
        logging.debug("Starting thread: %s" % i)
        i.start()

      exec_thread_queue.join()

  opsdbcursor.close()
  opsdb().close()

  readlog = open('/var/log/shards/%s' % logfile,'rU')
  printinfo = re.findall(r'INFO\|.+', readlog.read())
  [print(i) for i in printinfo]
  readlog.close()

  print()
  print("Log File: /var/log/shards/%s" % logfile)
  print()

if __name__ == '__main__':
  try:
    main()
  except KeyboardInterrupt:
    print('<Interrupted>')
    try:
      sys.exit(0)
    except SystemExit:
      os._exit(0)
