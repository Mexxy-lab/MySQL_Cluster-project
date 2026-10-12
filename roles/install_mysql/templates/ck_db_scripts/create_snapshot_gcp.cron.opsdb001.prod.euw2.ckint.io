# Non-shards
5 */3 * * * root /usr/local/ops/bin/create_snapshot_gcp.sh -d euw2 -h bkpservicedb001,bkpdarwindb001,bkpgrafanadb001,bkpadmaxdb001 2>&1 > /tmp/create_snapshot_gcp.out
# Shards
0 */3 * * * root /usr/local/ops/bin/create_snapshot_gcp.sh -d euw2 -g budb 2>&1 > /tmp/create_snapshot_gcp.out

#-- Vault ---------------------------------------------------------------------

# Vault Non Shards
5 */3 * * * root /usr/local/ops/bin/create_snapshot_gcp.sh -d euw2 -h bkpvdb001,bkpvpdb001 2>&1 > /tmp/create_snapshot_gcp.out

# Vault Shards
5 */3 * * * root /usr/local/ops/bin/create_snapshot_gcp.sh -d euw2 -g vbudb 2>&1 > /tmp/create_snapshot_gcp.out
