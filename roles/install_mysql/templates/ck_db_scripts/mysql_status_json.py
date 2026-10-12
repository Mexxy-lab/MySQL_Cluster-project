#!/usr/bin/python
# =============================================================================
# {% for line in fileBanner %}
# {{line}} {% endfor %}
# =============================================================================
"""
Process mysql global status into json for splunk consumption

Expect input as

    mysql -uUSERNAME -pPASSWORD -A --batch --skip-column-names -e 'show global status' | python this.py

Will then parse the global status and dump it in two chunks as timestamped json lines. A single line
is too long (>10000 characters) for splunk to ingest by default. This fixes that, but does require
`transaction`ing if you wish to combine events later on.
"""

import json
import collections
import datetime
import fileinput

# Create our data bucket with initial timestamp
vals = collections.OrderedDict()

# load to databucket
for line in fileinput.input():
    (v1, v2) = line.split("\t")
    vals[v1.lower()] = v2.strip()

# This data element is toooo long, split it in twine
vals1 = collections.OrderedDict()
vals2 = collections.OrderedDict()
# use the same timestamp for both lines so that we can `transaction` them back together later
ts = datetime.datetime.utcnow().isoformat("T") + "Z"
vals1['ts'] = ts
vals2['ts'] = ts
d1 = dict(vals.items()[len(vals)//2:])
d2 = dict(vals.items()[:len(vals)//2])
vals1.update(d1)
vals2.update(d2)

# Dump out the JSON
print json.dumps(vals1)
print json.dumps(vals2)
