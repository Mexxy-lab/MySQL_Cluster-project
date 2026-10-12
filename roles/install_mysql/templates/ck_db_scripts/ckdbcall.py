#!/usr/bin/python -tt

from __future__ import print_function
import os,re,sys,subprocess,threading,MySQLdb

sys.path.append("/usr/local/ops/bin/pydb")

from opsdb_host_info import parameter,opsdb,host_info,slave_status,show_db,find_table,dc_domain,query,exec_script

def mysql_fail(error):
  print("MySQL Error: %s" % str (error))

def exec_shards(s_tier, s_num, s_schema, s_script):

  if re.search('sjc1.', dc_domain()):
    dc = 'CKW'
  elif re.search('iad1.', dc_domain()):
    dc = 'CKE'
  else:
    print(dc_domain())
    sys.exit(1)

  s_range = re.search('([\d]+)-([\d]+)', s_num)
  if s_range and int(s_range.group(1)) >= 1 and int(s_range.group(2)) <= 128 and int(s_range.group(1)) <= int(s_range.group(2)):
    shardline = range(int(s_range.group(1)),int(s_range.group(2))+1)
  elif s_num.isdigit():
    shardline = [s_num]
  else:
    copout()

  opsdbcursor = opsdb().cursor()

  shard_threads = []

  for sn in [int(i) for i in shardline]:

    opsdbcursor.execute("select fqdn,port from host_info where groupName='%s' and role='shard' and shardNumber=%d and dataCenter='%s'" % (s_tier, sn, dc.lower()))
    hostnport = opsdbcursor.fetchone()

    shardconnect = {
      'user': parameter()[0],
      'passwd': parameter()[1],
      'host': hostnport[0],
      'port': int(hostnport[1]),
      'db': 'information_schema',
      'use_unicode': True
      }
    try:
      shardcnx = MySQLdb.connect(**shardconnect)
    except MySQLdb.Error as err:
      print("{0}:{1}".format(hostnport[0],hostnport[1]))
      mysql_fail(err)
      sys.exit(1)
    else:
      schema_full_list = []
      print("Executing {0} in schemas that match {1} in {2}:{3}".format(s_script, s_schema,hostnport[0],hostnport[1]))
      if len(show_db(shardcnx,s_schema)) > 0:
        for i in show_db(shardcnx,s_schema):
          schema_full_list.append("{0}:{1}:{2}".format(hostnport[0],hostnport[1],i))

    shardcnx.close()

    if len(schema_full_list) == 0:
      print("No schemas that match %s were not found. Script hasn't been excuted" % s_schema)
      copout()

    else:
      print('------------------------------')

      for i in schema_full_list:
        shard_connect = {
        'user': parameter()[0],
        'passwd': parameter()[1],
        'host': i.split(':')[0],
        'port': int(i.split(':')[1]),
        'db'  : i.split(':')[2],
        'use_unicode': True
        }

        try:
          cnx = MySQLdb.connect(**shard_connect)
        except MySQLdb.Error as err:
          mysql_fail(err)
        else:
          anytables = cnx.cursor().execute("show tables")
          if anytables != 0:
            print("Processing %s " % i)
            shard_thread = threading.Thread(target=exec_script, args=(cnx, s_script,))
            shard_thread.daemon = True
            shard_threads.append(shard_thread)
          else:
            print("{0} is empty. Skipping".format(i.split(':')[2]))
      print('------------------------------')

  print('==========================================================================================================')
  print("About to execute script {0} in {1} shard tier at {2}, instances: {3}".format(s_script,s_tier.upper(), dc, s_num))
  print("%d threads are ready to launch" % len(shard_threads))
  print("   Press \'Enter\' to proceed or any other key to quit  " , end="")
  gonogo = raw_input()

  if len(gonogo) > 0:
    sys.exit(0)
  else:
    for i in shard_threads:
      i.start()

    for i in shard_threads:
      i.join()

def admin_cmd(query):
  cursor = cnx.cursor()
  try:
    cursor.execute(query)
  except MySQLdb.Error as err:
    mysql_fail(err)
  else:
    for (output) in cursor:
      print("%s" % output)
    cnx.commit()
  cursor.close()
  cnx.close()

def global_variables(vname):
  cursor = cnx.cursor()
  query = ("select concat(variable_name,' => ', variable_value) as 'Variable => Setting' from global_variables\
          where variable_name like '%%%s%%' order by 1" % vname)
  try:
    cursor.execute(query)
  except MySQLdb.Error as err:
    mysql_fail(err)
  else:
    col_name = [i[0] for i in cursor.description]
    print(col_name[0])
    print("----------------------------------")
    for (output) in cursor:
      print("%s" % output)
  cursor.close()
  cnx.close()

def show_create(tname):
  cursor = cnx.cursor()
  query = ("show create table %s" % tname)
  try:
    cursor.execute(query)
  except MySQLdb.Error as err:
    print("MySQL Error: %s" % str (err))
  else:
    print("----------------------------------")
    for (output) in cursor:
      rowlist = ""
      for i in output:
        rowlist = str(i) + ' ' + rowlist
      print(rowlist)
  cursor.close()
  cnx.close()

def global_status(sname):
  cursor = cnx.cursor()
  query = ("select concat(variable_name,' => ', variable_value) as 'Status Variable => Setting' from global_status\
          where variable_name like '%%%s%%'" % sname)
  try:
    cursor.execute(query)
  except MySQLdb.Error as err:
    mysql_fail(err)
  else:
    col_name = [i[0] for i in cursor.description]
    printi(col_name[0])
    print("----------------------------------")
    for (output) in cursor:
      print("%s" % output)
  cursor.close()
  cnx.close()

def processlist(username):
  cursor = cnx.cursor()
  query = ("select id, user, substr(host from 1 for position(':' in host)-1) as 'HOST',\
            time, command, state from processlist \
            where user like '%%%s%%' order by time" % username)
  try:
    cursor.execute(query)
  except MySQLdb.Error as err:
    mysql_fail(err)
  else:
    col_names = [i[0] for i in cursor.description]
    col_string = ""
    for i in col_names:
      col_string = col_string + ' ' + '|' + ' ' + str(i)
#    print(col_string)
    print("-------------------------------------------------------------")
    output = cursor.fetchall()
    for (id, user, host, time, command, state) in output:
      print("{0} | {1} | {2} | {3} | {4} | {5}".format(id, user, host, time, command, state))
  cursor.close()
  cnx.close()

def slave_status(dbcnx):
  cursor = dbcnx.cursor()
  query = ("show slave status")

  try:
    cursor.execute(query)
  except MySQLdb.Error as err:
    mysql_fail(err)
  else:
    for (output) in cursor:
        print("----------------------------")
        print('Master Host: ', output[1])
        print('Master Port: ', output[3])
        print('Master Log File: ', output[5])
        print('Read Master Log Position: ', output[6])
        print('Relay Log File: ', output[7])
        print('Relay Log Position: ', output[8])
        print('Relay Master Log File: ', output[9])
        print('Exec Master Log Position: ', output[21])
        print('Slave IO Running: ', output[10])
        print('Slave SQL Running: ', output[11])
        print('Seconds behind master: ', output[32])
        print('SQL Delay: ', output[42])
        print('SQL Remaining Delay: ', output[43])
        print('Slave_SQL_Running_State: ', output[44])
        print('Last SQL Error: ', output[37])
        print('Retrieved GTID Set: ', output[51])
        print('Executed GTID Set: ', output[52])
        print('Auto Position: ', output[53])
  cursor.close()
  cnx.close()

def user_grants(username):
  cursor = cnx.cursor()
  query = ("select up.grantee,up.privilege_type, u.password from user_privileges up\
          join mysql.user u on concat('''',u.user,'''','@','''',u.host,'''') = up.grantee\
          where u.user like '%s%%' order by 1,2" % username)

  try:
    cursor.execute(query)
  except MySQLdb.Error as err:
    mysql_fail(err)
  else:
    col_names = [i[0] for i in cursor.description]
    print(col_names)
    print('-----------------------------------')
    for (grantee, privilege, password) in cursor:
      print("{0} {1} {2}".format(grantee, privilege, password))
  cursor.close()
  cnx.close()

def schema_grants(schemaname):
  cursor = cnx.cursor()
  query = ("select table_schema,grantee,privilege_type \
from schema_privileges where table_schema like '%%%s%%' order by 2" % schemaname)

  try:
    cursor.execute(query)
  except MySQLdb.Error as err:
    mysql_fail(err)
  else:
    print('-----------------------------------')
    for (schema,grantee,privilege) in cursor:
       print("{0} {1} {2}".format(schema, grantee, privilege))
  cursor.close()
  cnx.close()

def copout():
    print("Usage: %s host.[sjc1|iad1][:port,port,.. | :minport-maxport]  | shard_group modulename" % sys.argv[0])
    print("Modules:")
    print("[--proc | --status | --var | --show_db | --find_tab | --user_grants ] [optional searchstring] \
| --schema_grants schemaname [optional searchstring] | --show_create tablename \
| --slave | --query query | --admin command | --script scriptname \
| --exec_shards N-NN schemaname scriptname")
    sys.exit(1)

def main():

  global cnx
  global dbhost

  if len(sys.argv) < 3:
    copout()

  if len(sys.argv) > 3:
    dbparam = sys.argv[3]
  else:
    dbparam = ''

  if sys.argv[2].replace('--','') not in \
     ('slave','status','proc','var','show_create','find_tab','show_db','schema_grants',\
     'user_grants','script','admin','query','exec_shards'):
    copout()

  if sys.argv[1] in ('fldb','fodb','budb') and sys.argv[2].replace('--','') == 'exec_shards':
    if len(sys.argv) < 6:
      copout()
    else:
      exec_shards(sys.argv[1],sys.argv[3],sys.argv[4],sys.argv[5])
  else:

    dbhost = sys.argv[1]
    portlist = ""

    if len(dbhost.split(':')) > 1:
      dbhost = dbhost.split(':')[0]
      portlist = ':' + sys.argv[1].split(':')[1]

    if len(dbhost.split('.')) == 1:
      dbhost = dbhost + '.' + dc_domain()
    elif len(dbhost.split('.')) == 2 and dbhost.split('.')[1] == 'sjc1':
      dbhost = dbhost + '.' + 'creditkarma.com'
    elif len(dbhost.split('.')) == 2 and dbhost.split('.')[1] == 'iad1':
        dbhost = dbhost.split('.')[0] + '.' + 'prod.iad1.ckint.io'

    try:
      dbports = host_info(dbhost + portlist,None,'Y')
    except:
      print("%s: No valid ports were found..." % dbhost + portlist)
      sys.exit(1)

    for iport in dbports:
      print
      print("Port %s:" % iport)

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
        mysql_fail(err)
#        sys.exit(1)
        continue
      else:
        cnx.autocommit(True)

      if sys.argv[2] == '--slave':
        slave_status(cnx)

      elif sys.argv[2] == '--script':
        if len(sys.argv) < 4:
          cnx.close()
          copout()
        else:
          exec_script(cnx,sys.argv[3])

      elif sys.argv[2] == '--var':
        global_variables(dbparam)

      elif sys.argv[2] == '--status':
        global_status(dbparam)

      elif sys.argv[2] == '--proc':
        processlist(dbparam)

      elif sys.argv[2] == '--user_grants':
        user_grants(dbparam)

      elif sys.argv[2] == '--schema_grants':
        if len(sys.argv) < 4:
          cnx.close()
          copout()
        else:
          schema_grants(sys.argv[3])

      elif sys.argv[2] == '--query':
        if len(sys.argv) < 4:
          cnx.close()
          copout()
        else:
          query(cnx,dbparam,'Y')

      elif sys.argv[2] == '--admin':
        if len(sys.argv) < 4:
          cnx.close()
          copout()
        else:
          admin_cmd(dbparam)

      elif sys.argv[2] == '--show_create':
        if len(sys.argv) < 4:
          cnx.close()
          copout()
        else:
          show_create(dbparam)

      elif sys.argv[2] == '--show_db':
        for i in show_db(cnx,dbparam):
          print(i)

      elif sys.argv[2] == '--find_tab':
        for i in find_table(cnx,dbparam):
          print(i)

      else:
        cnx.close()
        copout()

if __name__ == '__main__':
  main()
