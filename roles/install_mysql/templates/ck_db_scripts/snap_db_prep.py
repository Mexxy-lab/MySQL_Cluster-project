#!/usr/bin/python -tt

import os,re,sys,subprocess
import MySQLdb

def mysql_fail(error):
  print("MySQL Error: %s" % str (error))

def all_shards(s_tier, s_schema, s_script):

  global cnx

  print "Shard Tier {0} at {1}".format(s_tier.split('.')[0],s_tier.split('.')[1])
  print "Press \'Enter\' to proceed or any other key to quit"
  gonogo = raw_input()
  if len(gonogo) > 0:
    sys.exit(0)

  if s_tier.split('.')[0] in ['fldb','fodb']:
    shardline = ['001','002','003','004','005','006','007','008','009','010','011','012','013','014','015','016']
  elif s_tier.split('.')[0] == 'budb':
    shardline = ['001','002','003','004','005','006','007','008']

  for shardn in shardline:
    dbports = host_info(s_tier.split('.')[0] + str(shardn) + '.' + s_tier.split('.')[1],'shard')
    for port in dbports:
      dbconnect = {
      'user': dbusername,
      'passwd': dbpasswd,
      'host': dbhost,
      'port': int(port),
      'db': 'information_schema',
      'use_unicode': True
      }
      try:
        cnx = MySQLdb.connect(**dbconnect)
      except MySQLdb.Error as err:
        print "{0}:{1}".format(dbhost,port)
        mysql_fail(err)
        sys.exit(1)
      else:
        shard_full_list = []
        print "Databases in {0}:{1}".format(s_tier.split('.')[0] + str(shardn),port)
        for i in show_db(s_schema):
          if i != None:
            shard_full_list.append("{0}:{1}:{2}".format(dbhost,port,i))
        cnx.close()

        for i in shard_full_list:
          shard_connect = {
          'user': dbusername,
          'passwd': dbpasswd,
          'host': i.split(':')[0],
          'port': int(i.split(':')[1]),
          'db': i.split(':')[2],
          'use_unicode': True
          }

          try:
            cnx = MySQLdb.connect(**shard_connect)
          except MySQLdb.Error as err:
            mysql_fail(err)
          else:
            cursor = cnx.cursor()
            query = ("show tables")
            anytables = cursor.execute(query)
            if anytables != 0:
              print "Processing {0}:".format(i.split(':')[2])
              exec_script(s_script)
            else:
              print "{0} is empty. Skipping".format(i.split(':')[2])
            cursor.close()
          cnx.close()
        print '------------------------------'

def query(query):
  cursor = cnx.cursor()
  try:
    cursor.execute(query)
    output = cursor.fetchall()
  except MySQLdb.Error as err:
    mysql_fail(err)
  else:
    for row in output:
      rowlist = ""
      for col in row:
        rowlist = rowlist + str(col) + ' '
      print rowlist
    cnx.commit()
  cursor.close()

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

def exec_script(scriptName):
  if os.path.isfile(scriptName) and os.access(scriptName, os.R_OK):
    script = open(scriptName,'rU')
  else:
  	print 'Script cannot be found/accessed'
  	sys.exit(1)

  statements = re.findall(r'.+?;\s', script.read().replace('\n', ' '))
  for stmt in statements:
    query(stmt.strip(';\ '))
  script.close()

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
    print col_name[0]
    print '----------------------------------'
    for (output) in cursor:
      print("%s" % output)
  cursor.close()

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
    print col_string
    print '-------------------------------------------------------------'
    output = cursor.fetchall()
    for (id, user, host, time, command, state) in output:
      print ("{0} | {1} | {2} | {3} | {4} | {5}".format(id, user, host, time, command, state))
  cursor.close()

def slave_status():
  cursor = cnx.cursor()
  query = ("show slave status")

  try:
    cursor.execute(query)
  except MySQLdb.Error as err:
    mysql_fail(err)
  else:
    for (output) in cursor:
        print '----------------------------'
        print 'Master Host: ', output[1]
        print 'Master Port: ', output[3]
        print 'Master Log File: ', output[5]
        print 'Read Master Log Position: ', output[6]
        print 'Exec Master Log Position: ', output[21]
        print 'Relay Log File: ', output[7]
        print 'Relay Log Position: ', output[8]
        print 'Relay Master Log File: ', output[9]
        print 'Slave IO Running: ', output[10]
        print 'Slave SQL Running: ', output[11]
        print 'Seconds behind master: ', output[32]
        print 'SQL Delay: ', output[42]
        print 'SQL Remaining Delay: ', output[43]
        print 'Slave_SQL_Running_State: ', output[44]
        print 'Relay Log (MB): ', int(output[22])/1024/1024
        print 'Last SQL Error: ', output[37]
  cursor.close()

  try:
    cursor.execute(query)
  except MySQLdb.Error as err:
    mysql_fail(err)
  else:
    col_names = [i[0] for i in cursor.description]
    print col_names
    print '-----------------------------------'
    for (grantee, privilege, password) in cursor:
      print ("{0} {1} {2}".format(grantee, privilege, password))
  cursor.close()

def host_info(hostname,role=''):

  def quit_host_info():
    cursor.close()
    localcnx.close()
    sys.exit(1)

  global dbhost

  dblocal = {
    'user': dbusername,
    'passwd': dbpasswd,
    'host': 'localhost',
    'port': 3306,
    'unix_socket': '/db/data/opsdb/mysql/mysql.sock',
    'db': 'ckadmin',
    'use_unicode': True
    }

  try:
    localcnx = MySQLdb.connect(**dblocal)
  except MySQLdb.Error as err:
    mysql_fail(err)
    sys.exit(1)
  else:
    cursor = localcnx.cursor()

  hostandport = re.search('(^[\w.]+):([\d,-]+$)', hostname)

  if hostandport:
    hhost = hostandport.group(1)
  else:
    hhost = hostname

  query = ("select count(distinct fqdn) from host_info where fqdn like '%s%%' and role like '%s%%'" % (hhost, role))

  try:
    cursor.execute(query)
  except MySQLdb.Error as err:
    mysql_fail(err)
    quit_host_info()
  else:
    host_match = cursor.fetchone()
    if int(host_match[0]) == 0:
      print "{0} - Unknown db host".format(hhost)
      quit_host_info()
    elif int(host_match[0]) > 1:
      print "Ambiguous name for db host"
      quit_host_info()
    else:
      query = ("select distinct fqdn from host_info where fqdn like '%s%%' and role like '%s%%'" % (hhost, role))
      cursor.execute(query)
      dbhost = cursor.fetchone()[0]

  if hostandport:
    if re.search(',', hostandport.group(2)) or hostandport.group(2).isdigit():
      dbports = hostandport.group(2).split(',')
    else:
      portrange = re.search('([\d]+)-([\d]+)', hostandport.group(2))
      if portrange and (int(portrange.group(1)) < int(portrange.group(2))):
        dbports = range(int(portrange.group(1)),int(portrange.group(2))+1)
      else:
        print "Invalid port range"
        quit_host_info()

    dbports = [int(i) for i in dbports]
    portlist=[]
    for i in dbports:
      query = ("select count(1) from host_info \
              where port in (%d) and fqdn='%s' and role like '%s%%'" % (i, dbhost, role))
      cursor.execute(query)
      port_match = cursor.fetchone()

      if int(port_match[0]) == 0:
        print "Invalid port: ", i
        quit_host_info()
      else:
        portlist.append(i)
    dbports = portlist

# No ports provided
  else:
    dbports = []
    query = ("select port from host_info where fqdn = '%s' and role like '%s%%' order by 1" % (dbhost, role))
    cursor.execute(query)
    for port in cursor:
      dbports.append(int(port[0]))

    if role != 'shard' and len(dbports) > 1:
      print "Validated ports for {0}: ".format(dbhost)
      for i in dbports:
        print "\t{0}".format(i)

      print "Press 'Enter\' for all ports or any non-numeric key to quit"
      iports = raw_input("Ports: (e.g. 3306|3311,..|3301-..) ")
      if len(iports) > 0:
        if iports == '0' or not re.search('([\d,-]+)', iports):
          sys.exit(0)
        elif re.search(',', iports) or iports.isdigit():
          iports = iports.split(',')
        elif re.search('([\d]+)-([\d]+)', iports):
          portrange = re.search('([\d]+)-([\d]+)', iports)
          if (int(portrange.group(1)) < int(portrange.group(2))):
            iports = range(int(portrange.group(1)),int(portrange.group(2))+1)
          else:
            print "Invalid port range"
            quit_host_info()
        try:
          iports = [int(i) for i in iports]
        except ValueError:
          print "Non-Numeric values for numeric ports:"
          print dbports
          quit_host_info()

        if set(iports) < set(dbports):
          dbports=iports
        else:
          print "Invalid ports found", iports
          quit_host_info()

  if not dbhost or len(dbports) == 0:
    quit_host_info()
  else:
    cursor.close()
    localcnx.close()
    return dbports

def copout():
    print "Usage: %s host[:port,port,.. | :minport-maxport]  | shard_group modulename" % sys.argv[0]
    print "Modules:"
    print "[--proc | --status | --slave | --query query | --admin command | --exec_script scriptname |  --all_shards schemaname scriptname"
    sys.exit(1)

def main():

  global cnx
  global dbhost
  global dbusername
  global dbpasswd

  if len(sys.argv) < 3:
    copout()

  if len(sys.argv) > 3:
    dbparam = sys.argv[3]
  else:
    dbparam = ''

  if sys.argv[2].replace('--','') not in ('slave','status','proc','exec_script','admin','query','all_shards'):
    copout()

  file = open('/usr/local/ops/bin/parameter.txt','rU')

  for line in file:
    col1 = line.strip().split('=')[0]
    if col1 == 'USER':
      col2 = line.strip().split('=')[1]
      dbusername = col2.strip('"')
    if col1 == 'PASSWD':
      col2 = line.strip().split('=')[1]
      dbpasswd = col2.strip('"')

  file.close()

  dbhost = sys.argv[1]

  if (dbhost in ['budb.iad1','budb.sjc1','fldb.sjc1','fodb.sjc1','fldb.iad1','fodb.iad1']
  	  and sys.argv[2] == '--all_shards'):
    if (len(sys.argv) > 4 and sys.argv[3] in ['mysql','information_schema','ip','accessRequestId','numericId','cookieId']):
      all_shards(dbhost,sys.argv[3],sys.argv[4])
    else:
      print "Invalid or missing options for shards"
      copout()
  else:
    dbports = host_info(dbhost)

    for iport in dbports:
      print
#      print "Port %s:" % iport

      dbconnect = {
      'user': dbusername,
      'passwd': dbpasswd,
      'host': dbhost,
      'port': iport,
      'db': 'information_schema',
      'use_unicode': True
      }

      try:
        cnx = MySQLdb.connect(**dbconnect)
      except MySQLdb.Error as err:
        mysql_fail(err)
        sys.exit(1)
      else:
        cnx.autocommit(True)

      if sys.argv[2] == '--slave':
        slave_status()

      elif sys.argv[2] == '--exec_script':
        if len(sys.argv) < 4:
          cnx.close()
          copout()
        else:
          exec_script(sys.argv[3])

      elif sys.argv[2] == '--status':
        global_status(dbparam)

      elif sys.argv[2] == '--proc':
        processlist(dbparam)

      elif sys.argv[2] == '--query':
        if len(sys.argv) < 4:
          cnx.close()
          copout()
        else:
          query(dbparam)

      elif sys.argv[2] == '--admin':
        if len(sys.argv) < 4:
          cnx.close()
          copout()
        else:
          admin_cmd(dbparam)

      else:
        cnx.close()
        copout()

      cnx.close()

if __name__ == '__main__':
  main()
