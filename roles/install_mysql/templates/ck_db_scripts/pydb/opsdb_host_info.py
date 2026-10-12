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
# Purpose: Python function library for OPSDB scripts
# Usage:   Run with --help.
#
###############################################################################

from __future__ import print_function
import os, re, sys, getpass, subprocess, logging, smtplib, socket, signal
import MySQLdb
import urllib2
import json
import socket


def check_for_cpids(cmd):
    output = []
    cmdline = cmd.split('/')
    cmd = cmdline[-1]
    cpid = subprocess.Popen(['/usr/bin/pgrep', '-f', '%s' % cmd], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = cpid.communicate()
    cpid.wait()
    output = out[0].split("\n")
    output = ([int(i) for i in output if i != None and i.isdigit()])
    output.remove(os.getpid())
    return output


def sigint_handler(signal, frame):
    print('<Interrupted>')
    sys.exit(0)


def local_mysql_fail(error):
    logging.error("MySQL Error: %s" % str(error))


def mysql_fail(error, hostnport):
    logging.error("MySQL Error %s:%s: %s" % (hostnport[0], hostnport[1], str(error)))


def slack_hook(send_status, stmts=[]):
    if send_status == 0:
        send_email_alert(parameter()[2], '%s executed' % os.getlogin(),
                         re.sub(r'^/.*/', '', sys.argv[0]) + ' ' + ' '.join(i for i in sys.argv[1:]) + '\n' + '\n'.join(
                             i for i in stmts))
        send_status = 1


def dc_domain():
    return re.sub('^[\w]+.', '', socket.gethostname())


def send_email_alert_bckup(receiver, subject, emailtext):
    sender = '%s' % getpass.getuser() + '@' + '%s' % socket.getfqdn()

    message = """From: %s
To: %s
Subject: %s
%s
""" % (sender, receiver, subject, emailtext)
    try:
        smtpObj = smtplib.SMTP('localhost')
        smtpObj.sendmail(sender, receiver, message)
    except SMTPException:
        print("Error: Unable to send email")


def parameter():
    file = open('/usr/local/ops/bin/parameter.txt', 'rU')
    dbusername, dbpasswd, uk_slack_webhook, alertsemail, pdmail = (None, None, None, None, None)

    for line in file:
        col1 = line.strip().split('=')[0]
        if col1 == 'USER':
            col2 = line.strip().split('=')[1]
            dbusername = col2.strip('"')
        if col1 == 'PASSWD':
            col2 = line.strip().split('=')[1]
            dbpasswd = col2.strip('"')
        if col1 == 'UK_SLACK_WEBHOOK':
            col2 = line.strip().split('=')[1]
            uk_slack_webhook = col2.strip('"')
        if col1 == 'ALERTSMAILID':
            col2 = line.strip().split('=')[1]
            alertsemail = col2.strip('"')
        if col1 == 'PDMAILID':
            col2 = line.strip().split('=')[1]
            pdmail = col2.strip('"')

    file.close()

    return dbusername, dbpasswd, uk_slack_webhook, alertsemail, pdmail


def send_email_alert(slack_webhook_link, subject, emailtext):
    host = socket.gethostname()
    shell_user = os.getlogin()
    slack_webhook_link = slack_webhook_link.strip("'")
    db_notification_channel = '#uk-db-jobs-notifications'
    post = {'channel': db_notification_channel,
            'username': ' ' + str(host) + ' - ' + str(subject),
            'text': '` *[' + str(shell_user) + ']* executed Script: ` \n\n\n ' + str(emailtext) + '.',
            'icon_emoji': ':ghost:'}

    json_data = json.dumps(post)
    req = urllib2.Request(slack_webhook_link,
                          json_data.encode('ascii'),
                          {'Content-Type': 'application/json'})
    resp = urllib2.urlopen(req)


def opsdb():
    username = parameter()[0]
    password = parameter()[1]

    dblocal = {
        'user': username.strip("'"),
        'passwd': password.strip("'"),
        'host': '{{inventory_hostname}}',
        'db': 'ckadmin',
        'use_unicode': True
    }
    try:
        ckadmincnx = MySQLdb.connect(host=dblocal['host'],  # your host
                                     user=dblocal['user'],  # username
                                     unix_socket='{{ socket  }}',  # DB Socket
                                     passwd=dblocal['passwd'],  # password
                                     db=dblocal['db'])  # name of the database
    except MySQLdb.Error as err:
        print("MySQL Error: %s" % str(err))
        sys.exit(1)
    else:
        ckadmincnx.autocommit(True)
    return ckadmincnx


def max_instance_number(dc, group):
    opsdbcnx = opsdb()
    opsdbcursor = opsdbcnx.cursor()

    query = ("select max(shardNumber) from host_info where dataCenter = '%s' and groupName = '%s'" % (dc, group))
    opsdbcursor.execute(query)

    output = opsdbcursor.fetchone()

    if output[0] is None:
        print("No shards were found for group %s at %s" % (group, dc))
        sys.exit(1)
    else:
        max_instance = int(output[0])

    opsdbcursor.close()
    opsdbcnx.close()

    return max_instance


def shard_groups():
    s_groups = []

    opsdbcnx = opsdb()
    opsdbcursor = opsdbcnx.cursor()

    query = ("select distinct(groupName) from host_info where shardNumber>0")
    opsdbcursor.execute(query)

    output = opsdbcursor.fetchall()

    for (output) in opsdbcursor:
        s_groups.append(str(output[0]))

    opsdbcursor.close()
    opsdbcnx.close()

    return s_groups


def shard_schemas():
    s_schemas = []

    opsdbcnx = opsdb()
    opsdbcursor = opsdbcnx.cursor()

    query = ("select distinct schemaName from schema_info where isSharded='Y'")
    opsdbcursor.execute(query)

    output = opsdbcursor.fetchall()

    for (output) in opsdbcursor:
        s_schemas.append(str(output[0]))

    opsdbcursor.close()
    opsdbcnx.close()

    return s_schemas


def host_info(hostname, shard='', interactive='N'):
    def quit_host_info():
        raise Exception("Critical: Unable to validate Host/Port(s) - %s" % hostname)
        opsdbcursor.close()
        opsdbcnx.close()

    opsdbcnx = opsdb()
    opsdbcursor = opsdbcnx.cursor()

    hostandport = re.search('(^[\w.]+):([\d,-]+$)', hostname)

    if hostandport:
        hostname = hostandport.group(1)
        if re.search(',', hostandport.group(2)) or hostandport.group(2).isdigit():
            dbports = hostandport.group(2).split(',')
        else:
            portrange = re.search('([\d]+)-([\d]+)', hostandport.group(2))
            if portrange and (int(portrange.group(1)) < int(portrange.group(2))):
                dbports = range(int(portrange.group(1)), int(portrange.group(2)) + 1)
            else:
                quit_host_info()

        dbports = [int(i) for i in dbports]
        portlist = []
        for i in dbports:
            query = ("select count(1) from host_info where port in (%d) and fqdn='%s' and role like '%%%s%%'" % (
                i, hostname, shard))
            opsdbcursor.execute(query)
            port_match = opsdbcursor.fetchone()

            if int(port_match[0]) == 0:
                print("Port %s is invalid: " % i)
                pass
            else:
                portlist.append(i)

    query = ("select count(*) from host_info where fqdn = '%s' and role like '%%%s%%'" % (hostname, shard))
    opsdbcursor.execute(query)

    host_match = opsdbcursor.fetchone()

    if int(host_match[0]) == 0:
        quit_host_info()
    else:
        try:
            dbports = portlist
        except:
            dbports = []
            query = ("select port from host_info where fqdn = '%s' and role like '%%%s%%' order by 1" % (
                hostname, shard))
            opsdbcursor.execute(query)
            for port in opsdbcursor:
                dbports.append(int(port[0]))

    if len(dbports) == 0:
        quit_host_info()
    else:
        if interactive == 'Y' and len(dbports) > 1:
            print("Available Ports: ")
            for i in dbports:
                print("\t\t", i)

            print("Press 'Enter\' for all ports or any non-numeric key to quit")
            iports = raw_input("Ports: (e.g. 3306|3311,..|3301-..) ")

            signal.signal(signal.SIGINT, sigint_handler)

            if len(iports) > 0:
                if iports == '0' or not re.search('([\d,-]+)', iports):
                    sys.exit(0)
                elif re.search(',', iports) or iports.isdigit():
                    iports = iports.split(',')
                elif re.search('([\d]+)-([\d]+)', iports):
                    portrange = re.search('([\d]+)-([\d]+)', iports)
                    if (int(portrange.group(1)) < int(portrange.group(2))):
                        iports = range(int(portrange.group(1)), int(portrange.group(2)) + 1)
                    else:
                        quit_host_info()
                try:
                    iports = [int(i) for i in iports]
                except ValueError:
                    quit_host_info()

                if set(iports) < set(dbports):
                    dbports = iports
                else:
                    signal.signal(signal.SIGINT, sigint_handler)
                    quit_host_info()

        opsdbcursor.close()
        opsdbcnx.close()

        return dbports


def slave_status(dbcnx, position):
    cursor = dbcnx.cursor()
    query = ("show slave status")
    try:
        cursor.execute(query)
    except MySQLdb.Error as err:
        connect_fail(err)
    else:
        for (output) in cursor:
            return output[position]


def global_variable(dbcnx, vname):
    vvalue = 'None'
    cursor = dbcnx.cursor()
    query = ("select variable_value from global_variables where variable_name='%s'" % vname)
    try:
        cursor.execute(query)
    except MySQLdb.Error as err:
        local_mysql_fail(err)
    else:
        output = cursor.fetchone()
        for (output) in cursor:
            vvalue = output[0]
    cursor.close()
    return vvalue


def global_status(dbcnx, vname):
    vvalue = 'None'
    cursor = dbcnx.cursor()
    query = ("select variable_value from global_status where variable_name='%s'" % vname)
    try:
        cursor.execute(query)
    except MySQLdb.Error as err:
        local_mysql_fail(err)
    else:
        output = cursor.fetchone()
        for (output) in cursor:
            vvalue = output[0]
    cursor.close()
    return vvalue


def show_db(dbcnx, dname):
    rowlist = []
    cursor = dbcnx.cursor()
    try:
        cursor.execute("show databases like '%s_____'" % dname)
    except MySQLdb.Error as err:
        local_mysql_fail(err)
    else:
        output = cursor.fetchall()
        for (output) in cursor:
            rowlist.append(output[0])
    cursor.close()
    return rowlist


def find_table(dbcnx, tabname):
    cursor = dbcnx.cursor()
    tables_found = []
    if len(tabname.split('.')) == 1:
        cursor.execute("select distinct table_schema from tables")
        dblist = []
        dbtab = tabname
        for (output) in cursor:
            for i in output:
                dblist.append(i)
    else:
        dblist = [tabname.split('.')[0]]
        if dblist[0] not in show_db(dbcnx, dblist[0]):
            raise Exception("Database %s not found" % dblist[0])
        else:
            dbtab = tabname.split('.')[1]
    for db in dblist:
        cursor.execute("show tables in %s like '%%%s%%'" % (db, dbtab))
        for (output) in cursor:
            tables_found.append("%s.%s" % (db, output[0]))
    return tables_found


def processlist(dbcnx, username, runtime=0, kill='N'):
    cursor = dbcnx.cursor()
    query = ("show full processlist")
    proclist = []

    try:
        cursor.execute(query)
    except MySQLdb.Error as err:
        local_mysql_fail(err)
    else:
        output = cursor.fetchall()
        print('----------')
        for (output) in cursor:
            if (len(username) == 0 or re.search(username, output[1])) and output[1] != 'system user' \
                    and output[7] != 'show full processlist' and output[5] != 'NULL' and output[5] > runtime:

                proclist.append(int(output[0]))
                printline = []

                for i in output:
                    printline.append(i)
                for i in printline:
                    print(i, end="|")
                print()

        if len(proclist) > 0 and kill == 'Y':
            for i in proclist:
                print('---------------------------------------------')
                pkill = raw_input("\'K\' to kill or any other key to skip %d: " % i)
                if pkill.lower() == 'k':
                    cursor.execute('kill %d' % int(i))

    cursor.close()
    dbcnx.close()


def query(dbcnx, query, closecnx='N'):
    cursor = dbcnx.cursor()
    try:
        cursor.execute(query)
        output = cursor.fetchall()
    except MySQLdb.Error as err:
        local_mysql_fail(err)
    else:
        for (output) in cursor:
            printline = []
            for i in output:
                printline.append(i)
            for i in printline:
                print(i, end="|")
            print()
        print()
        if closecnx == 'Y':
            dbcnx.close()


def exec_script(dbcnx, scriptName):
    if os.path.isfile(scriptName) and os.access(scriptName, os.R_OK):
        script = open(scriptName, 'rU')
    else:
        print("Script cannot be found/accessed")
        sys.exit(1)
    statements = re.findall(r'.+?;\s', script.read().replace('\n', ' '))

    for stmt in statements:
        query(dbcnx, stmt.strip(';\ '))

    script.close()
    dbcnx.commit()
    dbcnx.close()
