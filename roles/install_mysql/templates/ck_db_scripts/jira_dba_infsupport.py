#!/bin/env python
# ###############################################################################
#
# Author : Nived
# Purpose: Create database admin infsupport tickets
# Usage  : python jira_dba_infsupport.py 'Title' 'Description'
#
###############################################################################

import httplib, urllib, json, sys, string

host = 'jira.creditkarma.com'
baseUrl = '/rest/api/2/'
encodeUserData = 'Basic ' + ('ise_issue_creator' + ':' + 'SAK2Zkh1pUpOGcyWWclTGCUf').encode('base64').rstrip()

conn = httplib.HTTPSConnection(host)
headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json;charset=UTF-8',
    'Authorization': encodeUserData,
}

body = json.dumps({ 'fields': {
        'project'        : {
            'key'        : 'INFSUPPORT'
        },
        'summary'        : sys.argv[1],
        'description'    : sys.argv[2],
        'issuetype'      : {
            'name'       : 'Issue'
        },
        'priority'       : {
            'name'       : 'Blocker'
        },
        'customfield_12606' : {
            'value'         : "Yes",
        },
        'customfield_13504' : {
            'value'         : "Yes",
        },
        'customfield_13503' : {
            'id'            : "13442"
        },
    },
})

conn.request('POST', baseUrl + 'issue', headers=headers, body=body)

response = conn.getresponse()

#print response.status, response.reason
#print response.read()
