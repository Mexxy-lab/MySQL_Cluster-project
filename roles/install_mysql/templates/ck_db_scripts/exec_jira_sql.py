#!/usr/bin/python
from __future__ import print_function
from subprocess import Popen, PIPE
import json
import argparse
import sys
import MySQLdb
import re
import getpass
import os

# stores db host information
configFile = "./config.json"

# prompt for jira password
def get_jiraCredential():
    cred = {}
    cred['pwd'] = getpass.getpass("JiraPassword: ")
    return cred

# call script to parse and download sql statements 
def download_sql(args):
    try:
      jiraCred = get_jiraCredential()
      sub = Popen(['python2.7', '-c%s' % ("import local_parse_jira_sql; local_parse_jira_sql.main('" + args.ticket.upper() + "','" + jiraCred['usr'] + "','" + jiraCred['pwd'] +"')")], stdout=PIPE, stderr=PIPE)
      out = sub.communicate()
      if out[0]:
        print("%s" % out[0])
      elif out[1]:
        print("Error: %s" % out[1])
    except BaseException as e:
      print(e)

# prompt for db password
def get_dbCredential():
    cred = {}
    cred['pwd'] = getpass.getpass("DbPassword: ")
    return cred

# get path for downloaded sql 
def get_sql_path(ticketNum):
    sql_path=[]
    with open(str(ticketNum) + '/' +  'sql_path.txt','r') as f1:
        for line in (x for x in f1 if not x.startswith('#')):
          sql_path.append(line.strip('\n'))
        return sql_path

# mention of shard key in link
def get_shard_key(sql_path):
    if 'shard' in sql_path:
      shardKey = sql_path.split('/')[3]
      return shardKey
    else:
      return "none"

# parse dbtype(mono,shard) from sql_path and save
def get_db_prefix(sql_path):
  issue = sql_path.split('/')[0]
  prefix=[]
  with open(issue + '/' + 'db_schema.txt', 'r') as f:
    for line in f:
     prefix.append(line)
  return prefix

# parse db-schema-prefix
def get_raw_db_prefix(sql_path):
  issue = sql_path.split('/')[0]
  with open(issue + '/' + 'db_schema.txt', 'r') as f:
   rawDbSchema = f.read()
  return rawDbSchema

# get list of db from json file based on dbgroup schema
def get_pref_host_link(sql_path):
  hostGroups = get_db_group_info()
  prefGroups = get_db_prefix(sql_path)

  for prefGroup in prefGroups:
      prefGroup = prefGroup.strip()

      if ':' in prefGroup:
          prefDb = prefGroup.split(':')[0].strip()
          prefSchema = prefGroup.split(':')[1].strip()
          prefDbSchema = prefGroup.split(':')[0].strip() + '_' + prefGroup.split(':')[1].strip()
          for hostGroup,host in hostGroups.items():
              if 'shard' in sql_path:
                  if hostGroup == 'shard':
                      return hostGroup,prefSchema,hostGroup,host
              else:
                  if hostGroup == prefDbSchema:
                      return prefDb, prefSchema,hostGroup,host
      else:
          for hostGroup,host in hostGroups.items():
              prefDb = prefGroup
              prefSchema = prefGroup
              if 'shard' in sql_path:
                  if hostGroup == 'shard':
                      return hostGroup,prefSchema,hostGroup,host
              else:
                  if hostGroup == prefGroup:
                      return prefDb,prefSchema,hostGroup,host

# read downloaded sql
def get_sql(sql_path):
  sql=[]
  sqlCheck=re.compile('^create|^select|^show|^insert|^use|^set', re.IGNORECASE)
  ignoreText="Not Found"
  with open(sql_path, 'r') as sqlFile:
    statements = re.findall(r'.+?;', sqlFile.read().replace('\n', ''))
    for line in (x for x in statements if not x.startswith('#') and not x.startswith('--')):
        if ignoreText not in line:
            if re.match(sqlCheck, line):
                sql.append(line)
    return sql

# check sql in original format
def get_raw_sql(sql_path):
  with open(sql_path, 'r') as f:
    raw_sql = f.read()
  return raw_sql

# read config file
def getConfig():
     with open(configFile, 'r') as f:
       f.seek(0)
       config = json.load(f)
       return config

# get db host info
def get_db_group_info():
     config = getConfig()
     hostFile = config['hostFile']
     with open(''.join(hostFile), 'r') as f:
       f.seek(0)
       dbGroup = json.load(f)
       return dbGroup

# prepare host,port,schema info
def prepareHostFile(ticketNum, dbInfo, sqlLink):
    db = None
    conn = None
    dbHostList = None
    dbGroup=dbInfo[0].strip()
    dbSchema=dbInfo[1].strip()
    dbGroupSchema=dbInfo[2]
    hostList=dbInfo[3]

    if 'shard' in dbGroup:
       shardKey= get_shard_key(sqlLink)
       schemaName = dbSchema + '_' + shardKey
       dbHostList = ticketNum + '/' + schemaName + ".txt"
       if not os.path.isfile(dbHostList):
            with open (dbHostList, 'a+') as f1:
               for host in hostList:
                   hostFqdn=host.split(':')[0]
                   portNumber=host.split(':')[1]
                   schemaSuffix=host.split(':')[2]
                   f1.write(hostFqdn + ':' + portNumber + ':' + schemaName + '_' + schemaSuffix + '\n')
       return dbHostList
    else:
       schemaName=dbSchema
       dbHostList = ticketNum + '/' + schemaName + ".txt"
       if not os.path.isfile(dbHostList):
            with open (dbHostList, 'a+') as f1:
               for host in hostList:
                   #print('## host')
                   #print(host)
                   hostFqdn=host.split(':')[0]
                   portNumber=host.split(':')[1]
                   f1.write(hostFqdn + ':' + portNumber + ':' + schemaName + '\n')
       return dbHostList

# check sql execution syntax 
def dryrunSql(sql,dbHostList):
            if sql and dbHostList:
                with open (dbHostList, 'r') as f2:
                    hostList = f2.readlines()
                    for host in hostList:
                        count = host.split(':')
                        hostFqdn=host.split(':')[0]
                        portNumber=host.split(':')[1]
                        schemaName=host.split(':')[2]
                        print(hostFqdn, portNumber, schemaName.strip())

                    print('*' * (len(hostFqdn) + len(portNumber) + len(schemaName.strip())))
                    for sqlStatement in sql:
                        print(sqlStatement)
                    print('*' * (len(hostFqdn) + len(portNumber) + len(schemaName.strip())))

# check and execute
def processSql(sql,dbHostList):
        try:
            login = get_dbCredential()
            user = login['user']
            passwd = login['passwd']

            dryrunSql(sql,dbHostList)
            raw_input("\n\nPress ENTER to continue...\n")

            if sql and dbHostList:
                with open (dbHostList, 'r') as f2:
                    hostList = f2.readlines()
                    for host in hostList:
                        hostFqdn=host.split(':')[0]
                        portNumber=host.split(':')[1]
                        schemaName=host.split(':')[2]

                        for sqlStatement in sql:
                            executeSql(user, passwd, sqlStatement, hostFqdn, portNumber, schemaName)
        except KeyboardInterrupt:
            print('\nUser hit Ctl-c !')

# execute sql (under development)  
def executeSql(username, password, sqlStatement, hostFqdn, portNumber, schemaName):
  print('*' * (len(hostFqdn) + 5))
  print(hostFqdn, portNumber,schemaName.strip())

  try:
    conn = MySQLdb.connect(user=username,passwd=password,host=hostFqdn,port=int(portNumber),db=schemaName.strip())
    cur = conn.cursor()
    ##cur.execute(sqlStatement)
    print('> ' + cur._last_executed.strip('\n'))
    print('-' * len(cur._last_executed))
    response = cur.fetchone()
    if response:
       print(response)

 #   response = cur.fetchall()
 #   for resp in response:
 #     print(": ".join(resp))
 #   print('-' * len(cur._last_executed))

  except MySQLdb.Error as e:
    print("Error: %s" % e)
  except BaseException as e:
    print("Error: %s" % e)

def parse_arguments():
    parser = argparse.ArgumentParser()
    req = parser.add_argument_group('Required Parameters:')
    req.add_argument('-t','--ticket', help="Ticket Download options: new, BR-xxx, none", required=True)
    opt = parser.add_argument_group('Optional Parameters:')
    opt.add_argument('-a','--action',default='print', choices=['print','dryrun','execute'])
    opt.add_argument('-l','--link', help="Sql link")
    opt.add_argument('-r','--role', choices=['shard','ticketdb','mono','darwindb'])
    opt.add_argument('-s','--schema', help="Schema name")
    args = parser.parse_args()
    return args

def manage_sql():
    args = parse_arguments()
    ticketNum = (args.ticket).upper()

    if not os.path.exists(ticketNum):
        print('*' * len(ticketNum))
        print(ticketNum)
        print('*' * len(ticketNum))
        download_sql(args)
    else:
        print('#' * len(ticketNum))
        print(ticketNum)
        print('#' * len(ticketNum))

    sql_path=get_sql_path(ticketNum)

    for line in sql_path:
        sql = get_sql(line)
        raw_sql = get_raw_sql(line)
        if sql:
          dbInfo = get_pref_host_link(line)

          if args.action == 'dryrun':
              dbHostFile = prepareHostFile(ticketNum,dbInfo,line)
              dryrunSql(sql, dbHostFile)
          elif args.action == 'execute':
              dbHostFile = prepareHostFile(ticketNum,dbInfo,line)
              processSql(sql, dbHostFile)
          else:
              print(line)
              print('=' * len(line))
              print ('DB Schema Prefix:' + repr(get_db_prefix(line)))
              print('*' * len(line))
              print(repr(raw_sql))
              print('*' * len(line))
        else:
            if args.action == 'print':
                print(line)
    print('\n')

def main():
  try:
    manage_sql()
  except BaseException as e:
    print("Check if the sql ticket exists or sql properly formatted?\nError: %s" % e)

if __name__ == '__main__':
    main()
