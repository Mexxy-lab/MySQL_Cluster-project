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
# Purpose: Execute SQL Statements in Shards
# Usage:   Run with --help.
#
###############################################################################

from __future__ import print_function
import os,re,sys,time,subprocess,threading,MySQLdb,logging,Queue,argparse,codecs

reload(sys)
sys.setdefaultencoding('utf-8')

# Custom python modules for MySQL and system calls

sys.path.append("/usr/local/ops/bin/pydb")

from opsdb_host_info import parameter,slack_hook,opsdb,host_info,max_instance_number,show_db,check_for_cpids,mysql_fail,shard_groups,shard_schemas

def host_shard_batch(dc,shardgroup,batchsize,offset=0):

  # Generates batches of shard instances for further processing with --limit_per_host. Returns a list of shard lists (batches)

  shardlines = []
  shardn = offset
  fqdns = []

  opsdbcursor = opsdb().cursor()
  opsdbcursor.execute("select distinct fqdn from host_info where role like '%%shard%%' and dataCenter='%s' and groupName='%s'" % (dc,shardgroup))
  output = opsdbcursor.fetchall()

  for fqdn in output:
    fqdns.append(fqdn[0])

  while int(shardn) <= 16:

    shardbatch = []

    for fqdn in fqdns:
      opsdbcursor = opsdb().cursor()
      opsdbcursor.execute("select shardNumber from host_info where fqdn='%s' and role like '%%shard%%' and groupName ='%s' limit %d,%d" % (fqdn,shardgroup,int(shardn),int(batchsize)))
      output = opsdbcursor.fetchall()

      for n in output:
        shardbatch.append(int(n[0]))

    shardn = shardn + int(batchsize)
    if len(shardbatch) > 0:
      shardlines.append(shardbatch)

  opsdbcursor.close()
  opsdb().close()

  return shardlines

def instance_threads(s_dc, s_group, s_num, s_filter, s_log, noprompt=0, s_name='information_schema', s_osc=False):

  # Lauches threads for processing shards, one thread per instance

  def schema_info(schemaname):
#    if schemaname in ('information_schema','mysql','federated_mono'):
    if schemaname in ('federated_mono'):
      s_info = 1
    else:
      opsdbcursor = opsdb().cursor()
      opsdbcursor.execute("select numOfschema from schema_info where isSharded='Y' and schemaName='%s'" % schemaname)
      output = opsdbcursor.fetchone()
      if not output:
        print("{0} is missing in schema_info.".format(schemaname))
        sys.exit(1)
      opsdbcursor.close()
      opsdb().close()
      s_info = int(output[0])

    return s_info

  def exec_script(dbcnx,hostnport):

    # Threads - Executes SQL script or statement

    global shards_to_skip

    # shard_full_list is compiled to contain all shard schemas for further processing

    schema_full_list = []

    for i in show_db(dbcnx,s_name):
      schema_full_list.append("{0}:{1}:{2}".format(hostnport[0],hostnport[1],i))

    dbcnx.close()

    # Statements are executed in all shard schemas listed in schema_fill_list

    for i_shard in schema_full_list:
      shard_connect = {
      'user': parameter()[0].strip("'"),
      'passwd': parameter()[1].strip("'"),
      'host': i_shard.split(':')[0],
      'port': int(i_shard.split(':')[1]),
      'db'  : i_shard.split(':')[2],
      'use_unicode': True
      }

      try:
        shardcnx = MySQLdb.connect(host=shard_connect['host'],  # your host
                     user=shard_connect['user'],       # username
                     passwd=shard_connect['passwd'],     # password
                     unix_socket='{{ socket  }}',  # DB Socket
                     port=shard_connect['port'],
                     db=shard_connect['db'])   # name of the database
      except MySQLdb.Error as err:
        mysql_fail(err,hostnport)
      else:
        shardcnx.autocommit(True)
        shardstatus = 0
        print("Processing %s " % i_shard)

        cursor = shardcnx.cursor()

        stmtskip = 0

        for stmt in s_filter:
          outprefix = '%s:%s:%s|' % (i_shard.split(':')[0],i_shard.split(':')[1],i_shard.split(':')[2])
          if "Shard "+outprefix+"%s|OK" % stmt in shards_to_skip:
            logging.info("Shard %s%s|Skip" % (outprefix,stmt))
            stmtskip = stmtskip+1
          else:
            try:
              cursor.execute(stmt)
            except MySQLdb.Error as err:
              logging.error("Shard %s%s|Fail" % (outprefix,stmt))
              mysql_fail(err,hostnport)
              shardstatus = 1
            else:
              logging.info("Shard %s%s|OK" % (outprefix,stmt))
              output = cursor.fetchall()

              outstring = []

              for (output) in cursor:
                for i in output:
                  outrow = args.columnseparator.join(str(n).replace('None','Null') for n in output)

                outstring.append(outrow)

              logging.info(outprefix + args.rowseparator.join(outstring))

        cursor.close()
        shardcnx.commit()
        shardcnx.close()

        logger.debug("Flushing execution logs...")
        [h.flush() for h in logger.handlers]

      if stmtskip == len(s_filter):
        sharddict[outprefix] = 2
      else:
        sharddict[outprefix] = shardstatus

    thread_queue.task_done()

  def pt_osc(dbcnx,hostnport,_keep):

    # Threads - Executes DDL statements using PT_OSC

    global shards_to_skip

    # shard_full_list is compiled to contain all shard schemas for further processing

    schema_full_list = []

    for i in show_db(dbcnx,s_name):
      schema_full_list.append("{0}:{1}:{2}".format(hostnport[0],hostnport[1],i))

    dbcnx.close()

    osc_stmt = s_filter[0].split()
    if osc_stmt[0].lower() != 'alter' or osc_stmt[1].lower() != 'table' :
      print("Invalid alter statement")
      sys.exit(1)
    else:
      osc_table = osc_stmt[2]
      osc_action = ' '.join(i for i in osc_stmt[3:])
      osc_action = re.sub(';','',osc_action)

    # DDL statements are executed in all shard schemas listed in schema_fill_list using pt_osc

    for i_shard in schema_full_list:

      shardstatus = 0
      stmtskip = 0
      outprefix = '%s:%s:%s|' % (i_shard.split(':')[0],i_shard.split(':')[1],i_shard.split(':')[2])

      if "Shard "+outprefix+"%s|OK" % osc_action in shards_to_skip:
        logging.info("Shard %s%s|Skip" % (outprefix,osc_action))
        stmtskip = stmtskip+1
      else:
        osc_shell_call = subprocess.Popen(['/usr/bin/pt-online-schema-change','h=%s,P=%d,D=%s,u=%s,p=%s,t=%s' % (i_shard.split(':')[0],int(i_shard.split(':')[1]),i_shard.split(':')[2],parameter()[0],parameter()[1],osc_table),'--alter','%s' % osc_action,'--execute','--critical-load','threads_running=100','--max-load','threads_running=50','--recursion-method','none','--%sdrop-old-table' % _keep], stdout=subprocess.PIPE,stderr=subprocess.STDOUT)

        out = osc_shell_call.communicate()

        if osc_shell_call.returncode == 0:
          logging.info("Shard %s%s|OK" % (outprefix,osc_action))
        else:
          print('%s:%d:%s:%s: pt-osc failed' % (i_shard.split(':')[0],int(i_shard.split(':')[1]),i_shard.split(':')[2],osc_table))
          logging.error("Shard %s%s|Fail" % (outprefix,osc_action))
          shardstatus = 1

        osc_shell_call.wait()

        logging.info(out[0].strip())

        logger.debug("Flushing execution logs...")
        [h.flush() for h in logger.handlers]

      if stmtskip == len(s_filter):
        sharddict[outprefix] = 2
      else:
        sharddict[outprefix] = shardstatus

    thread_queue.task_done()

# Body of instance_threads

  opsdbcursor = opsdb().cursor()

  thread_queue = Queue.Queue()

  logger = logging.getLogger()

  sharddict = {}
  skipinstance = 0
  shardmatch = 0

  for sn in [int(i) for i in s_num]:

    opsdbcursor.execute("select fqdn,port from host_info where groupName='%s' and role like '%%shard%%' and shardNumber=%d and dataCenter='%s'" % (s_group, sn, s_dc.lower()))
    hostnport = opsdbcursor.fetchone()

    if hostnport is None:
      print("Instance %d is invalid for %s" % (int(sn),s_group))
      sys.exit(1)

    instanceconnect = {
    'user': parameter()[0].strip("'"),
    'passwd': parameter()[1].strip("'"),
    'host': hostnport[0],
    'port': int(hostnport[1]),
    'db': 'information_schema',
    'use_unicode': True
    }
    try:
      cnx = MySQLdb.connect(host=instanceconnect['host'],  # your host
                      user=instanceconnect['user'],  # username
                      passwd=instanceconnect['passwd'],  # password
                      unix_socket='{{ socket  }}',  # DB Socket
                      port=instanceconnect['port'],
                      db=instanceconnect['db'])  # name of the database
    except MySQLdb.Error as err:
      logging.critical("{0}:{1}".format(str(hostnport[0]),str(hostnport[1])))
      mysql_fail(err,hostnport)
    else:
      if len(show_db(cnx,s_name)) == 0:
        logging.debug("%s:%s: No %s shards were found. Skipping" % (hostnport[0],hostnport[1],s_name))
        skipinstance = skipinstance+1
        cnx.close()
      else:
        print("Preparing %s:%s" % hostnport)
        cnx.cursor().execute("set wait_timeout=3600")
        shardmatch = shardmatch + len(show_db(cnx,s_name))
        cnx.cursor().close()

        # Generating threads

        if not s_osc:
          shard_thread = threading.Thread(name='%s' % hostnport[1], target=exec_script, args=(cnx,hostnport,))
        else:
          if args.keep_old_table:
            _keep = 'no-'
          else:
            _keep=''
          shard_thread = threading.Thread(name='%s' % hostnport[1], target=pt_osc, args=(cnx,hostnport,_keep,))

        shard_thread.daemon = True

        # Queuing threads

        thread_queue.put(shard_thread)

  if thread_queue.qsize() > 0:
    print('======================================================================')
    [print(x) for x in s_filter]
    print('======================================================================')
    print("Processing {0} in {1} instances. ".format(s_name,thread_queue.qsize()))
    if skipinstance > 0:
      print("{0} was not found in {1} instances. Skipping.".format(s_name,skipinstance))
    print()

    if shardmatch != schema_info(s_name)*len(s_num):
      print("Warning: Processing {0} {1} shards out of {2} total.".format(shardmatch,s_name,schema_info(s_name)))
      print()

    if noprompt == 0:
      print("%d threads are ready to launch" % thread_queue.qsize())
      print("   Press \'Enter\' to proceed or any other key to quit  " , end="")

      gonogo = raw_input()
      if len(gonogo) > 0:
        sys.exit(0)

    # Launching Threads in parallel mode or serialized (--serialize)

    while not thread_queue.empty():

      i = thread_queue.get()
      logging.debug("Starting thread: %s" % i)
      i.start()

#      logger = logging.StreamHandler()
#      logger.flush()

      if args.serialize:
        i.join()
        while i.is_alive() > 0:
          print("Waiting for thread to finish")
          time.sleep(1)

    thread_queue.join()

  opsdbcursor.close()
  opsdb().close()
  return sharddict

# Processing input arguments
def process_args():

  parser = argparse.ArgumentParser(description='Parallel SQL execution in shards', epilog='Default Log Destination - /var/log/shards')
  actiongroup = parser.add_mutually_exclusive_group(required=True)
  parser.add_argument("-q", "--noprompt", help="Optional - Enables NonInteractive mode", action='store_true', required=False)
  parser.add_argument("-z", "--serialize", help="Fully Sequential Mode", action='store_true', required=False)
  parser.add_argument("-d", "--datacenter", choices=['euw2'], help="Data Center. Example: ckw/cke", required=True)
  parser.add_argument("-g", "--shardgroup", help="Example: budb/fldb/fodb", required=True)
  parser.add_argument("-s", "--shardname", help="Shard schema name", nargs='?', required=True)
  parser.add_argument("-x", "--columnseparator", help="Optional - Character sequence to separate column values. Default: ','", nargs='?', const=',', required=False)
  parser.add_argument("-r", "--rowseparator", help="Optional - Character sequence to separate rows. Default: '|'", nargs='?', const='|', required=False)
  parser.add_argument("-n", "--shardnn", help="Threading method - Shard sets. Example: -n 128|1,128|1-8",metavar="Set of instances", nargs='?')
  parser.add_argument("-p", "--limit_per_host", help="Threading method - Number of instances per host. Example: -p 2", nargs='?', type=int)
  parser.add_argument("-f", "--offset_per_host", help="Offsets number of instances per host to suppliments --limit_per_host, Default: 0, Example: -f 4", nargs='?', type=int, const=0)
  parser.add_argument("-l", "--logfile", help="Log file. Example: shards.log", required=False)
  parser.add_argument("-t", "--output", help="Writes query output to a file. Ignored when used with OSC. Default: STOUT", const='stout', nargs='?', required=False)
  actiongroup.add_argument("-e", "--execute", metavar="Script File/\"SQL Statement\"", help="Script or Statement. Example: br_nnn_shards.sql/\"show slave status\"")
  actiongroup.add_argument("-o", "--osc", metavar="\"Alter Table Statement\"", help='Alter statement. Example: \"alter table xxxx add yyy bigint\"')
  parser.add_argument("--keep_old_table", help="Keeping old table while running in OSC mode", action='store_true', required=False)
  args = parser.parse_args()

  return args

def main():

  global shards_to_skip,args

  logfile = None
  email_status = 0

  if len(check_for_cpids(sys.argv[0])) > 5:
    print("{0} is already in action. Check for active instances: 'pgrep -lf {0}'".format(sys.argv[0].split('/')[-1]))
    sys.exit(0)

  args = process_args()

  if args.shardgroup not in shard_groups():
    print("%s - Unknown Shard Group" % args.shardgroup)
    sys.exit(1)

  if args.shardname not in shard_schemas() and args.shardname != 'federated_mono':
    print("%s - Unknown Shard Schema" % args.shardname)
    sys.exit(1)

  if args.columnseparator is None:
    args.columnseparator = ','

  if args.rowseparator is None:
    args.rowseparator = '|'

  if args.offset_per_host is not None and args.limit_per_host is None:
    print('OFFSET_PER_HOST can only be used along with LIMIT_PER_HOST.')
    sys.exit(1)

  if args.keep_old_table and args.osc is None:
    print('KEEP_OLD_TABLE can only be used along with OSC.')
    sys.exit(1)

# List of shard instances

  max_instance = max_instance_number(args.datacenter,args.shardgroup)
  shardline = []
  shardlines = []

  if args.shardnn is not None:

    s_range = re.search('([\d]+)-([\d]+)', args.shardnn)

    if s_range and int(s_range.group(1)) >= 1 and int(s_range.group(2)) <= max_instance and int(s_range.group(1)) <= int(s_range.group(2)):
      shardline = range(int(s_range.group(1)),int(s_range.group(2))+1)

    elif args.shardnn.isdigit() and 1<=int(args.shardnn)<= max_instance:
      shardline = [int(args.shardnn)]

    elif re.search(',', args.shardnn):
      shardline = args.shardnn.split(',')
      shardline = [shardn for shardn in shardline if shardn.isdigit() and 1<=int(shardn)<=max_instance]

    else:
      print("Invalid Instance Numbers: %s" % args.shardnn)
      sys.exit(1)

    shardlines.append(shardline)

  if args.limit_per_host is not None:

    if not 1<=int(args.limit_per_host)<= 16:
      print("Invalid Instance number: %s" % args.limit_per_host)
      sys.exit(1)
    else:
      if args.offset_per_host is None:
        args.offset_per_host = 0
      shardlines = host_shard_batch(args.datacenter,args.shardgroup,args.limit_per_host,args.offset_per_host)

      if args.shardnn and len(shardline) > 0:
        nnshardlines = []
        for shardln in shardlines:
          nnshardlines.append(sorted(list(set(shardline) & set(shardln))))
        shardlines = nnshardlines

  if len(shardline) == 0 and len(shardlines) == 0:
    shardlines.append(range(1,max_instance_number(args.datacenter,args.shardgroup)+1))

# Script or Statement

  if args.execute:

    if os.path.isfile(args.execute) and os.access(args.execute, os.R_OK):
      script = open(args.execute,'rU')

    else:
      print('Script is not found: %s' % args.execute)
      print('Executing \"%s\" as a single statement' % args.execute)
      stmt = args.execute + ';'

      if os.path.isfile('/tmp/stmt.sql'):
        os.remove('/tmp/stmt.sql')

      script = open('/tmp/stmt.sql','w')
      script.write(stmt)
      script.close()
      script = open('/tmp/stmt.sql','rU')

  lastposition = 0

  if args.execute:
    if not args.logfile and os.path.isfile(args.execute):
      logfile = re.sub('\..+$','.log',re.sub('.+\/','',args.execute))
    elif not args.logfile and not os.path.isfile(args.execute):
      logfile = 'stmt.log'
    else:
      logfile = args.logfile

# Percona OSC

  if args.osc:

    if not args.logfile:
      logfile = 'osc_stmt.log'
    else:
      logfile = args.logfile

    osc_stmt = args.osc + ';'

    if os.path.isfile('/tmp/osc_stmt.sql'):
      os.remove('/tmp/osc_stmt.sql')

    script = open('/tmp/osc_stmt.sql','w')
    script.write(osc_stmt)
    script.close()
    script = open('/tmp/osc_stmt.sql','rU')


  if len(logfile.split('/')) > 1:
    if not os.path.exists(os.path.dirname(logfile)):
      print("Invalid path for logfile")
      sys.exit(0)
  else:
    logfile = '/var/log/shards/%s' % logfile

  if os.path.isfile(logfile):
    gonogo = 'n'
    while gonogo.lower() not in ('q','o','p'):
      print("%s already exists. Overwrite(o), Process(p), Quit(q):" % logfile,end=' ')
      gonogo = raw_input()
      if gonogo.lower() == 'q':
        sys.exit(0)
      elif gonogo.lower() == 'o':
        os.remove(logfile)
      elif gonogo.lower() == 'p':
        print("Processing and extending %s" % logfile)
        readlog = open('%s' % logfile,'rU')
        shards_to_skip = re.findall(r'Shard.+\|OK', readlog.read())
        lastposition = readlog.tell()
        readlog.close()

  logging.basicConfig(filename='%s' % logfile,format='%(levelname)s|%(asctime)s|%(threadName)s|%(message)s',level=logging.INFO)

# SQL Execution Threads
  s_filter = []
  statements = re.findall(r'.+?;', script.read().replace('\n', ''))

  for stmt in (x for x in statements if not x.startswith('#') and not x.startswith('--')):
    s_filter.append(stmt)

  total_shards_queued = 0
  total_shards_ok = 0
  total_shards_fail = 0
  total_shards_skip = 0

  for shardline in shardlines:

    if len(s_filter) > 0:
      sharddict = instance_threads(args.datacenter,args.shardgroup,shardline,s_filter,logfile,args.noprompt,args.shardname,args.osc)
    else:
      print("No valid statements were found. Correct the script/statement")
      sys.exit(1)

    shards_ok = sum(1 for v in sharddict.values() if v == 0)
    shards_fail = sum(1 for v in sharddict.values() if v == 1)
    shards_skip = sum(1 for v in sharddict.values() if v == 2)

    total_shards_queued = total_shards_queued + len(sharddict)
    total_shards_ok = total_shards_ok + shards_ok
    total_shards_fail = total_shards_fail + shards_fail
    total_shards_skip = total_shards_skip + shards_skip

    if len(shardlines) > 1:
      print("------------- Status --------------")
      print("%s shards queued:     %d" % (args.shardname,len(sharddict)))
      print("%s shards completed:  %d" % (args.shardname,shards_ok))
      print("%s shards failed:     %d" % (args.shardname,shards_fail))
      print("%s shards skipped:    %d" % (args.shardname,shards_skip))
      print("-----------------------------------")

  print("\t-------------- Summary ---------------")
  print("\t%s shards queued:     %d" % (args.shardname,total_shards_queued))
  print("\t%s shards completed:  %d" % (args.shardname,total_shards_ok))
  print("\t%s shards failed:     %d" % (args.shardname,total_shards_fail))
  print("\t%s shards skipped:    %d" % (args.shardname,total_shards_skip))

  if len(s_filter) > 1:

    readlog = open('%s' % logfile,'rU')
    readlog.seek(lastposition)
    stmt_ok = re.findall(r'Shard.+\|OK', readlog.read())
    readlog.seek(lastposition)
    stmt_fail = re.findall(r'Shard.+\|Fail', readlog.read())
    readlog.seek(lastposition)
    stmt_skip = re.findall(r'Shard.+\|Skip', readlog.read())
    readlog.close()

    print("\tStatements succeeded:  %d" % len(stmt_ok))
    print("\tStatements failed:     %d" % len(stmt_fail))
    print("\tStatements skipped:    %d" % len(stmt_skip))
  print("\t--------------------------------------")

  print("Execution Log File: %s" % logfile)

  if args.output and not args.osc:

    readlog = codecs.open('%s' % logfile,'rU','utf-8')

    if args.output != 'stout':

      if len(args.output.split('/')) > 1 and not os.path.exists(os.path.dirname(args.output)):
        print("Invalid path for output file")
        sys.exit(1)

      outputfile = codecs.open('%s' % args.output,'w+','utf-8')

    for line in readlog:
      if not re.search(r'Shard.+\|OK',line):
        if args.output == 'stout':
          print(line)
        else:
          outputfile.write(line)

    readlog.close()

    if args.output != 'stout':
      outputfile.close()
      print("Query Output File: %s" % args.output)

  logging.shutdown()

  if args.execute or args.osc:
    slack_hook(email_status,s_filter)

if __name__ == '__main__':
  try:
    shards_to_skip = []
    main()
  except KeyboardInterrupt:
    print('<Interrupted>')
    try:
      sys.exit(0)
    except SystemExit:
      os._exit(0)
