#! /usr/bin/perl -w
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
    if 0; #$running_under_some_shell
# WARNING: This file is managed by ansible. Manual changes to this file will/may be overwritten.
#AUTHOR                 =  IKECHUKWU MACDAVID UMEJIOFOR (MAJOR)
#EMAIL                  =  mailmajor01@gmail.com
#DATE                   =  11 February 2017
#PHONE                  =  07867430002
#SCRIPT/FILE PURPOSE    =  Nagios NRPE Plugin to alert and warn key mysql health indicators.
#SCRIPT LOCATION        = '/usr/lib64/nagios/plugins/npre_mysql_health_plugin.pl'
use strict;
use warnings FATAL => 'all';
use Sys::Hostname;
use Storable;
use strict;
use warnings FATAL => 'all';
use MIME::Base64;
use Getopt::Long;
use Crypt::Blowfish;

# checks are based on ports (for multi-mysql-instances)
# check_mysql_slave_io_status
# check_mysql_slave_sql_status
# check_mysql_slave_latency_status
# check_mysql_slave_seconds_behind_master
# check_mysql_error_status
# check_mysql_backup_status
# check_mysql_vip_status
# check_mysql_max_connected_users_status

# -- Define variables -- 
my $verbose; # =1;
my $max_latency = 0;
my $print_defaults;
my $check_mysql_instances_running = '';
my $check_mysql_used_connections = '';
my $check_mysql_slaves_running = '';
my $check_mysql_replication_latency = '';
my $slave_status_report;
my $real_time_conns_count = 0;
my $error;
my $slave_latency_status_report;
my $mysql_running_report;
my $mysql_max_used_connections_report;
my $host = hostname;
my $WARNING_EXITCODE = 1;
my $CRITICAL_EXITCODE = 2;
my $UNKNOWN_EXITCODE = 3;
my $ALL_OK_EXITCODE = 0;
# my %nagios_exit_messages=(
#     'criticals' => '',
#     'warnings'  => '',
#     'unknowns'  => '',
#     'all_ok'    => '',
# );
my %check_result_collectors = (
    'check_mysql_instances_running'   =>
    { 'criticals'  => '',
        'warnings' => '',
        'unknowns' => '',
        'all_ok'   => '', },
    'check_mysql_used_connections'    =>
    { 'criticals'  => '',
        'warnings' => '',
        'unknowns' => '',
        'all_ok'   => '', },
    'check_mysql_slaves_running'      =>
    { 'criticals'  => '',
        'warnings' => '',
        'unknowns' => '',
        'all_ok'   => '', },
    'check_mysql_replication_latency' =>
    { 'criticals'  => '',
        'warnings' => '',
        'unknowns' => '',
        'all_ok'   => '', },
);

print "Hostname = $host\n" if ($verbose);
$host =~ s/\.(.*)$//;
my $tmp_db_file = '/usr/lib/check_mk_agent_aux_scripts/.dbinfo';
my $cmd1 = 'sqlite3 /home/oraprd/monitoring/db/server.db "select admin_user, admin_pass, port from server; "  2>/dev/null';
my @dbinfo_cache;
my $database_info_obtained;
my $mysql_instance_was_auto_deployed;
my $mysql_inventory_file = 'mysql_inventory.cnf';
my $mysql_inventory_dir = '/etc/mysql_inventory_dir/';
my $mysql_latency_threshold_file = '/etc/mysql_inventory_dir/replication_latency_threshold.cnf';
my $replication_latency_critical_threshold;
$replication_latency_critical_threshold = `cat $mysql_latency_threshold_file 2>/dev/null  | grep -v '#'  |  grep -i 'critical_alert_threshold' | awk -F '=' '{print \$2}' `;
my $replication_latency_warning_threshold;
$replication_latency_warning_threshold = `cat $mysql_latency_threshold_file 2>/dev/null  | grep -v '#'  |  grep -i 'warning_alert_threshold' | awk -F '=' '{print \$2}' `;
my $critical_val;
my $warning_val;
if ($replication_latency_critical_threshold) {
    $critical_val = $replication_latency_critical_threshold;
}
if ($replication_latency_warning_threshold) {
    $warning_val = $replication_latency_warning_threshold;
}
$critical_val = 60 unless ($replication_latency_critical_threshold);   # alert as critical for latency more than or equal to 60($critical) minutes
$warning_val = 30 unless ($replication_latency_warning_threshold);    # alert as warning for latency more than or equal to 30($warning) minutes
my $mysql_defaults_file = '.my.cnf';
my $cmd0 = "cat $mysql_inventory_dir/$mysql_inventory_file | grep -v '#'  | grep -vi 'Installed_MySQL_Servers' | awk -F ';;' '{print \$3}' | awk -F '=' '{print \$2}'";
chomp(my @list_of_sid_on_host = `$cmd0` );
if ($verbose) {
    print "$_\n" foreach (@list_of_sid_on_host);
}


# -- Lets Use Get Options to Get Command Line Arguments Starts -- #
GetOptions(
    'print-defaults'                  => \$print_defaults,
    'check_mysql_instances_running'   => \$check_mysql_instances_running,
    'check_mysql_used_connections'    => \$check_mysql_used_connections,
    'check_mysql_slaves_running'      => \$check_mysql_slaves_running,
    'check_mysql_replication_latency' => \$check_mysql_replication_latency
);
# -- Lets Use Get Options to Get Command Line Arguments Ends -- #

if ($print_defaults) {
    print( "The Following are Default Options used by this Program: (Change any of the specified options defaults from the command line).\n
    '--check_mysql_instances_running'             ==>  $check_mysql_instances_running      (Status Check: Determine if/whether MySQL Service is running and able to receive connections on this host.)
    '--check_mysql_used_connections'              ==>  $check_mysql_used_connections       (Status Check: Determine if/whether MySQL Service is maxing out allowed number of connections.)
    '--check_mysql_slaves_running'                ==>  $check_mysql_slaves_running         (Status Check: Determine if/whether MySQL Service replication is running.)
    '--check_mysql_replication_latency'           ==>  $check_mysql_replication_latency    (Status Check: Determine if/whether MySQL Service replication latency has crossed its allowed threshold.)
\n\n" );
}

print "Hostname = $host\n" if ($verbose);
$host =~ s/\.(.*)$//;
print "Hostname = $host\n" if ($verbose);

chomp( my @cmd1_output = `$cmd1` );
unless (@cmd1_output)
{
    $error .= " ERROR::TEST1 - Unable to query sqlite3 for mysql instances on host: $host!";
    print "$error\n" if ($verbose);
}

if (-e $tmp_db_file) {
    my $dbinfo = eval {
        retrieve( $tmp_db_file );
    };

    if ($dbinfo) {
        print "Loading DB to Memory Successful!\n" if ($verbose);
        print "Data retrieved from database: @{$dbinfo}!\n" if ($verbose);
        @dbinfo_cache = @{$dbinfo};
    }
}

if (@cmd1_output) {
    # This only happens if the node is registered to the DBA legacy monitoring.
    # print "$_\n" foreach (@cmd1_output) if ($verbose);
    if (!-e $tmp_db_file) {
        eval {store \@cmd1_output, $tmp_db_file };
    } else
    {
        if ($#cmd1_output != $#dbinfo_cache) {
            print "Overwriting local database info cache..." if ($verbose);
            eval {store \@cmd1_output, $tmp_db_file; };
        }

    }
    $database_info_obtained += 1;
} elsif (@list_of_sid_on_host) {
    # means the node is not registered to the DBA legacy monitoring monitoring.
    # lets obtain mysql connect creadential using config files deployed by ansible.
    foreach my $sid (@list_of_sid_on_host)
    {
        my $mysql_cmd = "mysql --defaults-file=$mysql_inventory_dir/${sid}${mysql_defaults_file}";
        chomp(my $mysql_server_version = `$mysql_cmd -NBse 'select \@\@version' 2>/dev/null`);
        unless ($mysql_server_version)
        {
            $error .= "Could not connect to MySQL Server Host: $host! & SID: $sid";
            print "$error\n" if ($verbose);
        }
        if ($mysql_server_version)
        {
            $database_info_obtained += 1;
            #chomp(my $user_extracted=`mysql -NBse 'select SUBSTRING_INDEX(user(), "@" , 1)'`);
            chomp(my $user_extracted = `$mysql_cmd -NBse "select SUBSTRING_INDEX(user(), '\@' , 1)"`);
            chomp(my $port_extracted = `$mysql_cmd -NBse 'select \@\@port'`);
            chomp(my $socket_extracted = `$mysql_cmd -NBse 'select \@\@socket'`);
            $error .= "Could not extract a default user from MySQL!" unless ($user_extracted);
            $error .= "Could not extract a default port from MySQL!" unless ($port_extracted);
            $error .= "Could not extract a default socket from MySQL!" unless ($socket_extracted);
            print "MySQL Connect User extracted: $user_extracted\n" if ($verbose);
            print "MySQL Connect Port extracted: $port_extracted\n" if ($verbose);
            print "MySQL Connect socket extracted: $socket_extracted\n" if ($verbose);
            $mysql_instance_was_auto_deployed++ if ( ($user_extracted) && ($port_extracted) && ($socket_extracted ) );
            push @cmd1_output, "${user_extracted}|${port_extracted}|${socket_extracted}";
        }
    }

}

unless (@cmd1_output)
{
    if (@dbinfo_cache) {
        @cmd1_output = @dbinfo_cache;
        $database_info_obtained += 1;
    }
}

unless ($database_info_obtained)
{
    $error .= " ERROR::Confirmed - Unable to obtain info for mysql instances on host: $host!";
    print "$error\n" if ($verbose);
}

if ($database_info_obtained) {
    foreach my $mysql_instance_info (@cmd1_output)
    {
        my ($mysql_user, $mysql_enc_pass, $mysql_port, $mysql_socket);
        # my $mysql_connect_error;
        my $mysql_max_connection_error;
        ($mysql_user, $mysql_enc_pass, $mysql_port) = split /\|/,
            $mysql_instance_info unless ($mysql_instance_was_auto_deployed);
        ($mysql_user, $mysql_port, $mysql_socket) = split /\|/,
            $mysql_instance_info if ($mysql_instance_was_auto_deployed);
        my $cmd2 = &output_pass( "$mysql_enc_pass" ) if ($mysql_enc_pass);
        print "pass ===>  $cmd2 \n" if ( ($verbose) && ($mysql_enc_pass) );
        chomp( my $mysql_pass_extracted = $cmd2 ) if ($mysql_enc_pass);
        if ($mysql_enc_pass) {
            unless ($mysql_pass_extracted)
            {
                print "ERROR: Unable to obtain MySQL Password!\n" if ($verbose);
                $error .= " ERROR: Unable to obtain MySQL Login Credential!";
            }
        }

        my $mysql_pass = $mysql_pass_extracted if ($mysql_enc_pass);
        $mysql_pass = '' unless ($mysql_enc_pass);
        print "User Login Info for MySQL Instance Running on Port: $mysql_port ==> User: $mysql_user Socket: $mysql_socket Password: $mysql_pass\n" if ($verbose);

        my ($cmd3_real_time_conns_count, $cmd4_max_set_conns, $cmd5_connect_to_mysql, $cmd6_mysql_slave_status, $cmd7_mysql_all_slaves_status, $cmd8_mysql_dbadb_latency_check);
        if ($mysql_instance_was_auto_deployed) {
            $cmd3_real_time_conns_count = "timeout 10  mysql -NB -u $mysql_user  -S $mysql_socket  -P $mysql_port  -e 'select count(*) from information_schema.processlist;'   2>/dev/null ";
            $cmd4_max_set_conns = "timeout 10  mysql -NB -u $mysql_user -S $mysql_socket -P $mysql_port  -e 'show global variables like \"max_connections\"'  2>/dev/null ";
            $cmd5_connect_to_mysql = "timeout 10  mysql  -NB -u $mysql_user -S $mysql_socket  -P $mysql_port  -e 'select \@\@version'   2>/dev/null ";
            $cmd6_mysql_slave_status = "timeout 5 mysql   -u $mysql_user -S $mysql_socket -P $mysql_port  -e 'show slave status\\G' 2>/dev/null ";
            $cmd7_mysql_all_slaves_status = "timeout 5 mysql   -u $mysql_user  -S $mysql_socket -P $mysql_port  -e 'show all slaves status\\G' 2>/dev/null ";
            $cmd8_mysql_dbadb_latency_check = "timeout 5 mysql   -u $mysql_user  -S $mysql_socket -P $mysql_port  -e '
                            select server_name, FLOOR((unix_timestamp(now()) - unix_timestamp(time_stamp))/60) AS latency_mins FROM dbadb.latency \\G' 2>/dev/null ";

        } elsif ($mysql_pass_extracted)
        {
            $cmd3_real_time_conns_count = "timeout 10  mysql -NB -u $mysql_user -p$mysql_pass  -P $mysql_port  -e 'select count(*) from information_schema.processlist;'   2>/dev/null ";
            $cmd4_max_set_conns = "timeout 10  mysql -NB -u $mysql_user -p$mysql_pass -P $mysql_port  -e 'show global variables like \"max_connections\"'  2>/dev/null ";
            $cmd5_connect_to_mysql = "timeout 10  mysql  -NB -u $mysql_user -p$mysql_pass -P $mysql_port  -e 'select \@\@version'   2>/dev/null ";
            $cmd6_mysql_slave_status = "timeout 5 mysql   -u $mysql_user -p$mysql_pass -P $mysql_port  -e 'show slave status\\G' 2>/dev/null ";
            $cmd7_mysql_all_slaves_status = "timeout 5 mysql   -u $mysql_user -p$mysql_pass -P $mysql_port  -e 'show all slaves status\\G' 2>/dev/null ";
            $cmd8_mysql_dbadb_latency_check = "timeout 5 mysql   -u $mysql_user -p$mysql_pass -P $mysql_port  -e '
                            select server_name, FLOOR((unix_timestamp(now()) - unix_timestamp(time_stamp))/60) AS latency_mins FROM dbadb.latency \\G' 2>/dev/null ";
        }

        chomp( my $cmd_real_time_conns_count_output = `$cmd3_real_time_conns_count` );
        chomp( my $cmd_max_set_conns_output = `$cmd4_max_set_conns` );
        chomp( my $cmd5_connect_to_mysql_output = `$cmd5_connect_to_mysql` );
        my $cmd6_mysql_slave_status_output = `$cmd6_mysql_slave_status`;
        my $cmd7_mysql_all_slaves_status_output = `$cmd7_mysql_all_slaves_status`;
        my $cmd8_mysql_dbadb_latency_check_output = `$cmd8_mysql_dbadb_latency_check`;
        check_slave_status( $cmd6_mysql_slave_status_output, $mysql_port );
        check_slave_status( $cmd7_mysql_all_slaves_status_output, $mysql_port );
        check_latency($cmd8_mysql_dbadb_latency_check_output, $mysql_port );

        if ($cmd5_connect_to_mysql_output) {
            my $message = "OK: Able to check Replication Slave Status - MySQL is Running.";
            $mysql_running_report .= "$message check_mysql_on_port_${mysql_port}_slave_status_connect count=1 ";
            $check_result_collectors{'check_mysql_instances_running'}{'all_ok'} = $mysql_running_report;
        } else {
            my $message = "ERROR: Unable to check Replication Slave Status - Check that MySQL is Running and can accept connections.";
            $mysql_running_report .= "$message check_mysql_on_port_${mysql_port}_slave_status_connect count=0 ";
            $check_result_collectors{'check_mysql_instances_running'}{'criticals'} = $mysql_running_report;
        }

        my @result = split /\s+/, $cmd_max_set_conns_output;
        # print"Result ==> |@result|\n";
        $cmd_max_set_conns_output = $result[1];
        print "MySQL Instance Running on Port: $mysql_port ==> Has User: $mysql_user Password: $mysql_pass with Max Connections Set to: $cmd_max_set_conns_output and Real Time Connections Count: $cmd_real_time_conns_count_output\n" if ($verbose);


        unless ($cmd_real_time_conns_count_output)
        {
            print "ERROR: Unable to obtain Number of Counts for MySQL Realtime Connections for MySQL Instance Running on Port: $mysql_port!\n" if ($verbose);
            $mysql_max_used_connections_report .= " ERROR: Unable to obtain Number of Counts for MySQL Realtime Connections for MySQL Instance Running on Port: $mysql_port!";
            $mysql_max_connection_error += 1;
        }

        unless ($cmd_max_set_conns_output)
        {
            print "ERROR: Unable to obtain Maximum Number of Connections Set for MySQL Instance Running on Port: $mysql_port!\n" if ($verbose);
            $mysql_max_used_connections_report .= " ERROR: Unable to obtain Maximum Number of Connections Set for MySQL Instance Running on Port: $mysql_port!";
            $mysql_max_connection_error += 1;
        }

        if ($mysql_max_connection_error) {
            $check_result_collectors{'check_mysql_used_connections'}{'unknowns'} = $mysql_max_used_connections_report;
        } else {
            my $critical = 95;
            my $warning = 90;
            my $message;
            my $percent_used_connection = int( $cmd_real_time_conns_count_output * 100 / $cmd_max_set_conns_output );
            $real_time_conns_count = $percent_used_connection if (($percent_used_connection) && ($real_time_conns_count < $percent_used_connection));
            print "Percentage used connections to database: $percent_used_connection\%\n" if ($verbose);
            if ((  $percent_used_connection > $warning ) && (  $percent_used_connection < $critical  )) {
                $message = "WARNING: $cmd_real_time_conns_count_output of $cmd_max_set_conns_output - $percent_used_connection\% used!";
                $mysql_max_used_connections_report .= "$message check_mysql_used_connections_port_$mysql_port ";
                $check_result_collectors{'check_mysql_used_connections'}{'warnings'} = $mysql_max_used_connections_report;

            } elsif ($percent_used_connection >= $critical)
            {
                $message = "CRITICAL: $cmd_real_time_conns_count_output of $cmd_max_set_conns_output - $percent_used_connection\% used!";
                $mysql_max_used_connections_report .= "$message check_mysql_used_connections_port_$mysql_port ";
                $check_result_collectors{'check_mysql_used_connections'}{'criticals'} = $mysql_max_used_connections_report;

            } else
            {
                $message = "OK: $cmd_real_time_conns_count_output of $cmd_max_set_conns_output - $percent_used_connection\% used!";
                $mysql_max_used_connections_report .= "$message check_mysql_used_connections_port_$mysql_port ";
                $check_result_collectors{'check_mysql_used_connections'}{'all_ok'} = $mysql_max_used_connections_report;

            }

        }

    }
}

if ($check_mysql_slaves_running) {

    if ($check_result_collectors{'check_mysql_slaves_running'}{'criticals'})
    {
        print "$check_result_collectors{'check_mysql_slaves_running'}{'criticals'} | mysql_slaves_running=-1;0;-1;-2;2 \n ";
        exit $CRITICAL_EXITCODE;
    } elsif ($check_result_collectors{'check_mysql_slaves_running'}{'warnings'})
    {
        print "$check_result_collectors{'check_mysql_slaves_running'}{'warnings'}| mysql_slaves_running=0;0;-1;-2;2 \n ";
        exit $WARNING_EXITCODE;
    } elsif ($check_result_collectors{'check_mysql_slaves_running'}{'all_ok'})
    {
        print "$check_result_collectors{'check_mysql_slaves_running'}{'all_ok'} | mysql_slaves_running=1;0;-1;-2;2 \n ";
        exit $ALL_OK_EXITCODE;
    } else
    {
        print "UNKNOWN - Check To See if MySQL is Running: $check_result_collectors{'check_mysql_slaves_running'}{'unknowns'} | mysql_slaves_running=-2;0;-1;-2;2 \n ";
        exit $UNKNOWN_EXITCODE;
    }

} elsif ($check_mysql_replication_latency)
{
    if ($check_result_collectors{'check_mysql_replication_latency'}{'criticals'})
    {
        print "$check_result_collectors{'check_mysql_replication_latency'}{'criticals'} | latency=${max_latency}minutes;$warning_val;$critical_val;-100;1000 \n";
        exit $CRITICAL_EXITCODE;
    } elsif ($check_result_collectors{'check_mysql_replication_latency'}{'warnings'})
    {
        print "$check_result_collectors{'check_mysql_replication_latency'}{'warnings'} | latency=${max_latency}minutes;$warning_val;$critical_val;-100;1000 \n";
        exit $WARNING_EXITCODE;
    } elsif ($check_result_collectors{'check_mysql_replication_latency'}{'all_ok'})
    {
        print "$check_result_collectors{'check_mysql_replication_latency'}{'all_ok'} | latency=${max_latency}minutes;$warning_val;$critical_val;-100;1000 \n";
        exit $ALL_OK_EXITCODE;
    } else
    {
        print "UNKNOWN - Check To See if MySQL is Running: $check_result_collectors{'check_mysql_replication_latency'}{'unknowns'} | latency=-100minutes;$warning_val;$critical_val;-100;1000 \n";
        exit $UNKNOWN_EXITCODE;
    }

} elsif ($check_mysql_instances_running)
{
    if ($check_result_collectors{'check_mysql_instances_running'}{'criticals'})
    {
        print "$check_result_collectors{'check_mysql_instances_running'}{'criticals'} | mysql_running=0;-1;1;-2;2 \n ";
        exit $CRITICAL_EXITCODE;
    } elsif ($check_result_collectors{'check_mysql_instances_running'}{'warnings'})
    {
        print "$check_result_collectors{'check_mysql_instances_running'}{'warnings'}| mysql_running=0;0;-1;-2;2 \n ";
        exit $WARNING_EXITCODE;
    } elsif ($check_result_collectors{'check_mysql_instances_running'}{'all_ok'})
    {
        print "$check_result_collectors{'check_mysql_instances_running'}{'all_ok'} | mysql_running=1;0;-1;-2;2 \n ";
        exit $ALL_OK_EXITCODE;
    } else
    {
        print "UNKNOWN - Check To See if MySQL is Running: $check_result_collectors{'check_mysql_instances_running'}{'unknowns'} | mysql_running=-2;0;-1;-2;2 \n ";
        exit $UNKNOWN_EXITCODE;
    }

} elsif ($check_mysql_used_connections)
{

    if ($check_result_collectors{'check_mysql_used_connections'}{'criticals'})
    {
        print "$check_result_collectors{'check_mysql_used_connections'}{'criticals'} | mysql_used_connections=${real_time_conns_count}%;90;95;-1;100 \n ";
        exit $CRITICAL_EXITCODE;
    } elsif ($check_result_collectors{'check_mysql_used_connections'}{'warnings'})
    {
        print "$check_result_collectors{'check_mysql_used_connections'}{'warnings'}| mysql_used_connections=${real_time_conns_count}%;90;95;-1;100 \n ";
        exit $WARNING_EXITCODE;
    } elsif ($check_result_collectors{'check_mysql_used_connections'}{'all_ok'})
    {
        print "$check_result_collectors{'check_mysql_used_connections'}{'all_ok'} | mysql_used_connections=${real_time_conns_count}%;90;95;-1;100 \n ";
        exit $ALL_OK_EXITCODE;
    } else
    {
        print "UNKNOWN - Check To See if MySQL is Running: $check_result_collectors{'check_mysql_used_connections'}{'unknowns'} | mysql_used_connections=-1%;90;95;-1;100 \n ";
        exit $UNKNOWN_EXITCODE;
    }
}






sub check_slave_status {
    my $output = shift;
    my $mysql_port = shift;
    # my $mysql_sid = shift;
    # my $unknown=0;
    # my $warning=0;
    my $critical = 0;
    my $all_ok = 0;
    if ($output) {
        my @all_slaves_status;     # we assume mysql node may have multiple masters
        my $masters_counter = 0;
        foreach(split /\n/, $output) {
            $masters_counter += 1 and next if ( $_ =~ /\s*\*\*+/ );
            $all_slaves_status[$masters_counter - 1] .= "$_\n";
        }

        print "We see: $masters_counter - master(s)\n" if ($verbose);
        # print "$_\n" foreach(@all_slaves_status) ;
        foreach(@all_slaves_status) {
            my @cmd_output = split /\n/, $_;
            my %important_vars;
            foreach(@cmd_output) {
                chomp;
                next unless ( $_ =~ /(\bSeconds_B)|(\bMaster_)|(\bSlave_)|(\bLast_)|(\bChannel_name)|(\bConnection_name)/ );
                $important_vars{'Master_Host'} = (split /\:/, $_  )[1] if ( $_ =~ /\bMaster_Host/ );
                $important_vars{'Seconds_Behind_Master'} = (split /\:/, $_  )[1] if ( $_ =~ /\bSeconds_Behind_Master/ );
                $important_vars{'Slave_IO_running'} = (split /\:/, $_  )[1] if ( $_ =~ /\bSlave_IO_Running/i );
                $important_vars{'Slave_SQL_running'} = (split /\:/, $_  )[1] if ( $_ =~ /\bSlave_SQL_Running\s*\:/i );
                $important_vars{'Errors'} .= $_.' ' if ( $_ =~ /\bLast_/ );
                $important_vars{'Channel_name'} = (split /\:/, $_  )[1] if ( $_ =~ /\bChannel_name/ );
                $important_vars{'Connection_name'} = (split /\:/, $_  )[1] if ( $_ =~ /\bConnection_name/ );
            }
            print "important_vars:\n" if ($verbose);
            foreach (keys %important_vars) {
                $important_vars{$_} =~ s/\s+/ /g;
                print "$_  ==>  $important_vars{$_}\n" if ($verbose);
            }
            if (( $important_vars{'Slave_IO_running'} =~ /\byes/i ) and ( $important_vars{'Slave_SQL_running'} =~ /\byes/i   )) {
                my $message = "OK: Slave_IO_running: Yes - Slave_SQL_running: Yes";
                $important_vars{'Channel_name'} =~ s/\s+//g if ( $important_vars{'Channel_name'}  );
                $important_vars{'Connection_name'} =~ s/\s+//g if ( $important_vars{'Connection_name'}  );
                $slave_status_report .= "$message slave_running_on_port_${mysql_port}_4_channel_$important_vars{'Channel_name'}    " if ( $important_vars{'Channel_name'}  );
                $slave_status_report .= "$message slave_running_on_port_${mysql_port}_4_Connection_name_$important_vars{'Connection_name'}   " if ( $important_vars{'Connection_name'}  );
                $slave_status_report .= "$message slave_running_on_port_${mysql_port}   " unless ( ($important_vars{'Channel_name'} ) && ($important_vars{'Connection_name'})  );
                $check_result_collectors{'check_mysql_slaves_running'}{'all_ok'} = $slave_status_report;
                # $nagios_exit_messages{'all_ok'} .=  $slave_status_report;
                $all_ok++;
            } else {
                $important_vars{'Slave_IO_running'} =~ s/\s+//g;
                $important_vars{'Slave_SQL_running'} =~ s/\s+//g;
                my $message = "CRITICAL: Slave_IO_running: $important_vars{'Slave_SQL_running'} - Slave_SQL_running: $important_vars{'Slave_IO_running'}".' '.$important_vars{'Errors'};
                $important_vars{'Channel_name'} =~ s/\s+//g if ( $important_vars{'Channel_name'}  );
                $important_vars{'Connection_name'} =~ s/\s+//g if ( $important_vars{'Connection_name'}  );
                $slave_status_report .= "$message slave_running_on_port_${mysql_port}_4_channel_$important_vars{'Channel_name'}    " if ( $important_vars{'Channel_name'}  );
                $slave_status_report .= "$message slave_running_on_port_${mysql_port}_4_Connection_name_$important_vars{'Connection_name'}   " if ( $important_vars{'Connection_name'}  );
                $slave_status_report .= "$message slave_running_on_port_${mysql_port}   " unless ( ($important_vars{'Channel_name'} ) && ($important_vars{'Connection_name'})  );
                $check_result_collectors{'check_mysql_slaves_running'}{'criticals'} = $slave_status_report;
                #$nagios_exit_messages{'criticals'} .= $slave_status_report;
                $critical++;
            }
        }

    }

}




sub check_latency {
    my $output = shift;
    my $mysql_port = shift;
    my $unknown = 0;
    my $warning = 0;
    my $critical = 0;
    my $all_ok = 0;

    if ($output) {
        my @all_nodes_lantency_status;   # we assume there are multiple nodes involved in replication.
        my $nodes_counter;
        foreach(split /\n/, $output) {
            $nodes_counter += 1 and next if ( $_ =~ /\s*\*\*+/ );
            $all_nodes_lantency_status[$nodes_counter - 1] .= "$_\n";
        }
        print "We see: $nodes_counter - node(s)\n" if ($verbose);
        foreach (@all_nodes_lantency_status)
        {
            my @cmd_output = split /\n/, $_;
            my %important_vars;
            foreach(@cmd_output) {
                chomp;
                $important_vars{'Server_Name'} = (split /\:/, $_  )[1] if ( $_ =~ /\bserver_name/i );
                $important_vars{'Latency_Mins'} = (split /\:/, $_  )[1] if ( $_ =~ /\blatency_mins/i );
            }
            print "important_vars:\n" if ($verbose);
            foreach (keys %important_vars) {
                $important_vars{$_} =~ s/\s+//g;
                print "$_  ==>  $important_vars{$_}\n" if ($verbose);
            }
            next if ($important_vars{'Server_Name'} =~ /\b$host/i);

            if ($important_vars{'Latency_Mins'} < $warning_val) {
                $max_latency = $important_vars{'Latency_Mins'} if ($important_vars{'Latency_Mins'} > $max_latency);
                my $message = "OK: Replication Slave is running optimally. Latency = $important_vars{'Latency_Mins'} minutes.";
                $slave_latency_status_report .= "$message - mysql_rep_latency_on_port_${mysql_port}_from_node_$important_vars{'Server_Name'}   ";
                $check_result_collectors{'check_mysql_replication_latency'}{'all_ok'} = $slave_latency_status_report;
                # $nagios_exit_messages{'all_ok'} .=  $slave_latency_status_report;
                $all_ok++;
            } elsif (( $important_vars{'Latency_Mins'} >= $warning_val ) and ( $important_vars{'Latency_Mins'} < $critical_val   ))
            {
                $max_latency = $important_vars{'Latency_Mins'} if ($important_vars{'Latency_Mins'} > $max_latency);
                my $message = "WARNING!: Replication Slave is lagging by $important_vars{'Latency_Mins'} minutes.";
                $slave_latency_status_report .= "$message - mysql_rep_latency_on_port_${mysql_port}_from_node_$important_vars{'Server_Name'}   ";
                $check_result_collectors{'check_mysql_replication_latency'}{'warnings'} = $slave_latency_status_report;
                # $nagios_exit_messages{'warnings'} .=  $slave_latency_status_report;
                $warning++;
            } elsif ($important_vars{'Latency_Mins'} >= $critical_val)
            {
                $max_latency = $important_vars{'Latency_Mins'} if ($important_vars{'Latency_Mins'} > $max_latency);
                my $message = "CRITICAL!: Replication Slave is lagging by $important_vars{'Latency_Mins'} minutes.";
                $slave_latency_status_report .= "$message - mysql_rep_latency_on_port_${mysql_port}_from_node_$important_vars{'Server_Name'}   ";
                $check_result_collectors{'check_mysql_replication_latency'}{'criticals'} = $slave_latency_status_report;
                # $nagios_exit_messages{'criticals'} .=  $slave_latency_status_report;
                $critical++;
            } else
            {
                my $message = "UNKNOWN ERROR!: Unable to check mysql replication latency status - check that dbdb.lantency table exists.";
                $slave_latency_status_report .= "$message - mysql_rep_latency_on_port_${mysql_port}_from_node_$important_vars{'Server_Name'}   ";
                $check_result_collectors{'check_mysql_replication_latency'}{'unknown'} = $slave_latency_status_report;
                # $nagios_exit_messages{'unknown'} .=  $slave_latency_status_report;
                $unknown++;
            }

        }
    } else
    {
        my $message = "UNKNOWN ERROR!: Unable to check mysql replication latency status - check that dbdb.lantency table exists.";
        $slave_latency_status_report .= "$message  ";
        $check_result_collectors{'check_mysql_replication_latency'}{'unknown'} = $slave_latency_status_report;
        # $nagios_exit_messages{'unknown'} .=  $slave_latency_status_report;
        $unknown++;
    }

}


