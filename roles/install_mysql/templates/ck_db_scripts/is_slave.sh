#!/bin/bash
# =============================================================================
# {% for line in fileBanner %}
# {{line}} {% endfor %}
# =============================================================================

# Determine if the given mysqld is configured as a slave

# fail on unset vars and errors
set -u
set -e

# Which check do we want?
if [ -z "$1" -o "$1" == "" ]; then
    echo "CRIT Not configured correctly, use 'true' or 'false' arg"
    exit 3
fi
if [ "$1" == "true" -o "$1" == "false" ]; then
    # all good
    a=1
else
    echo "CRIT Not configured correctly, use 'true' or 'false' arg"
    exit 3
fi

# Count the number of lines in the slave status output
COUNT=$(mysql -S ${SOCKET} -u ${USER} -p${PASS} -e 'SHOW SLAVE STATUS \G' 2>/dev/null | wc -l)

# If there are no lines, this is not setup as a slave at all, crit out -- otherwise we good
if [ $COUNT -eq 0 ]; then
    # The instance is NOT configured to be a slave
    if [ "$1" == "true" ]; then
        echo 'CRIT Is not a slave and should be'
        exit 3
    else
        echo 'OK Is not a slave'
        exit 0
    fi
else
    # The instance IS configured to be a slave
    if [ "$1" == "true" ]; then
        echo 'OK Is a slave'
        exit 0
    else
        echo 'CRIT Is a slave and should not be'
        exit 3
    fi
fi
