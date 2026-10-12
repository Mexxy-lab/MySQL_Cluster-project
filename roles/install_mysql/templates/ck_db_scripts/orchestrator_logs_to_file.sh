# Every minute log of orchestrator.audit table

mysql -NB -A orchestrator -e "select concat('audit_timestamp=', date_format(audit_timestamp, '%Y-%m-%dT%T'), ' audit_id=', audit_id, ' audit_type=', audit_type, ' hostname=', hostname, ' port=', port, ' cluster_name=', cluster_name, ' message=\"', message, '\"') from orchestrator.audit where audit_timestamp >= date_format(now(), '%Y-%m-%d %H:%i:00') - interval 1 minute and audit_timestamp < date_format(now(), '%Y-%m-%d %H:%i:00') and audit_type not in ('forget-unseen','inject-unseen-masters','resolve-unknown-masters','forget-unseen-differently-resolved','review-unseen-instances');" > /var/log/orchestrator_audit_table.log

# Every minute log of orchestrator.topology_failure_detection table

mysql -NB -A orchestrator -e"select concat('detect_time=', date_format(start_active_period, '%Y-%m-%dT%T'), ' analysis=', analysis, ' failed_instance=', hostname, ':', port, ' count_affected_slaves=', count_affected_slaves, ' cluster_name=', cluster_name, ' cluster_alias=', cluster_alias) from orchestrator.topology_failure_detection where start_active_period >= date_format(now(), '%Y-%m-%d %H:%i:00') - interval 1 minute and start_active_period < date_format(now(), '%Y-%m-%d %H:%i:00');" > /var/log/orchestrator_topology_failure_detection_table.log

# Full table scan of orchestrator.topology_recovery table

mysql -NB -A orchestrator -e"select concat('start_time=', date_format(start_active_period, '%Y-%m-%dT%T'), ' end_time=', date_format(end_recovery,'%Y-%m-%dT%T'), ' analysis=', analysis, ' failed_instance=', hostname, ':', port, ' cluster_name=', cluster_name, ' successor_instance=', successor_hostname, ':', successor_port, ' processed_by=', processing_node_hostname, ' affected_slaves=', count_affected_slaves, ' slave_hosts=', slave_hosts) from orchestrator.topology_recovery;" > /var/log/orchestrator_topology_recovery.log
