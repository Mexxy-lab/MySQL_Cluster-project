#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
# Script to Patch MySQL
# Author: Ikechukwu Umejiofor
sleep 30;
# declare variables
$| = 1;      # flush to disk/file asap
my $var_file_fh;
my $file_open_failure_count = 0 ;
my $var_file='/etc/mysql_inventory/patch_mysql.flag';
# mysql_os_user_info='${sid}.${db_user}.${port}.patch_mysql_true'
my $i_see_valid_entry_in_flag_file = 0;
my %hash;
my $do_not_patch_mysql_notice_received = 0 ;
chomp(my $hostname =`hostname -s`);
my $log_file="/tmp/mysql_db_patch.$$";
my $log_file_handle_fh;
my $email_subject;
my $percona_packages;
my $mariadb_packages;
# my $cannot_find_startup_script;
# my $cannot_find_shutdown_script;
my $counter;
my $percona_packages_pipe_separated;
my $mariadb_packages_pipe_separated;


open $log_file_handle_fh, '>>', $log_file or $file_open_failure_count++;
if($file_open_failure_count) {
    $email_subject =  "[MySQL PATCHING ABORTED!] - Could not open file: $log_file - for logging: $!";
    print "$email_subject\n";
    &fail_and_send_email($log_file, $email_subject);
}

# Check if script is run with root privilege
if ($> != 0 ) {
    $email_subject = "[MySQL PATCHING ABORTED!] - This script [$0] must be run with sudo privileges";
    print  $log_file_handle_fh "$email_subject\n";
    print  "$email_subject\n";
    &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
}

open $var_file_fh, '<', $var_file or $file_open_failure_count++;
if($file_open_failure_count){
    $email_subject = "[MySQL PATCH ABORTED!] - Could not open file: $var_file - for variables extraction: $!";
    print  $log_file_handle_fh "$email_subject\n";
    print  "$email_subject\n";
    &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
}


while  (defined(my $line=<$var_file_fh>)) {
    chomp $line;
    # print("Line ==> $line\n");
    if ($line =~ m/\A\s*\#/) {
        next;
    }
    if ($line =~ m/\A\s+\Z/) {
        next;
    }
    $line =~ s/\A\s+//g;
    $line =~ s/\s+\Z//g;
    next unless (length $line);

    unless ($line =~ m/.*mysql_os_user_info=.*/i) {
        next;
    }

    $line =~ s/.*mysql_os_user_info=//ig;
    # variable $line should have content format:
    # '${sid}.${db_user}.${port}.patch_mysql_true'
    # OR
    # '${sid}.${db_user}.${port}.patch_mysql_false'
    $line =~ s/\'//g;
    $line =~ s/\"//g;
    my @tmp_array;
    @tmp_array = split /\./, $line;
    my ${sid} = $tmp_array[0];
    $sid =~ s/\A\s+//g;
    $sid =~ s/\s+\Z//g;

    my $db_user = $tmp_array[1];
    $db_user =~ s/\A\s+//g;
    $db_user =~ s/\s+\Z//g;

    my $port = $tmp_array[2];
    $port =~ s/\A\s+//g;
    $port =~ s/\s+\Z//g;

    my $to_patch_or_not_to_patch = lc $tmp_array[3];
    $to_patch_or_not_to_patch =~ s/\A\s+//g;
    $to_patch_or_not_to_patch =~ s/\s+\Z//g;

    @{$hash{$sid}} = ($db_user,$port,$to_patch_or_not_to_patch);
    if ( (length $sid) && (length $db_user) && (length $port) && (length $to_patch_or_not_to_patch)){
        $i_see_valid_entry_in_flag_file++;
        if ($to_patch_or_not_to_patch  =~ m/.*patch_mysql_false.*/) {
            $do_not_patch_mysql_notice_received++;
        }
    }

}

close $var_file_fh;

if ($do_not_patch_mysql_notice_received) {
    $email_subject = "[MySQL PATCHING ABORTED] - Instruction in File: [$var_file] says no patching MySQL on this host: [$hostname]";
    print  $log_file_handle_fh "$email_subject\n";
    print  "$email_subject\n";
    &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
}

unless($i_see_valid_entry_in_flag_file){
    $email_subject =  "[MySQL PATCH ABORTED] - Unable to extract valid Patch Instruction in File: [$var_file] on this host: [$hostname]";
    print  $log_file_handle_fh "$email_subject\n";
    print  "$email_subject\n";
    &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
}


if( `yum list installed | grep -i Perco |  /bin/awk  \'{print \$1}\' | grep -i Perco `){
    chomp ($percona_packages = `yum list installed | grep -i Perco |  /bin/awk  \'{print \$1}\' | grep -i Perco | tr \"\n\" \" \"  | sed  \'s/.\$//\'  `);
    chomp ($percona_packages_pipe_separated = `yum list installed | grep -i Perco |  /bin/awk  \'{print \$1}\' | grep -i Perco | tr \"\n\" \"|\"  | sed  \'s/.\$//\'  `);
}

if( `yum list installed | grep -i maria |  /bin/awk  \'{print \$1}\' | grep -i maria `){
    chomp ($mariadb_packages = `yum list installed | grep -i maria |  /bin/awk  \'{print \$1}\' | grep -i maria | tr \"\n\" \" \"  | sed  \'s/.\$//\'  `);
    chomp ($mariadb_packages_pipe_separated = `yum list installed | grep -i maria |  /bin/awk  \'{print \$1}\' | grep -i maria | tr \"\n\" \"|\"  | sed  \'s/.\$//\'  `);
}

chomp (my $mysql_version_before_patching = `mysqld --version 2> /dev/null  | /bin/awk  \'{print \$3}\' `);
print $log_file_handle_fh "Current version of MySQL before commencing auto patch is ====> $mysql_version_before_patching\n";
print  "Current version of MySQL before commencing auto patch is ====> $mysql_version_before_patching\n";


if ($percona_packages) {
    # Query for the Right Percona Repo
    chomp(my $yum_output_0 = `yum repolist all | grep -i Frozen-MT-percona`);
    chomp(my $yum_output_1 = `yum repolist all | grep -i percona-release-x86_64`);
    # chomp(my $yum_repolist_output_2 = `yum repolist all | grep -i MT-percona` );
    print $log_file_handle_fh "Checking for available Percona Packages for Updates - host - $hostname: $percona_packages\n";
    print "Checking for available Percona Packages for Updates - host - $hostname: $percona_packages\n";
    if ($yum_output_0) {
        chomp(my $yum_output_2 = `yum  list available  --enablerepo=Frozen-MT-percona   |  grep -P  \'$percona_packages_pipe_separated\' `);
        if ($?) {
            $email_subject = "[YUM - MySQL Search For Available Patch] - No NEW Patch Available for MySQL - [$hostname]";
            print $log_file_handle_fh "$email_subject\n";
            print $log_file_handle_fh "$yum_output_2\n";
            print "$email_subject\n";
            &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
        }
    }
    elsif ($yum_output_1) {
        chomp(my $yum_output_2 = `yum  list available  --enablerepo=percona-release-x86_64   |  grep -P  \'$percona_packages_pipe_separated\' `);
        if ($?) {
            $email_subject = "[YUM - MySQL Search For Available Patch] - No NEW Patch Available for MySQL - [$hostname]";
            print $log_file_handle_fh "$email_subject\n";
            print $log_file_handle_fh "$yum_output_2\n";
            print "$email_subject\n";
            &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
        }
    }
    else {
        chomp(my $yum_output_2 = `yum  list available  --enablerepo=MT-percona  |  grep -P  \'$percona_packages_pipe_separated\' `);
        if ($?) {
            $email_subject = "[YUM - MySQL Search For Available Patch] - No NEW Patch Available for MySQL - [$hostname]";
            print $log_file_handle_fh "$email_subject\n";
            print $log_file_handle_fh "$yum_output_2\n";
            print "$email_subject\n";
            &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
        }
    }
}

unless ($percona_packages) {
    if ($mariadb_packages) {
        # Query for the Right MariaDB Repo
        chomp(my $yum_output_0 = `yum repolist all | grep -i Frozen-MT-mariadb`);
        chomp(my $yum_output_1 = `yum repolist all | grep -i mariadb`);
        print $log_file_handle_fh "Checking for available MariaDB Packages for Updates - host - $hostname: $mariadb_packages\n";
        print "Checking for available MariaDB Packages for Updates - host - $hostname: $mariadb_packages\n";
        if ($yum_output_0) {
            chomp(my $yum_output_2 = `yum  list available  --enablerepo=Frozen-MT-percona  |  grep -P  \'$mariadb_packages_pipe_separated\'   `);
            if ($?) {
                $email_subject = "[YUM - MySQL Search For Available Patch] - No NEW Patch Available for MySQL - [$hostname]";
                print $log_file_handle_fh "$email_subject\n";
                print $log_file_handle_fh "$yum_output_2\n";
                print "$email_subject\n";
                &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
            }
        }
        elsif ($yum_output_1) {
            chomp(my $yum_output_2 = `yum  list available   --enablerepo=mariadb  |  grep -P  \'$mariadb_packages_pipe_separated\'  `);
            if ($?) {
                $email_subject = "[YUM - MySQL Search For Available Patch] - No NEW Patch Available for MySQL - [$hostname]";
                print $log_file_handle_fh "$email_subject\n";
                print $log_file_handle_fh "$yum_output_2\n";
                print "$email_subject\n";
                &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
            }
        }
        else {
            chomp(my $yum_output_2 = `yum  list available   |  grep -P  \'$mariadb_packages_pipe_separated\'  `);
            if ($?) {
                $email_subject = "[YUM - MySQL Search For Available Patch] - No NEW Patch Available for MySQL - [$hostname]";
                print $log_file_handle_fh "$email_subject\n";
                print $log_file_handle_fh "$yum_output_2\n";
                print "$email_subject\n";
                &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
            }
        }

    }
}



# Shutdown MySQL IF still Running
foreach my $sid(keys %hash)
{
    next unless ($hash{$sid});
    my @tmp_array = @{$hash{$sid}};
    my $user = $tmp_array[0];
    my $port = $tmp_array[1];
    print $log_file_handle_fh "SID - $sid  ==> Os User ==> $user   && PORT ==>  $port \n";
    # chomp(my $capture_pass =`su -l - $user  -c \" source ~$user/.profile > /dev/null 2>&1  &&  echo \$SOCKET_FILE  2> /dev/null  \" `);
    # chomp(my $capture_socket =`su -l - $user  -c \" source ~$user/.profile > /dev/null 2>&1  &&  cat \$CFG_LOC/.pswd   2> /dev/null \" `);
    chomp(my $capture_socket =`su -l - $user  -c \" source ~$user/.profile > /dev/null 2>&1  &&  echo \\\$SOCKET_FILE  2> /dev/null  \" `);
    chomp(my $capture_pass =`su -l - $user  -c \" source ~$user/.profile > /dev/null 2>&1  &&  cat \\\$CFG_LOC/.pswd   2> /dev/null \" `);
    chomp(my $capture_myroot=`su -l - $user  -c \" source ~$user/.profile > /dev/null 2>&1  &&  alias myroot | tr -d \\' | /bin/awk  -F\'=\' \'{print \\\$2}\' \" `);
    if (  ($capture_pass) &&  ($capture_socket) ) {
            $capture_myroot="mysql  -uroot  -h localhost  -p$capture_pass   -S $capture_socket ";
    }

    chomp(my $mysql_upgrade_command=`echo $capture_myroot |  sed    \'s/.*-uroot/mysql_upgrade -h localhost  --skip-version-check --skip-write-binlog --upgrade-system-tables  --force -uroot/\'  `);
    chomp(my $capture_shutdown_script=`su -l - $user  -c \" source ~$user/.profile > /dev/null 2>&1  &&  which shutdown.sh  2> /dev/null \"`);
    chomp(my $capture_startup_script=`su -l - $user  -c \" source ~$user/.profile > /dev/null 2>&1  &&  which startup.sh  2> /dev/null \"`);
    print $log_file_handle_fh "MYROOT is ====> $capture_myroot\n";
    print $log_file_handle_fh "mysql_upgrade command is ====> $mysql_upgrade_command\n";
    print $log_file_handle_fh "shutdown_script is ====> $capture_shutdown_script\n";
    print $log_file_handle_fh "startup_script is ====> $capture_startup_script\n";

    unless(-e $capture_shutdown_script){
        my $sid_uppercase = uc $sid;
        my $alternate_shutdown_script_1 = "~$user/$sid_uppercase/bin/shutdown.sh";
        chomp(my $alternate_shutdown_script_2 =`su -l - $user  -c \" source ~$user/.profile > /dev/null 2>&1  &&  echo $alternate_shutdown_script_1 \"`);
        if (-e $alternate_shutdown_script_2 ) {
            $capture_shutdown_script = $alternate_shutdown_script_2;
        }
   }

    unless(-e $capture_shutdown_script){
        $email_subject =  "[MySQL PATCH ABORTED] - Unable to locate MySQL Shutdown Script for MySQL Service: SID - $sid  ==> Os User ==> $user   && PORT ==>  $port - [$hostname]";
        print  $log_file_handle_fh "$email_subject\n";
        print  "$email_subject\n";
        &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
    }

    unless(-e $capture_startup_script){
        my $sid_uppercase = uc $sid;
        my $alternate_startup_script_1 = "~$user/$sid_uppercase/bin/startup.sh";
        chomp(my $alternate_startup_script_2 =`su -l - $user  -c \" source ~$user/.profile > /dev/null 2>&1  &&  echo $alternate_startup_script_1 \"`);
        if (-e $alternate_startup_script_2 ) {
           $capture_startup_script = $alternate_startup_script_2;
        }
    }


    unless(-e $capture_startup_script){
        $email_subject =  "[MySQL PATCH ABORTED] - Unable to locate MySQL Startup Script for MySQL Service: SID - $sid  ==> Os User ==> $user   && PORT ==>  $port - [$hostname]";
        print  $log_file_handle_fh "$email_subject\n";
        print  "$email_subject\n";
        &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
    }
    push ( @{$hash{$sid}} , $capture_shutdown_script);
    push ( @{$hash{$sid}} , $capture_startup_script);
    push ( @{$hash{$sid}} , $mysql_upgrade_command);
    push ( @{$hash{$sid}} , $percona_packages ) if ($percona_packages);
    push ( @{$hash{$sid}} , $mariadb_packages ) if ($mariadb_packages);

    print  $log_file_handle_fh "Shutting Down MySQL Service with SID - $sid  ==> Os User ==> $user   && PORT ==>  $port - [$hostname]\n";
    my $lowercase_sid = lc $sid;
    chomp(my $service_script_shutdown_output =`service $lowercase_sid  stop`);
    print  $log_file_handle_fh "$service_script_shutdown_output\n";
    chomp(my $capture_shutdown_output=`su -l - $user  -c \" source ~$user/.profile > /dev/null 2>&1  && bash -x $capture_shutdown_script \"`);
    print  $log_file_handle_fh "$capture_shutdown_output\n";

    $counter=0;
    # we wait for at most 240sec for MySQL Server to shutdown
    while( (`timeout 1 bash -c "</dev/tcp/localhost/$port" && echo Port open. || echo Port closed.` =~ m/open/i) && ($counter < 48)){
        print $log_file_handle_fh "SID - $sid  ==> Os User ==> $user   && PORT ==>  $port - [$hostname] - Checking for open port count: $counter\n";
        sleep 5;
        $counter++;
    }
    $counter=0;

    unless(`timeout 1 bash -c "</dev/tcp/localhost/$port" && echo Port open. || echo Port closed.` =~ m/closed/i){
        $email_subject =  "[MySQL PATCH ABORTED] - Unable to Gracefully Shutdown MySQL with SID - $sid  ==> Os User ==> $user   && PORT ==>  $port - [$hostname]";
        print  $log_file_handle_fh "$email_subject\n";
        print  "$email_subject\n";
        &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
    }

}

# Start Actual Patching:
if ($percona_packages) {
    # Query for the Right Percona Repo
    chomp(my $yum_output_0 = `yum repolist all | grep -i Frozen-MT-percona` );
    chomp(my $yum_output_1 = `yum repolist all | grep -i percona-release-x86_64` );
    # chomp(my $yum_repolist_output_2 = `yum repolist all | grep -i MT-percona` );
    print $log_file_handle_fh "Updating packages on host - $hostname: $percona_packages\n";
    print  "Updating packages on host - $hostname: $percona_packages\n";
    if ($yum_output_0) {
        chomp(my $yum_output_2 = `yum -y update $percona_packages   --nogpgcheck    --enablerepo=Frozen-MT-percona` );
        if ($?) {
            $email_subject =  "[MySQL YUM UPDATE FAILED] - YUM Failed with non-zero exit code - [$hostname]";
            print $log_file_handle_fh "$email_subject\n";
            print $log_file_handle_fh "$yum_output_2\n";
            print  "$email_subject\n";
            &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
        } else{
            $email_subject =  "[MySQL YUM UPDATE COMPLETED SUCCESSFULLY] - YUM Completed Successfully with zero exit code - [$hostname]";
            print $log_file_handle_fh "$email_subject\n";
            print  "$email_subject\n";
        }
    }
    elsif ($yum_output_1) {
        chomp(my $yum_output_2 = `yum -y update $percona_packages   --nogpgcheck    --enablerepo=percona-release-x86_64` );
        if ($?) {
            $email_subject =  "[MySQL YUM UPDATE FAILED] - YUM Failed with non-zero exit code - [$hostname]";
            print $log_file_handle_fh "$email_subject\n";
            print $log_file_handle_fh "$yum_output_2\n";
            print  "$email_subject\n";
            &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
        } else{
            $email_subject =  "[MySQL YUM UPDATE COMPLETED SUCCESSFULLY] - YUM Completed Successfully with zero exit code - [$hostname]";
            print $log_file_handle_fh "$email_subject\n";
            print  "$email_subject\n";
        }
    } else{
        chomp(my $yum_output_2 = `yum -y update $percona_packages   --nogpgcheck    --enablerepo=MT-percona` );
        if ($?) {
            $email_subject =  "[MySQL YUM UPDATE FAILED] - YUM Failed with non-zero exit code - [$hostname]";
            print $log_file_handle_fh "$email_subject\n";
            print $log_file_handle_fh "$yum_output_2\n";
            print  "$email_subject\n";
            &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
        } else{
            $email_subject =  "[MySQL YUM UPDATE COMPLETED SUCCESSFULLY] - YUM Completed Successfully with zero exit code - [$hostname]";
            print $log_file_handle_fh "$email_subject\n";
            print  "$email_subject\n";
        }
    }
}


if ($mariadb_packages){
    # Query for the Right MariaDB Repo
    chomp(my $yum_output_0 = `yum repolist all | grep -i Frozen-MT-mariadb` );
    chomp(my $yum_output_1 = `yum repolist all | grep -i mariadb` );
    print $log_file_handle_fh "Updating MariaDB packages on host - $hostname: $mariadb_packages\n";
    print  "Updating packages on host - $hostname: $mariadb_packages\n";
    if ($yum_output_0) {
        chomp(my $yum_output_2 = `yum -y update $mariadb_packages   --nogpgcheck    --enablerepo=Frozen-MT-mariadb` );
        if ($?) {
            $email_subject =  "[MySQL/MariaDB YUM UPDATE FAILED] - YUM Failed with non-zero exit code - [$hostname]";
            print $log_file_handle_fh "$email_subject\n";
            print $log_file_handle_fh "$yum_output_2\n";
            print  "$email_subject\n";
            &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
        } else{
            $email_subject =  "[MySQL YUM UPDATE COMPLETED SUCCESSFULLY] - YUM Completed Successfully with zero exit code - [$hostname]";
            print $log_file_handle_fh "$email_subject\n";
            print  "$email_subject\n";
        }
    }
    elsif ($yum_output_1) {
        chomp(my $yum_output_2 = `yum -y update $mariadb_packages    --nogpgcheck    --enablerepo=mariadb` );
        if ($?) {
            $email_subject =  "[MySQL/MariaDB YUM UPDATE FAILED] - YUM Failed with non-zero exit code - [$hostname]";
            print $log_file_handle_fh "$email_subject\n";
            print $log_file_handle_fh "$yum_output_2\n";
            print  "$email_subject\n";
            &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
        } else{
            $email_subject =  "[MySQL YUM UPDATE COMPLETED SUCCESSFULLY] - YUM Completed Successfully with zero exit code - [$hostname]";
            print $log_file_handle_fh "$email_subject\n";
            print  "$email_subject\n";
        }
    } else{
        chomp(my $yum_output_2 = `yum -y update   --nogpgcheck    $mariadb_packages` );
        if ($?) {
            $email_subject =  "[MySQL/MariaDB YUM UPDATE FAILED] - YUM Failed with non-zero exit code - [$hostname]";
            print $log_file_handle_fh "$email_subject\n";
            print $log_file_handle_fh "$yum_output_2\n";
            print  "$email_subject\n";
            &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
        } else{
            $email_subject =  "[MySQL YUM UPDATE COMPLETED SUCCESSFULLY] - YUM Completed Successfully with zero exit code - [$hostname]";
            print $log_file_handle_fh "$email_subject\n";
            print  "$email_subject\n";
        }
    }


    ############
    print $log_file_handle_fh "Updating packages on host - $hostname: $mariadb_packages\n";
    print "Updating packages on host - $hostname: $mariadb_packages\n";
    #chomp(my $yum_output_2 = `` );
}


# Startup MySQL after patching was successful
foreach my $sid(keys %hash) {
    next unless ($hash{$sid});
    my @tmp_array = @{$hash{$sid}};
    my $user = $tmp_array[0];
    my $port = $tmp_array[1];
    my $capture_shutdown_script = $tmp_array[3];
    my $capture_startup_script =  $tmp_array[4];
    my $mysql_upgrade_command = $tmp_array[5];
    $percona_packages = $tmp_array[6];
    $mariadb_packages  = $tmp_array[7];

    # print "capture_shutdown_script ===> $capture_shutdown_script \n";
    # print "capture_startup_script ===> $capture_startup_script \n";
    # print "mysql_upgrade_command ===> $mysql_upgrade_command \n";
    # print "percona_packages ===> $percona_packages \n" if ($percona_packages);
    # print "mariadb_packages ===> $mariadb_packages \n" if ($mariadb_packages);

    # Shut down the server if the server is running for any reason
    print  $log_file_handle_fh "[Before mysql_upgrade Script Run ] : Ensure Shutdown of MySQL Service with SID - $sid  ==> Os User ==> $user   && PORT ==>  $port - [$hostname]\n";
    print  "[Before mysql_upgrade Script Run ] : Ensure Shutdown of MySQL Service with SID - $sid  ==> Os User ==> $user   && PORT ==>  $port - [$hostname]\n";
    my $lowercase_sid = lc $sid;
    chomp(my $service_script_shutdown_output =`service $lowercase_sid  stop`);
    print  $log_file_handle_fh "$service_script_shutdown_output\n";
    unless(`timeout 1 bash -c "</dev/tcp/localhost/$port" && echo Port open. || echo Port closed.` =~ m/closed/i){
        chomp(my $capture_shutdown_output=`su -l - $user  -c \" source ~$user/.profile > /dev/null 2>&1  && bash -x $capture_shutdown_script \"`);
        print  $log_file_handle_fh "$capture_shutdown_output\n";
    }
    $counter=0;
    # we wait for at most 240sec for MySQL Server to shutdown
    while( (`timeout 1 bash -c "</dev/tcp/localhost/$port" && echo Port open. || echo Port closed.` =~ m/open/i) && ($counter < 48)){
        print $log_file_handle_fh "SID - $sid  ==> Os User ==> $user   && PORT ==>  $port - [$hostname] - Checking for open port count: $counter\n";
        sleep 5;
        $counter++;
    }
    $counter=0;

    unless(`timeout 1 bash -c "</dev/tcp/localhost/$port" && echo Port open. || echo Port closed.` =~ m/closed/i){
        $email_subject =  "[MySQL PATCH ABORTED - Before mysql_upgrade Script Run] - Unable to Gracefully Shutdown MySQL with SID - $sid  ==> Os User ==> $user   && PORT ==>  $port - [$hostname]";
        print  $log_file_handle_fh "$email_subject\n";
        print  "$email_subject\n";
        &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
    }


    # Startup the server:
    print  $log_file_handle_fh "Starting up MySQL Service with SID - $sid  ==> Os User ==> $user   && PORT ==>  $port - [$hostname]\n";
    print  "Starting up MySQL Service with SID - $sid  ==> Os User ==> $user   && PORT ==>  $port - [$hostname]\n";
    chomp(my $service_script_startup_output =`service $lowercase_sid  start`);
    print  $log_file_handle_fh "$service_script_startup_output\n";
    unless(`timeout 1 bash -c "</dev/tcp/localhost/$port" && echo Port open. || echo Port closed.` =~ m/open/i){
       chomp(my $capture_startup_output=`su -l - $user  -c \" source ~$user/.profile > /dev/null 2>&1  && bash -x $capture_startup_script \"`);
       print  $log_file_handle_fh "$capture_startup_output\n";
    }
    $counter=0;
    # we wait for at most 240sec for MySQL Server to startup
    while( (`timeout 1 bash -c "</dev/tcp/localhost/$port" && echo Port open. || echo Port closed.` =~ m/closed/i) && ($counter < 48)){
        print $log_file_handle_fh "SID - $sid  ==> Os User ==> $user   && PORT ==>  $port - [$hostname] - Checking for open port count: $counter\n";
        sleep 5;
        $counter++;
    }
    $counter=0;
    unless(`timeout 1 bash -c "</dev/tcp/localhost/$port" && echo Port open. || echo Port closed.` =~ m/open/i){
        $email_subject =  "[MySQL PATCH FAILED] - Unable to Startup MySQL After Patching: SID - $sid  ==> Os User ==> $user   && PORT ==>  $port - [$hostname]";
        print  $log_file_handle_fh "$email_subject\n";
        print  "$email_subject\n";
        &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
    }

    # run mysql_upgrade script:
    print  $log_file_handle_fh "Running mysql_upgrade Script on system tables ONLY! for MySQL Service with SID - $sid  ==> Os User ==> $user   && PORT ==>  $port - [$hostname]\n";
    # chomp(my $capture_mysql_upgrade_output = `$mysql_upgrade_command`);
    chomp(my $capture_mysql_upgrade_output = `su -l - $user  -c \" source ~$user/.profile > /dev/null 2>&1  &&  $mysql_upgrade_command \"`);
    if ($?) {
            $email_subject =  "[MySQL Upgrade Script Run FAILED] - Failed with non-zero exit code: SID - $sid  ==> Os User ==> $user   && PORT ==>  $port- [$hostname]";
            print $log_file_handle_fh "$email_subject\n";
            print $log_file_handle_fh "$capture_mysql_upgrade_output\n";
            print  "$email_subject\n";
            &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
        } else{
            $email_subject =  "[MySQL Upgrade Script Run COMPLETED SUCCESSFULLY] - SID - $sid  ==> Os User ==> $user   && PORT ==>  $port- [$hostname]";
            print $log_file_handle_fh "$email_subject\n";
            print  "$email_subject\n";
        }


}

#chomp ($mysql_version_before_patching = `mysqld --version 2> /dev/null  | /bin/awk  \'{print \$3}\' `);
chomp (my $mysql_version_after_patching = `mysqld --version 2> /dev/null  | /bin/awk  \'{print \$3}\' `);
chomp (my $mysql_version_after_patching_long = `mysqld --version 2> /dev/null  `);

if ($mysql_version_before_patching ne $mysql_version_after_patching) {
    $email_subject =  "[MySQL Auto-Patch Completed SUCCESSFULLY on Host - $hostname]: MySQL Went From Version - $mysql_version_before_patching to $mysql_version_after_patching";
    print $log_file_handle_fh "$email_subject\n";
    print  "$email_subject\n";
    &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
} else{
    $email_subject =  "[MySQL Auto-Patch Completed SUCCESSFULLY on Host - $hostname]: No Patch Available at this time - Current Version: $mysql_version_after_patching_long";
    print $log_file_handle_fh "$email_subject\n";
    print  "$email_subject\n";
    &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);
}

# $email_subject =  "[MySQL Upgrade Completed SUCCESSFULLY on Host - $hostname]";
# print $log_file_handle_fh "$email_subject\n";
# print  "$email_subject\n";
# &fail_and_send_email($log_file, $email_subject, $log_file_handle_fh);

# chomp (my $out=`cat $log_file`);
# print "$out\n";
# unlink $log_file;

sub fail_and_send_email(){
    # this sub-routine takes 4 arguments:
    # 1st argument is the logfile.
    # 2nd argument is the Subject of email
    # 3rd argument is log file handle if opened
    # 4th argument is the email address to sent log file contents to.
    chomp(my $hostname_2 =`hostname -s`);
    my $log_file_2 = $_[0];
    my $email_subject_2 = $_[1];
    my $fh = $_[2];
    my $email = $_[3];
    unless($email){
        $email = 'dbamail@macetron.com';
        # $email = 'Ikechukwu.Umejiofor@macetron.com';
    }
    if ($fh) {
        close($fh);
    }
    if (-e $log_file_2) {
        `cat $log_file_2  | mail -s "[MT DB Auto Patch] - $email_subject_2 - [ $hostname_2 ]" $email`;
      # unlink $log_file_2;
    } else {
        `mail -s "[MT DB Auto Patch] - $email_subject_2 - [ $hostname_2 ]" $email`;
    }
    exit(0);
}


