#!/bin/bash
# =============================================================================
# {% for line in fileBanner %}
# {{line}} {% endfor %}
# =============================================================================

# Grabs all the mysql status values and tosses out a nice json log line(s) for splunk to collect up

{% for dbid, info in pillar.get('database', {}).iteritems() %}

mysql -u'{{ info.username }}' -p'{{ info.password }}' --socket={{ info.socket }} \
 -A --batch --skip-column-names -e 'show global status;' \
 | python /usr/local/ops/bin/mysql_status_json.py \
 >> /var/log/mysql/global-status-{{ dbid }}.log

{% endfor %}
