#! /usr/bin/perl -w
eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
    if 0; #$running_under_some_shell
# WARNING: This file is managed by ansible. Manual changes to this file will/may be overwritten.
# AUTHOR                 =  IKECHUKWU MACDAVID UMEJIOFOR (MAJOR)
# EMAIL                  =  mailmajor01@gmail.com
# DATE                   =  29 February 2016
# PHONE                  =  07867430002
# SCRIPT/FILE PURPOSE    =  Nagios Plugin to alert and warn key mysql health indicators.
# SCRIPT LOCATION        = '/usr/lib/check_mk_agent/local/mysql_check_backup.pl'

use strict;
use warnings FATAL => 'all';
use Sys::Hostname;
use Storable;
use POSIX qw(strftime);

my $tmp_db_file = '/usr/lib/check_mk_agent_aux_scripts/.dbinfo';
my $cmd_path_to_decrypt_mysql_pass = '/usr/lib/check_mk_agent_aux_scripts/decrypt_mysql_pass.pl';
my $cmd1 = 'timeout 5 sqlite3 /home/oraprd/monitoring/db/server.db "select ux_user, db_user, password, port, backup_base, cnf_file from server"  2>/dev/null';
my @dbinfo_cache;
my $database_info_obtained;
my $error;
my $verbose ;# = 1;
my $check_mk_report;
my $host = hostname;
my $iterationStart = time;
my $secs_in_a_day = 86400;
my $Xtrabackup_rpm = "percona-xtrabackup";
chomp( my $time = `date +%H%M` );
my $early_bird;
my @backup_logs;
chomp( my $current_date_minus_x_days_in_secs = `date +"%s" -d "-48hours"` );      ### Settled for 48hours instead of a day.

# NOTES:
# Backup mount is an NFS share. no_root_squash is not enabled on nfs sever. Hence, you may need to su as a non-root user
# to see contents to non-root user only files/folders:
# SYNTAX: su - <non-root-user> -c "<bash-commands-to-run>"
#  su - dbqhcp -c " ls -l /dbbackup/dbqhcp/HCPQ1/innodb/2016-02-25_03-00-09/"

=BEGIN comment

# -- #### NOT USEFUL FOR NOW STARTS #### -- #
if ($time == 0000) {
    $time = '0';
} elsif ($time =~ m/^0/) {
    $time =~ s/^0*//;
}
# more formats needed?  ==> http://search.cpan.org/dist/TimeDate/lib/Date/Format.pm
# my $todays_backup_dir_date_format = fnGetDate( "%Y-%m-%d" );
# print "'\%Y\%m\%d': todays_backup_dir_date_format ==> $todays_backup_dir_date_format \n" if ($verbose);

# my $targetDate2 = fnGetDate( "%Y%m%d", $iterationStart - $secs_in_a_day );
# print "'\%Y\%m\%d': targetDate2 ==> $targetDate2 \n" if ($verbose);

# my $targetDate3 = fnGetDate( "%Y%m%d", $iterationStart - $secs_in_a_day - $secs_in_a_day );
# print "'\%Y\%m\%d': targetDate3 ==> $targetDate3 \n" if ($verbose);

# my $targetDate4 = fnGetDate( "%Y%m%d", $iterationStart - $secs_in_a_day - $secs_in_a_day - $secs_in_a_day );
# print "'\%Y\%m\%d': targetDate4 ==> $targetDate4 \n" if ($verbose);

if ($time <= 800) {
    $early_bird++;
    push @backup_logs, $_ foreach ($targetDate2, $targetDate3, $targetDate4);
} else
{
    push @backup_logs, $_ foreach ($targetDate1, $targetDate2, $targetDate3, $targetDate4);
}
# -- #### NOT USEFUL FOR NOW ENDS #### -- #

=end comment
=cut

# 86400sec = 24hours
chomp( my $backup_install_date = `timeout 5 rpm -qa --last | grep -i ${Xtrabackup_rpm}  |  awk '{\$1=""; print \$0}'  | sed 's/^\\s//'  | sed 's/\\s\$//'` );
chomp( my $backup_install_date_in_sec = `timeout 5 date --date="$backup_install_date" +%s` );
unless ($backup_install_date) {
    print "XtraBackup RPM is not installed\n" if ($verbose);
    print "Exitiing..." if ($verbose);
    exit 0;
}

print "Hostname = $host\n" if ($verbose);
$host =~ s/\.(.*)$//;
print "Hostname = $host\n" if ($verbose);

chomp( my @cmd1_output = `$cmd1` );
unless (@cmd1_output)
{
    $error .= " ERROR::TEST1 - Unable to query sqlite3 for mysql instance(s) on host: $host!";
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
    $error .= " ERROR::Confirmed - Unable to obtain info for mysql instance(s) on host: $host!";
    print "$error\n" if ($verbose);
}

if ($database_info_obtained) {
    foreach my $mysql_instance_info (@cmd1_output)
    {
        my ( $ux_user, $mysql_user, $mysql_enc_pass, $mysql_port, $backup_base, $cnf_file ) = split /\|/,
            $mysql_instance_info;;
        my $cmd2 = "timeout 5 perl $cmd_path_to_decrypt_mysql_pass $mysql_enc_pass  2>/dev/null ";
        chomp( my $cmd2_output = `$cmd2` );
        unless ($cmd2_output)
        {
            print "ERROR: Unable to obtain MySQL Password!\n" if ($verbose);
            $error .= " ERROR: Unable to obtain MySQL Login Credential!";
        }
        my $mysql_pass = $cmd2_output;
        $backup_base = "$backup_base/innodb/";
        print "User Login Info for MySQL Instance Running on Port: $mysql_port ==> User: $mysql_user, Password: $mysql_pass, CNF: $cnf_file, Backup_loc: $backup_base, db_os_user: $ux_user\n" if ($verbose);

        my $cmd3_list_cron_jobs_for_xtra_backup = "timeout 5 crontab -u $ux_user  -l  2>/dev/null ";
        chomp( my @cmd3_list_cron_jobs_for_xtra_backup_output = `$cmd3_list_cron_jobs_for_xtra_backup` );
        my @xtra_backup_cron_job;
        my @mysqldump_job;

        foreach (@cmd3_list_cron_jobs_for_xtra_backup_output)
        {
            push @xtra_backup_cron_job, $_ if ( $_ =~ /\bmysql_backupdb(.*)xtra(.*)/ );
            push @mysqldump_job, $_ if ($_ =~ /\bmysqldump_backup/);
        }

        my $f5vip;
        my $xtrabackup_enabled;
        foreach (@xtra_backup_cron_job)
        {
            next if ($_ =~ /\A#/);
            $xtrabackup_enabled +=1;
            next if (! $_ =~ /\s+-f\s*.+\s+/ );
            print "Percona Xtrabackup Cron Job Activated!\n" if($verbose);
            if ( $_ =~ /\s+-f\s*.+\s+/ ) {
                   $_ =~ s/.+(\s+-f\s*\S+)/$1/;
                   $_ =~ s/-f\s*(\S+)/$1/;
                   $_ =~ s/(\S+)\s+.+/$1/;
                   $f5vip = $_
            }
            print "f5vip For this host is: $f5vip\n" if(($verbose) && ($f5vip) );
            last;
        }

        my $unable_to_open_backup_dir;
        opendir my $dh, $backup_base or $unable_to_open_backup_dir +=1;

        my $i_have_dr_ok_backup;
        my $most_recent_backup;
        my %true_successful_backups;

        unless ($unable_to_open_backup_dir)
        {
            chomp( my @presummed_successful_backups=`find $backup_base  -maxdepth 1  -type d` ) ;
            # print "presummed_successful_backups ==> @presummed_successful_backups\n";
            # push @presummed_successful_backups, "${backup_base}$_"  foreach grep {-d "$backup_base/$_" && ! /^\.{1,2}$/} readdir($dh);
            chomp( my $cluster_date_minus_5_days_in_secs = `date +"%s" -d "-120hours"` );    # Settled for 5 days for disaster recovery policy adherence.
            my @true_successful_backups;


            foreach my $backups (@presummed_successful_backups)
            {
               chomp(  my $xtrabackup_info_file_exists = `su - $ux_user  -c ' test -f $backups/xtrabackup_info  && echo 2 '` );
               chomp(  my $xtrabackup_info_qp_file_exists = `su - $ux_user  -c ' test -f $backups/xtrabackup_info.qp  && echo 2 '` )   unless(  $xtrabackup_info_file_exists );
                if ( $xtrabackup_info_file_exists  ){
                    my $cmd5_capture_backup_date = "su - $ux_user  -c 'timeout 5 cat $backups/xtrabackup_info  | grep -i end_time   2> /dev/null'";
                    my $cmd5_capture_backup_date_output = `$cmd5_capture_backup_date`;
                    my @garbage = split /\s+/, $cmd5_capture_backup_date_output if ($cmd5_capture_backup_date_output);
                    my $cmd6 = "timeout 5 date --date='$garbage[2]' +%s";
                   my $cmd6_backup_date_in_secs_output = `$cmd6` if (@garbage);
                    $backups =~ s#\/\/#\/#;
                    $true_successful_backups{$backups} = $cmd6_backup_date_in_secs_output if (@garbage);
                    push @true_successful_backups, $backups if(@garbage);
                    if ($cmd6_backup_date_in_secs_output > $cluster_date_minus_5_days_in_secs){
                        print "Backup that meets disaster recovery policy - of not more than 5 days old - found: $backups.\n" if ($verbose);
                        $i_have_dr_ok_backup +=1;
                    }

                } elsif ( $xtrabackup_info_qp_file_exists  ){
                    my $cmd5_capture_backup_date = "su - $ux_user  -c 'timeout 5 qpress -do $backups/xtrabackup_info.qp  | grep -i end_time   2> /dev/null'";
                    my $cmd5_capture_backup_date_output = `$cmd5_capture_backup_date`;
                    my @garbage = split /\s+/, $cmd5_capture_backup_date_output if ($cmd5_capture_backup_date_output);
                    my $cmd6 = "timeout 5 date --date='$garbage[2]' +%s";
                    my $cmd6_backup_date_in_secs_output = `$cmd6` if (@garbage);
                    $backups =~ s#\/\/#\/#;
                    $true_successful_backups{$backups} = $cmd6_backup_date_in_secs_output if (@garbage);
                    push @true_successful_backups, $backups if(@garbage);
                    if ($cmd6_backup_date_in_secs_output > $cluster_date_minus_5_days_in_secs){
                        print "Backup that meets disaster recovery policy - of not more than 5 days old - found: $backups.\n" if ($verbose);
                        $i_have_dr_ok_backup +=1;
                    }

                }


            }

            my $most_recent_backup_time=0;
            foreach my $element (keys %true_successful_backups)
            {
                if ($true_successful_backups{$element} > $most_recent_backup_time) {
                    $most_recent_backup = $element;
                    $most_recent_backup_time = $true_successful_backups{$element};
                }
            }
            print "Latest successful backup: $most_recent_backup.\n" if (($verbose) && ($most_recent_backup));


        }


        my $cmd4_check_if_am_in_active_use_output;
        if ($f5vip){
            $f5vip =~ s/\s+//g;
            # my $cmd4_check_if_am_in_active_use = "timeout 5 mysql -u $mysql_user -h$f5vip -p$mysql_pass --protocol=tcp -P$mysql_port -BNse 'select \@\@hostname' 2>/dev/null ";
            my $cmd4_check_if_am_in_active_use = "timeout 5 wget -qO-  http://bdbamon01.risk.regn.net:3000/f5/$f5vip 2>/dev/null ";
            $cmd4_check_if_am_in_active_use_output = `$cmd4_check_if_am_in_active_use`;
            $cmd4_check_if_am_in_active_use_output =~ s/\.(.*)$//  if ($cmd4_check_if_am_in_active_use_output);
            if ( ($cmd4_check_if_am_in_active_use_output) && ($cmd4_check_if_am_in_active_use_output =~ /$host/i) ) {
                my $message = "OK! Backups Disabled - MySQL on Port: $mysql_port, Host: $host is in active use.";
                $message = $message . " Latest successful backup: $most_recent_backup" if ($most_recent_backup);
                $check_mk_report .= "0 check_mysql_xtrabackup_port_${mysql_port} count=0.5 $message\n";
                next;
            } elsif ( ! $cmd4_check_if_am_in_active_use_output )
            {
                my $message = "UNKNOWN ERROR: Unable to check if node is active via f5vip - check that http://bdbamon01.risk.regn.net:3000/f5/$f5vip is reachable in a browser.";
                $message = $message . " Latest successful backup: $most_recent_backup" if ($most_recent_backup);
                $check_mk_report .= "3 check_mysql_xtrabackup_port_${mysql_port} count=0 $message\n";
                next;
            }
        }


        if ( $backup_install_date_in_sec >= $current_date_minus_x_days_in_secs  ) {
            my $message = "XtraBackup RPM newly installed: Allow for 48hrs to get realtime backup status!";
            $check_mk_report .= "0 check_mysql_xtrabackup_port_${mysql_port} count=0.5 $message\n";
            next;
        }

        if ($unable_to_open_backup_dir){
            print "Unable to list contents of backup directory: $backup_base.\n" if ($verbose);
            my $message = "UNKNOWN ERROR: Unable to list contents of backup directory - $backup_base. Check that this directory exists on host: $host";
            $check_mk_report .= "3 check_mysql_xtrabackup_port_${mysql_port} count=0 $message\n";
            next;
        }

        unless ($i_have_dr_ok_backup)
        {
            if (($f5vip) && ($cmd4_check_if_am_in_active_use_output)) {
                my $message = "CRITICAL: No True DR Certified Backup found - Any backup found is over 5 days old: ";
                $message .= 'Old Available backups: ' .  join( ' ',  keys( %true_successful_backups ) ) if  ( keys( %true_successful_backups )) ;
                $check_mk_report .= "2 check_mysql_xtrabackup_port_${mysql_port} count=0 $message\n";
            } else
            {
                my $message = "UNKNOWN ERROR: Unable to find a True DR Certified Backup - Any backup found is over 5 days old: ";
                $message .= 'Old Available backups: ' .  join( ' ',  keys( %true_successful_backups ) ) if  ( keys( %true_successful_backups )) ;
                $check_mk_report .= "3 check_mysql_xtrabackup_port_${mysql_port} count=0 $message\n";
            }
        }

        if ( $i_have_dr_ok_backup ) {
                    my $message = "OK! Certified True Backups Found - MySQL on Port: $mysql_port, Host: $host.";
                    $message = $message . " Latest successful backup: $most_recent_backup" if ($most_recent_backup);
                     $check_mk_report .= "0 check_mysql_xtrabackup_port_${mysql_port} count=1  $message\n";
                     next;
             }
    }
}

if (defined($check_mk_report)){
    print "$check_mk_report";
}


sub fnGetDate {
    my ($fnGD_format, $fnGD_time) = @_;
    my ($fnGD_sec, $fnGD_min, $fnGD_hour, $fnGD_mday, $fnGD_mon, $fnGD_year, $fnGD_wday, $fnGD_yday, $fnGD_isdst, $fnGD_return);
    $fnGD_time = time if (!defined $fnGD_time);
    print "DEBUG - \$fnGD_format: $fnGD_format\n" if ($verbose);
    print "DEBUG - \$fnGD_time: $fnGD_time\n" if ($verbose);
    if (!defined $fnGD_format) {
        $fnGD_return = localtime();
    } else {
        $fnGD_return = strftime $fnGD_format, localtime( $fnGD_time );
    }
    print "DEBUG - \$fnGD_return: $fnGD_return\n" if ($verbose);
    return $fnGD_return;
}
