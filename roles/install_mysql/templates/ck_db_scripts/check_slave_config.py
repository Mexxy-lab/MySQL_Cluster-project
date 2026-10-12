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
# Purpose: Multi-purpose script for remote MySQL monitoring
# Usage:   Run with --help.
#
###############################################################################

from __future__ import print_function
import os,re,sys,time,threading,MySQLdb,logging,Queue,argparse

# Custom python modules for MySQL and system calls

sys.path.append("/usr/local/ops/bin/pydb")

from opsdb_host_info import parameter,dc_domain,slack_hook,opsdb,host_info,mysql_fail,global_variable,slave_status

def slave_hosts(dbcnx):

  cursor = dbcnx.cursor()
  query = ("show slave hosts")
  try:
    cursor.execute(query)
  except MySQLdb.Error as error:
    print("MySQL Error: %s" % str(error))
    cursor.close()
    raise
  else:
    s_hosts = cursor.fetchall()
    return(len(s_hosts))
    cursor.close()

def process_args():

  parser = argparse.ArgumentParser(description='Check for slave hosts and port matching')
  parser.add_argument("-m", "--mode", choices=['slaves','ports'], nargs=1, required=True)
  parser.add_argument("-v", "--verbose", action='store_true', required=False)

  args = parser.parse_args()

  return args

def main():

  state = 0

  args = process_args()

  if dc_domain() == 'prod.iad1.ckint.io':
    dc = 'cke'
  elif dc_domain() in ('prod.sjc1.ckint.io','sjc1.creditkarma.com'):
    dc = 'ckw'
  else:
    logging.critical("Invalid Domain - %s" % dc_domain)
    sys.exit(1)

  if args.mode[0] == 'ports':

    opsdbcursor = opsdb().cursor()

    opsdbcursor.execute("select h.fqdn,h.port from db_monitor_info d join host_info h on d.hostId=h.hostId \
                         where master_slave_port_match=1 and h.datacenter='%s' order by h.fqdn" % dc)

    output = opsdbcursor.fetchall()

    for (output) in output:
      instanceconnect = {
      'user': parameter()[0],
      'passwd': parameter()[1],
      'host': output[0],
      'port': int(output[1]),
      'db': 'information_schema',
      'use_unicode': True
      }

      try:
        cnx = MySQLdb.connect(**instanceconnect)
      except MySQLdb.Error as err:
        logging.error("{0}:{1} - {2}".format(output[0],output[1],err))
        state = 1
      else:
        localport = global_variable(cnx,'port')
        masterport = slave_status(cnx,3)

        if masterport is not None and int(localport) != int(masterport) and re.sub('\.[\.\w]+$','',output[0]) != 'budb009':
          state = 1
          print("Failed: Port on slave %s:%s <> port on master - %s" % (output[0],localport,masterport))
        else:
          if masterport is None:
            if args.verbose:
              print("OK: %s:%s - Master or Standalone database" % (output[0],output[1]))
          elif int(localport) == int(masterport):
            if args.verbose:
              print("OK: %s:%s - Slave and Master ports match: %s == %s" % (output[0],output[1],localport,masterport))
          else:
            if args.verbose:
              print("OK: Expected slave-master port mismatch: %s %s <> %s" % (output[0],localport,masterport))

        opsdbcursor.close()
        opsdb().close()
        cnx.close()

  elif args.mode[0] == 'slaves':

    opsdbcursor = opsdb().cursor()

    opsdbcursor.execute("select h.fqdn,h.port from db_monitor_info d join host_info h on d.hostId=h.hostId \
                         where number_of_slaves=1 and h.datacenter='%s' and h.role='shard' order by h.fqdn" % dc)

    output = opsdbcursor.fetchall()

    for (output) in output:
      instanceconnect = {
      'user': parameter()[0],
      'passwd': parameter()[1],
      'host': output[0],
      'port': int(output[1]),
      'db': 'information_schema',
      'use_unicode': True
      }

      try:
        cnx = MySQLdb.connect(**instanceconnect)
      except MySQLdb.Error as err:
        logging.error("{0}:{1} - {2}".format(output[0],output[1],err))
        state = 1
      else:
        if global_variable(cnx,'read_only') == 'OFF' and slave_hosts(cnx) > 2:
          state = 1
          print("Failed: %s:%s:%s RW master has too many active slaves - %s" % (output[0],output[1],global_variable(cnx,'read_only'),slave_hosts(cnx)))
        else:
          if args.verbose:
            print("OK: %s:%s:%s - Number of slaves: %s" % (output[0],output[1],global_variable(cnx,'read_only'),slave_hosts(cnx)))

        opsdbcursor.close()
        opsdb().close()
        cnx.close()

  if state != 0:
    print('------')
    print("Failed")
    sys.exit(2)
  else:
    print('--')
    print("OK")
    sys.exit(0)

if __name__ == '__main__':
  main()
