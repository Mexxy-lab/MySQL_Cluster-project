#!/bin/bash
# =============================================================================
# {% for line in fileBanner %}
# {{line}} {% endfor %}
# =============================================================================

# This script will log raw on-disk sizes for all datatbase ibd files

# Ensure we have some files to work with, otherwise `xargs du` will list the home directory. Not what we want
COUNT=$(find /db/data -iname '*ibd' | grep -c .)
if [ $COUNT -eq 0 ]; then
  # Nothing to report on, exit cleanly. This is fine; some machines that get this script my be DB servers, but not contain ibd files
  exit 0;
fi

mkdir -p /var/log/dbsize
[ $? -ne 0 ] && echo "Unable to create log directory" && exit 1

TODAY=`date "+%Y-%m-%dT%T%z"`

# Aggregate table sizes to a log file that splunk can pick up and we can analyze later
find /db/data -iname '*ibd' | xargs du | sed "s#/db/data/#$TODAY  #" | awk '{print $2" t="$3" s="$1}' >> /var/log/dbsize/size.log

[ $? -ne 0 ] && echo "Failed to collect stats" && exit 1
