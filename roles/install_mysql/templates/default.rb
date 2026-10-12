#------------------
# cookbook settings
#------------------
default["ou"]["org: "non-hpcc"

default["mysql"]["variant: "Percona"
default["mysql"]["major_version: "5.7"
default["mysql"]["replace: "N"

default["global"]["db"]["template: "db.std.mysql.cnf.erb"
default["global"]["db"]["overwrite: "N"

default["rpm: nil

#----------------
# mysqld Settings
#----------------
basedir: "/usr"    

#---------------
# Basic Settings
#---------------
server_id: 1
port: 3306

bind_address: "0.0.0.0"
character_set: "utf8"
collation: "utf8_unicode_ci"
connect_timeout: 10
language: "/usr/share/mysql/english"
old_passwords: 0
skip_external_locking: true
skip_name_resolve: false
skip_networking: false
wait_timeout: 28800

#--------------------------------------------------
# SSL settings
#--------------------------------------------------
# ssl_cipher:"RC4-SHA:AES128-SHA:CDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA"
ssl_cipher:"ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256"

#------------
# Fine Tuning
#------------
back_log: 50
bulk_insert_buffer_size: "32M"
expand_fast_index_creation: false
explicit_defaults_for_timestamp: 1
group_concat_max_len: 4096
join_buffer_size: "8M"
key_buffer: "32M"
lower_case_table_names: 1
max_allowed_packet: "512M"
max_connect_errors: 100000
max_connections: 2000
max_heap_table_size: "64M"
max_sp_recursion_depth: 50
memlock: false
open_files_limit: 16384
port_open_timeout: 5
query_alloc_block_size: "16K"
read_buffer_size: "1M"
read_rnd_buffer_size: "10M"
sort_buffer_size: "2M"
sql_modes: ["TRADITIONAL"]
table_cache: 1024
thread_cache_size: 8
thread_stack: "192K"
tmp_table_size: "64M"
transaction_isolation: "READ-COMMITTED"
binlog_gtid_simple_recovery: 1

#--------------------------
# Query Cache Configuration
#--------------------------
query_cache_limit: "2M"
query_cache_size: 0
query_cache_type: 0

#-----------------
# Logging Settings
#-----------------
log_long_format: false
log_output: "file"
log_warnings: true
long_query_time: 10
slow_query_log: 1

#---------------------
# Replication Settings
#---------------------
auto_increment_increment: 10
auto_increment_offset: 1
binlog_cache_size: "1M"
binlog_do_db: []
binlog_format: "ROW"
expire_logs_days: 7
replication"]["ignore_db: []
replication"]["ignore_table: []
log_slave_updates: true
max_binlog_size: "1G"
skip_slave_start: false
slave_compressed_protocol: 1
sync_binlog: 1
##report_host: "fillhost"
slave-net-timeout: 30
slave_parallel_workers: 0
slave_allow_batching: 1
slave_checkpoint_period: 5000
slave_checkpoint_group: 5120
slave_pending_jobs_size_max: 104857600
# for better crash recovery
master_info_repository: "'table'"
relay_log_info_repository: "'table'"
relay_log_recovery: 0

#----------------
# MyISAM settings
#----------------
myisam_max_sort_file_size: "10G"
myisam_recover: "BACKUP"
myisam_repair_threads: 4
myisam_sort_buffer_size: "32M"

#----------------
# InnoDB settings
#----------------
default_storage_engine: "INNODB"
innodb_adaptive_flushing: 1
innodb_autoinc_lock_mode: 2
innodb_additional_mem_pool_size: "32M"
innodb_buffer_pool_instances: 8
innodb_buffer_pool_size: "24G"
innodb_commit_concurrency: 0
innodb_data_file_path: "ibdata1:200M:autoextend:max:1G"
innodb_fast_shutdown: true
innodb_file_format: "barracuda"
innodb_file_io_threads: 4
innodb_file_per_table: 1
innodb_flush_log_at_trx_commit: 2
innodb_flush_method: "O_DIRECT"
innodb_io_capacity: 1000
innodb_io_capacity_max: 10000
innodb_lock_wait_timeout: 50
innodb_log_buffer_size: "128M"
innodb_log_file_size: "2G"
innodb_log_files_in_group: 2
innodb_max_dirty_pages_pct: 15
innodb_open_files: 2000
innodb_purge_threads: 8
innodb_read_io_threads: 8
innodb_stats_on_metadata: 0
innodb_stats_sample_pages: 96
innodb_status_file: true
innodb_thread_concurrency: 24
innodb_write_io_threads: 8
innodb_undo_tablespaces: 10
###innodb_undo_directory: "."
innodb_undo_logs: 128
skip_innodb: false

#-------------------
# Performance Schema
#-------------------
performance_schema: "ON"
