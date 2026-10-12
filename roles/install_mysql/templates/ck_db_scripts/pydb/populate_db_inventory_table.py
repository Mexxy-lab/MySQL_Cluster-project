#!/usr/bin/env python
# A simple script to display CK DBs Host information.

# Import Modules

import MySQLdb
import argparse
import os
import re
import sys
import shlex
import subprocess
from os import path

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
                                     description='CK Database Node/Host Inventory table Manager - by CreditKarma DBA.',
                                     formatter_class=argparse.RawDescriptionHelpFormatter, add_help=False)
    # Add arguments
    parser.add_argument(
        '--file', type=str,
        help='File containing DB inventory details - use csv format:  hostName,ipAddress,groupName,dataCenter,instanceName,port,role,isMaster,shardNumber,socket,fqdn,datadir,multiInstance,consulMasterCandidate,consulSlaveCandidate\n 192.euw2,192.168.56.109,opsdb,euw2,OFFBZIIP1,3306,opsdb,N,1,/db/p/offbzii/v1/admin/OFFBZIIP1/cfg/OFFBZIIP1mysql.sock,192.168.56.109,/db/p/offbzii/v3/table/OFFBZIIP1/,N,1,0',
        required=False, default='db_inventory_info.txt')
    parser.add_argument(
        '--help', action='help', default=argparse.SUPPRESS, help=argparse._('show this help message and exit'))
    parser.add_argument(
        '-h', '--host', type=str, help='Hostname or IP of Opsdb - defaults to opsdb001', required=False,
        default='{{inventory_hostname}}')
    parser.add_argument(
        '-i', '--ipaddress', type=str, help='DB Hostname eg. vdb001.prod.euw2.ckint.io.', required=False, default='')
    parser.add_argument(
        '-g', '--group', type=str, help='Group of Database host(s)', required=False, default='')
    parser.add_argument(
        '-D', '--datacenter', type=str, help='Data Center - eg. defaults to: euw2 ', required=False, default='euw2')
    parser.add_argument(
        '-p', '--partition-name', type=str, help='The [storage] partition name, or the instanceName - eg. vdb',
        required=False, default='')
    parser.add_argument(
        '-P', '--port', type=str, help='Port number of the MySQL DB Service', required=False, default='3306')
    parser.add_argument(
        '-r', '--role', type=str, help='Role of Database host(s)', required=False, default='')
    parser.add_argument(
        '-m', '--is-master', type=str, help='Is this DB host a master node? Values are: Y(for True) or N(for false.)',
        required=False, default='N')
    parser.add_argument(
        '-n', '--shard-number', type=str, help='If this is a sharded DB host, what is the shard number? Default is 0.',
        required=False, default='0')
    parser.add_argument(
        '-s', '--socket', type=str, help='Path to DB socket file', required=False, default='')
    parser.add_argument(
        '-f', '--fqdn', type=str,
        help='Fully qualified domain/host name for the DB. Defaults to the option provided in the -i flag',
        required=False, default='')
    parser.add_argument(
        '-d', '--datadir', type=str, help='Path to DB data directory', required=False, default='')
    parser.add_argument(
        '-M', '--multi-instance', type=str,
        help='Is this host going to have multiple MySQL services? Defaults to N. Y=True, N=False.', required=False,
        default='N')
    parser.add_argument(
        '-v', '--verbose', help='verbose flag', action='store_true', required=False, default=True)
    parser.add_argument(
        '--dbtype', type=str, help='Database Service Type: [mysql or postgresql]', choices=['mysql', 'postgresql'],
        required=False, default='mysql')
    parser.add_argument(
        '-I', '--interactive', help='interactive mode - prompts for response', action='store_true', required=False,
        default=False)
    parser.add_argument(
        '-c', '--is-consul-master-candidate', type=str,
        help='Is this node to be marked as a Master DB in consul? Default value is 0. 1=True, 0=False', required=False,
        default='0')
    parser.add_argument(
        '-C', '--is-consul-slave-candidate', type=str,
        help='Is this node to be marked as a Slave DB in consul? Default value is 0. 1=True, 0=False', required=False,
        default='0')
    # Array for all arguments passed to script
    args = parser.parse_args()
    # Assign args to variables
    file = args.file
    opsdb = args.host
    interactive = args.interactive
    verbose = args.verbose
    dbtype = args.dbtype
    ip_address = args.ipaddress
    group_name = args.group
    data_center = args.datacenter
    instance_name = args.partition_name
    port = args.port
    role = args.role
    is_master = args.is_master
    shard_number = args.shard_number
    socket = args.socket
    fqdn = args.fqdn
    datadir = args.datadir
    multi_instance = args.multi_instance
    consul_master_candidate = args.is_consul_master_candidate
    consul_slave_candidate = args.is_consul_slave_candidate

    # Return all variable values
    return dbtype, verbose, interactive, file, opsdb, ip_address, group_name, data_center, instance_name, port, role, is_master, shard_number, socket, fqdn, datadir, multi_instance, consul_master_candidate, consul_slave_candidate


def split_db_entry_info_into_list(db_host_info):
    db_host_info = db_host_info.strip()
    db_host_info = db_host_info.replace(" ", "")
    array_list = db_host_info.split(",")
    return array_list


dbtype, verbose, interactive, file, opsdb, ip_address, group_name, data_center, instance_name, port, role, is_master, shard_number, socket, fqdn, datadir, multi_instance, consul_master_candidate, consul_slave_candidate = get_args()

ck_opsdb = '{{ck_opsdb_ipaddress_or_hostname}}'
if ck_opsdb:
    opsdb = ck_opsdb

command = shlex.split("env -i bash -c 'set -a && source /usr/local/bin/parameter.txt  &&  env '")
proc = subprocess.Popen(command, stdout=subprocess.PIPE)
for line in proc.stdout:
    # for line in subprocess.getoutput(command).split("\n"):
    (key, _, value) = line.partition("=")
    # key, value = line.split("=")
    os.environ[key] = value
proc.communicate()

DB_USER = os.environ['USER'].strip('\n')
DB_PASS = os.environ['PASSWD'].strip('\n')


def connect_to_mysql_and_execute_query(query, data='', is_select=True, db_host=opsdb, user=DB_USER, passwd=DB_PASS,
                                       db="ckadmin"):
    try:

        db = MySQLdb.connect(host=db_host,  # your host
                             user=user,  # username
                             unix_socket='{{ socket  }}',  # DB Socket
                             passwd=passwd,  # password
                             db=db)  # name of the database
        # Create a Cursor object to execute queries.
        cursor = db.cursor()
        cursor.execute(query, data)
        if is_select:
            list_returned = cursor.fetchall()
        else:
            db.commit()
    except MySQLdb.Error as e:
        print("Error %d: %s" % (e.args[0], e.args[1]))
        sys.exit(1)
    finally:
        if db:
           db.close()
    if is_select:
        return list_returned

if path.exists(file):
    text_file = open(file, "r")
    lines = text_file.read().split('\n')
    text_file.close()

if path.exists(file):
    text_file = open(file, "r")
    lines = text_file.read().split('\n')
    text_file.close()

    for line in lines:
        line = line.strip()
        if line == '':
            continue
        if re.match('^#', line, re.M | re.I):
            continue
        # ipAddress,datacenter, ipAddress,groupName,dataCenter,instanceName,port,role,isMaster,shardNumber,socket,fqdn,datadir,multiInstance,consulMasterCandidate,consulSlaveCandidate'
        dummy_db_hostname, ip_address, group_name, data_center, instance_name, port, role, is_master, shard_number, socket, fqdn, datadir, multi_instance, consul_master_candidate, consul_slave_candidate = split_db_entry_info_into_list(
            line)

        #select_query = "SELECT hostName,ipAddress,groupName,dataCenter,instanceName,port,role,isMaster,shardNumber,socket,fqdn,datadir,multiInstance,consulMasterCandidate,consulSlaveCandidate, substring_index(ipAddress, '.', 1) FROM host_info where substring_index(ipAddress, '.', 1) = " + "'" + ip_address.split('.')[0] + "'"

        select_query = "SELECT hostName,ipAddress,groupName,dataCenter,instanceName,port,role,isMaster,shardNumber,socket,fqdn,datadir,multiInstance,consulMasterCandidate,consulSlaveCandidate, substring_index(ipAddress, '.', 1) FROM host_info where ipAddress = " + "'" + \
                       ip_address.strip() + "'"

        array_returned = connect_to_mysql_and_execute_query(select_query)
        count = 0
        for row in array_returned:
            # if row[1].split('.')[0].strip() == ip_address.split('.')[0] and row[5] == port.strip():
            # if (str(row[1].split('.')[0]).strip() == str(ip_address.split('.')[0]).strip())  and (str(row[5]).strip() == str(port).strip() ):
            if (str(row[1]).strip() == str(ip_address).strip()) and (str(row[5]).strip() == str(port).strip()):
                count = count + 1
                print("Entry for host: [ ", ip_address.strip(), " ] already exists in opsdb: [ " + opsdb + " ]!")
                print("Host Count:".rjust(22, ' '), count)
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
                break

        if count > 0:
            continue
        else:
            insert_into = "Insert into host_info (hostName, ipAddress, groupName, dataCenter, instanceName, port, role, isMaster, shardNumber, socket, fqdn, datadir,multiInstance, consulMasterCandidate, consulSlaveCandidate) values (%s, %s, %s, %s,%s, %s,%s, %s,%s, %s,%s, %s,%s, %s, %s )"

            if fqdn == '':
                fqdn = ip_address
            if multi_instance == '':
                multi_instance = 'N'
            if consul_master_candidate == '':
                consul_master_candidate = 'N'
            if consul_slave_candidate == '':
                consul_slave_candidate = 'N'
            if is_master == '':
                is_master = 'N'
            if data_center == '':
                data_center = 'euw2'

            # db_hostname = ip_address.split('.')[0].strip() + '.' + str(data_center)
            db_hostname = ip_address.strip() + '.' + str(data_center)
            data = (
                db_hostname, ip_address, group_name, data_center, instance_name, port, role, is_master, shard_number,
                socket, fqdn, datadir, multi_instance, consul_master_candidate, consul_slave_candidate)
            full_insert_statement = (insert_into, data)
            print("full_insert_statement ===> ", insert_into, data)
            connect_to_mysql_and_execute_query(insert_into, data, False)







