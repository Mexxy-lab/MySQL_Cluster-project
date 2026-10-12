#! /usr/bin/perl -w
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
    if 0; #$running_under_some_shell
# WARNING: This file is managed by ansible. Manual changes to this file will/may be overwritten.
#AUTHOR                 =  IKECHUKWU MACDAVID UMEJIOFOR (MAJOR)
#EMAIL                  =  mailmajor01@gmail.com
#DATE                   =  29 February 2016
#PHONE                  =  07867430002
#SCRIPT/FILE PURPOSE    =  Nagios Plugin to alert and warn key mysql health indicators.
#SCRIPT LOCATION        = '/usr/lib/check_mk_agent/local/mysql_health_status.pl'
use strict;
use warnings FATAL => 'all';
use Sys::Hostname;
use Storable;

my $tmp_db_file = '/usr/lib/check_mk_agent_aux_scripts/.dbinfo';
my $cmd_path_to_decrypt_mysql_pass = '/usr/lib/check_mk_agent_aux_scripts/decrypt_mysql_pass.pl';
my $cmd1 = 'sqlite3 /home/oraprd/monitoring/db/server.db "select admin_user, admin_pass, port from server; "  2>/dev/null';
my @dbinfo_cache;
my $database_info_obtained;
my $error;
my $verbose;
# my $mysql_client_path = `which mysql`;
my $check_mk_report;
# my $local_db = '/home/oraprd/monitoring/db/server.db';
# my $sql1 = 'select db_user , password from server;';
my $host = hostname;
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
    # print "$_\n" foreach (@cmd1_output);
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
        my $mysql_connect_error;
        my $mysql_max_connection_error;
        my ($mysql_user, $mysql_enc_pass, $mysql_port) = split /\|/, $mysql_instance_info;;
        my $cmd2 = "perl $cmd_path_to_decrypt_mysql_pass $mysql_enc_pass  2>/dev/null ";
        chomp( my $cmd2_output = `$cmd2` );
        unless ($cmd2_output)
        {
            print "ERROR: Unable to obtain MySQL Password!\n" if ($verbose);
            $error .= " ERROR: Unable to obtain MySQL Login Credential!";
        }
        my $mysql_pass = $cmd2_output;
        print "User Login Info for MySQL Instance Running on Port: $mysql_port ==> User: $mysql_user Password: $mysql_pass\n" if ($verbose);

        my $cmd3_real_time_conns_count = "timeout 10  mysql -NB -u $mysql_user -p$mysql_pass  -P $mysql_port --protocol=tcp -e 'select count(*) from information_schema.processlist;'   2>/dev/null ";
        my $cmd4_max_set_conns = "timeout 10  mysql -NB -u $mysql_user -p$mysql_pass -P $mysql_port --protocol=tcp -e 'show global variables like \"max_connections\"'  2>/dev/null ";
        my $cmd5_connect_to_mysql = "timeout 10  mysql  -NB -u $mysql_user -p$mysql_pass -P $mysql_port --protocol=tcp -e 'select \@\@version'   2>/dev/null ";
        my $cmd6_mysql_slave_status = "timeout 5 mysql   -u $mysql_user -p$mysql_pass -P $mysql_port --protocol=tcp -e 'show slave status\\G' 2>/dev/null ";
        my $cmd7_mysql_all_slaves_status = "timeout 5 mysql   -u $mysql_user -p$mysql_pass -P $mysql_port --protocol=tcp -e 'show all slaves status\\G' 2>/dev/null ";
        my $cmd8_mysql_dbadb_latency_check = "timeout 5 mysql   -u $mysql_user -p$mysql_pass -P $mysql_port --protocol=tcp -e '
                            select server_name, FLOOR((unix_timestamp(now()) - unix_timestamp(time_stamp))/60) AS latency_mins FROM dbadb.latency \\G' 2>/dev/null ";

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
            $check_mk_report .= "0 check_mysql_on_port_${mysql_port}_slave_status_connect count=1 $message\n";
        } else {
            my $message = "ERROR: Unable to check Replication Slave Status - Check that MySQL is Running and can accept connections.";
            $check_mk_report .= "3 check_mysql_on_port_${mysql_port}_slave_status_connect count=0 $message\n";
        }

        unless ($cmd_real_time_conns_count_output)
        {
            print "ERROR: Unable to obtain Number of Counts for MySQL Realtime Connections for MySQL Instance Running on Port: $mysql_port!\n" if ($verbose);
            $error .= " ERROR: Unable to obtain Number of Counts for MySQL Realtime Connections for MySQL Instance Running on Port: $mysql_port!";
            $mysql_max_connection_error += 1;
        }

        unless ($cmd_max_set_conns_output)
        {
            print "ERROR: Unable to obtain Maximum Number of Connections Set for MySQL Instance Running on Port: $mysql_port!\n" if ($verbose);
            $error .= " ERROR: Unable to obtain Maximum Number of Connections Set for MySQL Instance Running on Port: $mysql_port!";
            $mysql_max_connection_error += 1;
        }

        unless ($cmd5_connect_to_mysql) {
            print "ERROR: Unable to Connect to MySQL Instance Running on Port: $mysql_port!\n" if ($verbose);
            $error .= " ERROR: Unable to Connect to MySQL Instance Running on Port: $mysql_port!";
            $mysql_connect_error += 1;
        }

        my @result = split /\s+/, $cmd_max_set_conns_output;
        # print"Result ==> |@result|\n";
        $cmd_max_set_conns_output = $result[1];
        print "MySQL Instance Running on Port: $mysql_port ==> Has User: $mysql_user Password: $mysql_pass with Max Connections Set to: $cmd_max_set_conns_output and Real Time Connections Count: $cmd_real_time_conns_count_output\n" if ($verbose);

        unless ($mysql_connect_error)
        {
            $check_mk_report .= "0 MySQL_Instance_Port_$mysql_port count=1 OK - MySQL Instance On Port: $mysql_port is Running!\n";
        }
        if ($mysql_connect_error) {
            $check_mk_report .= "3 MySQL_Instance_Port_$mysql_port count=0 UNKNOWN ERROR - MySQL Instance On Port: $mysql_port - $error\n";
        }

        unless ($mysql_max_connection_error)
        {
            my $critical = 95;
            my $warning = 90;
            my $message;
            my $exit_code;
            my $percent_used_connection = int( $cmd_real_time_conns_count_output * 100 / $cmd_max_set_conns_output );
            print "Percentage used connections to database: $percent_used_connection\%\n" if ($verbose);
            if ((  $percent_used_connection > $warning ) && (  $percent_used_connection < $critical  )) {
                $message = "WARNING: $cmd_real_time_conns_count_output of $cmd_max_set_conns_output - $percent_used_connection\% used!";
                $exit_code = 1;
            } elsif ($percent_used_connection >= $critical)
            {
                $message = "CRITICAL: $cmd_real_time_conns_count_output of $cmd_max_set_conns_output - $percent_used_connection\% used!";
                $exit_code = 2;
            } else
            {
                $message = "OK: $cmd_real_time_conns_count_output of $cmd_max_set_conns_output - $percent_used_connection\% used!";
                $exit_code = 0;
            }
            $check_mk_report .= "$exit_code check_mysql_used_connections_port_$mysql_port count=$percent_used_connection $message\n";
        }

        if ($mysql_max_connection_error)
        {
            my $exit_code = 3;
            my $message = "ERROR: Unable to obtain MySQL Used Connections! Check that MySQL is running!";
            $check_mk_report .= "$exit_code check_mysql_used_connections_port_$mysql_port count=0 $message\n";
        }

        # Checking For replication:

    }
}

print "$check_mk_report";

sub check_slave_status {
    my $output = shift;
    my $mysql_port = shift;
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
                $important_vars{'Slave_IO_running'} = (split /\:/, $_  )[1] if ( $_ =~ /\bSlave_IO_Running/ );
                $important_vars{'Slave_SQL_running'} = (split /\:/, $_  )[1] if ( $_ =~ /\bSlave_SQL_Running\s*\:/ );
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
                $check_mk_report .= "0 check_mysql_slave_running_on_port_${mysql_port}_4_channel_$important_vars{'Channel_name'} count=1 $message\n" if ( $important_vars{'Channel_name'}  );
                $check_mk_report .= "0 check_mysql_slave_running_on_port_${mysql_port}_4_Connection_name_$important_vars{'Connection_name'} count=1 $message\n" if ( $important_vars{'Connection_name'}  );
                $check_mk_report .= "0 check_mysql_slave_running_on_port_${mysql_port} count=1 $message\n" unless ( ($important_vars{'Channel_name'} ) && ($important_vars{'Connection_name'})  );
            } else {
                $important_vars{'Slave_IO_running'} =~ s/\s+//g;
                $important_vars{'Slave_SQL_running'} =~ s/\s+//g;
                my $message = "CRITICAL: Slave_IO_running: $important_vars{'Slave_SQL_running'} - Slave_SQL_running: $important_vars{'Slave_IO_running'}".$important_vars{'Errors'};
                $important_vars{'Channel_name'} =~ s/\s+//g if ( $important_vars{'Channel_name'}  );
                $important_vars{'Connection_name'} =~ s/\s+//g if ( $important_vars{'Connection_name'}  );
                $check_mk_report .= "2 check_mysql_slave_running_on_port_${mysql_port}_4_channel_$important_vars{'Channel_name'} count=0 $message\n" if ( $important_vars{'Channel_name'}  );
                $check_mk_report .= "2 check_mysql_slave_running_on_port_${mysql_port}_4_Connection_name_$important_vars{'Connection_name'} count=0 $message\n" if ( $important_vars{'Connection_name'}  );
                $check_mk_report .= "2 check_mysql_slave_running_on_port_${mysql_port} count=0 $message\n" unless ( ($important_vars{'Channel_name'} ) && ($important_vars{'Connection_name'})   );
            }
        }

    }
}

sub check_latency {
    my $output = shift;
    my $mysql_port = shift;
    # $host = shift;      # take from local host variable
    my $critical = 60;   # alert as critical for latency more than or equal to 60($critical) minutes
    my $warning = 30;    # alert as warning for latency more than or equal to 60($critical) minutes
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

            if ($important_vars{'Latency_Mins'} < $warning) {
                my $message = "OK: Replication Slave is running optimally. Latency = $important_vars{'Latency_Mins'} minutes.";
                $check_mk_report .= "0 check_mysql_rep_latency_on_port_${mysql_port}_from_node_$important_vars{'Server_Name'} count=$important_vars{'Latency_Mins'} $message\n";
            } elsif (( $important_vars{'Latency_Mins'} >= $warning ) and ( $important_vars{'Latency_Mins'} < $critical   ))
            {
                my $message = "WARNING!: Replication Slave is lagging by $important_vars{'Latency_Mins'} minutes.";
                $check_mk_report .= "1 check_mysql_rep_latency_on_port_${mysql_port}_from_node_$important_vars{'Server_Name'} count=$important_vars{'Latency_Mins'} $message\n";
            } elsif ($important_vars{'Latency_Mins'} >= $critical)
            {
                my $message = "CRITICAL!: Replication Slave is lagging by $important_vars{'Latency_Mins'} minutes.";
                $check_mk_report .= "2 check_mysql_rep_latency_on_port_${mysql_port}_from_node_$important_vars{'Server_Name'} count=$important_vars{'Latency_Mins'} $message\n";
            } else
            {
                my $message = "UNKNOWN ERROR!: Unable to check mysql replication latency status - check that dbdb.lantency table exists.";
                $check_mk_report .= "3 check_mysql_rep_latency_on_port_${mysql_port}_from_node_$important_vars{'Server_Name'} count=$important_vars{'Latency_Mins'} $message\n";
            }

        }
    }

}



