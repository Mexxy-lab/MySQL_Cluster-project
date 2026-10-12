#!/usr/bin/env python
# A simple script to display CK DBs Host information.

# Import Modules

import MySQLdb
import argparse
import os
import shlex
import subprocess
import re
# import sys
# from os import path
# import os, subprocess
# import pprint
# import mysql.connector


# Variables
env_variable_file = '/usr/local/bin/parameter.txt'

# Functions
def get_args():
    """
    CK Database Node/Host Info Manager - by CreditKarma DBA - Major Umejiofor.
    Function: get_args
        - process argument supplied to this manager.
    """
    # Assign description to the help doc
    parser = argparse.ArgumentParser(usage=__doc__,
        description='CK Database Node/Host Info Manager - by CreditKarma DBA - Major Umejiofor.', formatter_class=argparse.RawDescriptionHelpFormatter, add_help=False)
    # Add arguments
    parser.add_argument(
        '--help', action='help',  default=argparse.SUPPRESS, help=argparse._('show this help message and exit'))
    parser.add_argument(
        '-h', '--host', type=str, help='Hostname or IP of Database host', required=False, default='')
    parser.add_argument(
        '-s', '--service-name', type=str, help='DB or Application Service Name', required=False, default='')
    parser.add_argument(
        '-g', '--group', type=str, help='Group of Database host(s)', required=False, default='')
    parser.add_argument(
        '-r', '--role', type=str, help='Role of Database host(s)', required=False, default='')
    parser.add_argument(
        '-v', '--verbose', help='verbose flag', action='store_true', required=False, default=True)
    parser.add_argument(
        '--dbtype', type=str, help='Database Service Type: [mysql or postgresql]', choices=['mysql', 'postgresql'], required=False, default='mysql')
    parser.add_argument(
        '-i', '--interactive', help='interactive mode - prompts for response', action='store_true', required=False, default=False)
    # Array for all arguments passed to script
    args = parser.parse_args()
    # Assign args to variables
    db_hostname = args.host
    group = args.group
    role = args.role
    interactive = args.interactive
    verbose = args.verbose
    dbtype = args.dbtype
    service_name = args.service_name

    # Return all variable values
    return db_hostname, group, role, verbose, interactive, dbtype,service_name


db_hostname, group, role, verbose, interactive, dbtype, service_name = get_args()
# command = shlex.split("env -i bash -c 'set -a && source " + env_variable_file + " &&  set +a '")
command = shlex.split("env -i bash -c 'set -a && source /usr/local/bin/parameter.txt  &&  env '")
# command = shlex.split("env -i bash -c 'source /usr/local/bin/parameter.txt  &&  env '")
# command = shlex.split("env -i bash -c 'source " + env_variable_file + " &&  env '")
proc = subprocess.Popen(command, stdout=subprocess.PIPE)
for line in proc.stdout:
# for line in subprocess.getoutput(command).split("\n"):
    (key, _, value) = line.partition("=")
    # key, value = line.split("=")
    os.environ[key] = value
proc.communicate()


DB_USER = os.environ['SPLUNK_USER'].strip('\n')
DB_PASS = os.environ['SPLUNK_PASSWD'].strip('\n')



db = MySQLdb.connect(host="{{inventory_hostname}}",  # your host
                     user=DB_USER,                   # username
                     unix_socket='{{ socket  }}',    # DB Socket
                     passwd=DB_PASS,                 # password
                     db="ckadmin")                   # name of the database


# Create a Cursor object to execute queries.
cur = db.cursor()
# Select data from table using SQL query.
cur.execute("SELECT hostName,ipAddress,groupName,dataCenter,instanceName,port,role,isMaster,shardNumber,socket,fqdn,datadir,multiInstance,consulMasterCandidate,consulSlaveCandidate, substring_index(ipAddress, '.', 1) FROM host_info")
# cur.execute("SELECT * FROM host_info")


if 'x' + db_hostname != 'x' and not re.match(r';', db_hostname, re.M | re.I):
    print("DB Host info details - ", db_hostname, ":")
    db_hostname = db_hostname.strip()
    cur.execute("SELECT hostName,ipAddress,groupName,dataCenter,instanceName,port,role,isMaster,shardNumber,socket,fqdn,datadir,multiInstance,consulMasterCandidate,consulSlaveCandidate, substring_index(ipAddress, '.', 1) FROM host_info where ipAddress like " + "'" + db_hostname + "%'")
    for row in cur.fetchall() :
        # print row # , " ", row[1]
        print('Host:'.rjust(22, ' '), row[15])
        print('hostName:'.rjust(22, ' '), row[0])
        print('ipAddress:'.rjust(22, ' '), row[1])
        print('groupName:'.rjust(22, ' '), row[2])
        print('dataCenter:'.rjust(22, ' '), row[3])
        print('instanceName:'.rjust(22, ' '), row[4])
        print('port:'.rjust(22, ' '), row[5])
        print('role:'.rjust(22, ' '), row[6])
        print('isMaster:'.rjust(22, ' '), row[7])
        print('shardNumber:'.rjust(22, ' '), row[8])
        print('socket:'.rjust(22, ' '), row[9])
        print('fqdn:'.rjust(22, ' '), row[10])
        print('datadir:'.rjust(22, ' '), row[11])
        print('multiInstance:'.rjust(22, ' '), row[12])
        print('consulMasterCandidate:'.rjust(22, ' '), row[13])
        print('consulSlaveCandidate:'.rjust(22, ' '), row[14])
        print('\n')

elif 'x' + role != 'x' and not re.match(r';', role, re.M | re.I):
    role = role.strip()
    print("DB Hosts info with Role - ", role, ":")
    cur.execute("SELECT hostName,ipAddress,groupName,dataCenter,instanceName,port,role,isMaster,shardNumber,socket,fqdn,datadir,multiInstance,consulMasterCandidate,consulSlaveCandidate, substring_index(ipAddress, '.', 1) FROM host_info where role like" + "'" + role + "%'")
    count = 0
    for row in cur.fetchall() :
        count = count + 1
        print("Host Count:".rjust(22, ' '), count)
        # print row # , " ", row[1]
        print('Host:'.rjust(22, ' '), row[15])
        print('hostName:'.rjust(22, ' '), row[0])
        print('ipAddress:'.rjust(22, ' '), row[1])
        print('groupName:'.rjust(22, ' '), row[2])
        print('dataCenter:'.rjust(22, ' '), row[3])
        print('instanceName:'.rjust(22, ' '), row[4])
        print('port:'.rjust(22, ' '), row[5])
        print('role:'.rjust(22, ' '), row[6])
        print('isMaster:'.rjust(22, ' '), row[7])
        print('shardNumber:'.rjust(22, ' '), row[8])
        print('socket:'.rjust(22, ' '), row[9])
        print('fqdn:'.rjust(22, ' '), row[10])
        print('datadir:'.rjust(22, ' '), row[11])
        print('multiInstance:'.rjust(22, ' '), row[12])
        print('consulMasterCandidate:'.rjust(22, ' '), row[13])
        print('consulSlaveCandidate:'.rjust(22, ' '), row[14])
        print('\n')

elif 'x' + group != 'x' and not re.match(r';', group, re.M | re.I):
    group = group.strip()
    print("DB Hosts info with groupName - ", group, ":")
    cur.execute("SELECT hostName,ipAddress,groupName,dataCenter,instanceName,port,role,isMaster,shardNumber,socket,fqdn,datadir,multiInstance,consulMasterCandidate,consulSlaveCandidate, substring_index(ipAddress, '.', 1) FROM host_info where groupName like" + "'" + group + "%'")
    count = 0 
    for row in cur.fetchall() :
        count = count + 1
        print("Host Count:".rjust(22, ' '), count)
        # print row # , " ", row[1]
        print('Host:'.rjust(22, ' '), row[15])
        print('hostName:'.rjust(22, ' '), row[0])
        print('ipAddress:'.rjust(22, ' '), row[1])
        print('groupName:'.rjust(22, ' '), row[2])
        print('dataCenter:'.rjust(22, ' '), row[3])
        print('instanceName:'.rjust(22, ' '), row[4])
        print('port:'.rjust(22, ' '), row[5])
        print('role:'.rjust(22, ' '), row[6])
        print('isMaster:'.rjust(22, ' '), row[7])
        print('shardNumber:'.rjust(22, ' '), row[8])
        print('socket:'.rjust(22, ' '), row[9])
        print('fqdn:'.rjust(22, ' '), row[10])
        print('datadir:'.rjust(22, ' '), row[11])
        print('multiInstance:'.rjust(22, ' '), row[12])
        print('consulMasterCandidate:'.rjust(22, ' '), row[13])
        print('consulSlaveCandidate:'.rjust(22, ' '), row[14])
        print('\n')
elif 'x' + service_name != 'x'  and not re.match(r';', service_name, re.M | re.I):
    cur.execute("select distinct role from schema_info where serviceName like '%" + service_name + "%'")
    distinct_roles_array = cur.fetchall()
    count = 0
    for row in distinct_roles_array:
        distinct_role=row[0].strip()
        cur.execute("select distinct s.serviceName, s.schemaName as 'Database',  s.numOfschema, s.role, h.groupName from schema_info s, host_info h  where    s.role = h.role and h.role='" + distinct_role + "' and serviceName like '%" + service_name + "%'")
        for row in cur.fetchall():
            count = count + 1
            print("ServiceName Count:".rjust(22, ' '), count)
            # print row # , " ", row[1]
            print('ServiceName:'.rjust(22, ' '), row[0])
            print('Database:'.rjust(22, ' '), row[1])
            print('Number of Schema:'.rjust(22, ' '), row[2])
            print('Role:'.rjust(22, ' '), row[3])
            print('groupName:'.rjust(22, ' '), row[4])
            print('\n')

db.close()








