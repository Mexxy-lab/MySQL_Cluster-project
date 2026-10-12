#!/usr/bin/python
#October 4,2016
#anodotqps v 0.1 by Yevgeniy Gorbatenko
#usage: anodotqps.py hostname port
#
#
import sys,getopt
import re
import requests
import json
import mmap
import MySQLdb
import MySQLdb.cursors
import datetime
from datetime import time, timedelta
import time
from warnings import filterwarnings
from warnings import resetwarnings


class datagrab:
     def __init__(self,schema,targethost, targetport):
          self.pattern1= re.compile("^USER=")
          self.pattern2= re.compile("^PASSWD=")

          for self.line in open('/usr/local/ops/bin/parameter.txt'):
          	    for self.match in re.finditer(self.pattern1,self.line):
          	        self.user = self.line.replace(self.match.group(0),'')
          	        self.user = self.user.replace('"','')
          	        self.user = self.user.rstrip('\n')
          	    for self.match2 in re.finditer(self.pattern2,self.line):
          	        self.passwd = self.line.replace(self.match2.group(0),'')
          	        self.passwd = self.passwd.replace('"','')
          	        self.passwd = self.passwd.rstrip('\n')

          self.host = str(targethost)
          self.port = targetport
          filterwarnings('ignore', category = MySQLdb.Warning)
          def makedbconnection():
              return MySQLdb.connect(host=self.host,port=self.port,user=self.user,passwd=self.passwd,db="information_schema")

          def queryresult(connection,query):
              queryresultcursor=connection.cursor()
              queryresultcursor.execute(query)
              return queryresultcursor.fetchall()

          self.connection=makedbconnection()
          self.query = 'show global status like "Queries"'
          self.dboutput = queryresult(self.connection,self.query)

          self.connection.close()

     def averageovertime(self,value1,value2,timeperiod):
         return (int(value2)-int(value1))/int(timeperiod)


class payload:
    def __init__(self):
        self.schemaName = "Metrics.json"
        self.version = "dfae8dbc005527603e874f76ef9d61c6"
        self.ts = str(datetime.datetime.utcnow().isoformat()) + "+00:00"
        self.tsEvent = str(datetime.datetime.utcnow().isoformat()) + "+00:00"
        self.traceId = "FAKEUUID-FAKE-UUID-FAKE-FAKEUUID7676"
        self.baseSystemName = "opsdbaqps"
        self.dimensions = '{ "metrichosttype" : "mysql", "metric" : "qps" }'
        self.value = '5.0'
        self.source = str(sys.argv[1])
        # min,max,sum,average,upper90
        self.aggregationMethod = "upper90"
        self.currentpayload = '{ "events": [{ "schemaName" : "' + self.schemaName + '", "version": "' + self.version + '", "ts": "' + self.ts + '", "tsEvent": "' + self.tsEvent +  '", "traceId": "' + self.traceId + '", "baseSystemName": "' + self.baseSystemName + '", "dimensions": ' + self.dimensions + ', "value": ' + self.value + ', "source": "' + self.source + '", "aggregationMethod": "' + self.aggregationMethod + '" }]}'
    def updatepayload(self):
        self.currentpayload = '{ "events": [{ "schemaName" : "' + self.schemaName + '", "version": "' + self.version + '", "ts": "' + self.ts + '", "tsEvent": "' + self.tsEvent +  '", "traceId": "' + self.traceId + '", "baseSystemName": "' + self.baseSystemName + '", "dimensions": ' + self.dimensions + ', "value": ' + self.value + ', "source": "' + self.source + '", "aggregationMethod": "' + self.aggregationMethod + '" }]}'

# all starts here
if __name__== '__main__':
    ourtargethost = str(sys.argv[1])
    ourtargetport = int(sys.argv[2])
    sleepvalue = 60
    datagrab1 = datagrab('information_schema',ourtargethost,ourtargetport)
    datagrab1.dboutputlist = list( row[1] for row in datagrab1.dboutput)
    time.sleep(sleepvalue)
    datagrab2 = datagrab('information_schema',ourtargethost,ourtargetport)
    datagrab2.dboutputlist = list( row[1] for row in datagrab2.dboutput)
#    oururl = 'https://sponge-vip1.sjc1.creditkarma.com/events'
#    oururl = 'https://sponge.prod.iad1.ckint.io/events'
    oururl = 'https://oddity.prod.iad1.ckint.io/events'

    ourheaders = {'Content-type': 'application/json','Accept': '*/*'}
    targetpayload = payload()
    targetpayload.value = str(datagrab1.averageovertime(datagrab1.dboutputlist[0] , datagrab2.dboutputlist[0] , sleepvalue)) + '.0'
    targetpayload.baseSystemName = "iedbaqps"
    targetpayload.dimensions = '{ "host" : "' + str(sys.argv[1]).translate(None,'.') + ":" + str(sys.argv[2]) + '", "type" : "' + str(sys.argv[1])[:5] +'" }'
    targetpayload.updatepayload()
#    print targetpayload.currentpayload
    ro = requests.post (oururl, data=targetpayload.currentpayload,headers=ourheaders)
#    print ro.text


