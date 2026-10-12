#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
# use YAML::XS 'LoadFile';

$| = 1;
my $key_var_file_fh;
my $key_var_file='metadata_test.cnf';
open $key_var_file_fh, '<', $key_var_file or die "Could not open file: $key_var_file - for variables extract: $!";
# my $db_port;

my %hash;
my $ansible_role;

while  (defined(my $line=<$key_var_file_fh>))
{
    chomp $line;
    # print("Line ==> $line\n");
    if ($line =~ m/\A\s*\#/){
        next;
    }
    if ($line =~ m/\A\s+\Z/){
        next;
    }
    $line =~ s/\A\s+//g;
    $line =~ s/\s+\Z//g;
    next unless (length $line);


    if ($line =~ m/\s*\[\s*\w+/)
    {
        $line =~ s/\A\s+//g;
        $line =~ s/\s+\Z//g;
        $line =~ s/\[//g;
        $line =~ s/\A\s+//g;
        $line =~ s/\].*\Z//g;
        $line =~ s/\s+\Z//g;
        $ansible_role = $line;
        # print "I see ansible role: $ansible_role\n";
        next if ( (  $ansible_role =~ m/\s*setup_mysql_replication\s*/ ) and  ( $hash{'setup_mysql_replication'})    );
        $hash{$ansible_role} =qw();
        next;
        # $hash{$line} =
    }
    $line =~ s/\s+\#.*\Z//g;
    $line =~ s/\s*\=\s*/:/;
    # print("Line ==> $line\n");
    push( @{$hash{$ansible_role}},  $line );

    if ( $line =~ m/\s*db_port\s*/ )
    {
      $line =~ s/\s*db_port\s*/port/g;
      $hash{ 'setup_mysql_replication' } = qw() unless ( exists  $hash{'setup_mysql_replication'})  ;
      push( @{$hash{ 'setup_mysql_replication' }} ,  $line ) if ( exists  $hash{'setup_mysql_replication'});
    }

    next;
}

close $key_var_file_fh;

foreach my $role_name(keys %hash)
{
    # print("For Role: $role_name - we have the following custom variables to inject into the ansible run:\n") if ($hash{$role_name});
    next unless ($hash{$role_name});
    my $vars_file_path = join( '/',  "roles", ${role_name} ,"vars", "main.yml");
    # print "var file to edit: $vars_file_path\n";
    open my $append_to_var_file_fh, '>>',  $vars_file_path or die "Could not open file: $vars_file_path for custom variables loading: $!";
    my @output=("\n#-----------------------\n# Custom Variables Below \n#-----------------------\n");
    foreach my $key_var (@{$hash{$role_name}})
    {
        my($key, $values) = split/\:/, $key_var;
        if (length($values)){
            if ($values =~ m/\;/){
                $values =~ s/\"//g;
                $values =~ s/\'//g;
                #print"    For Key: $key - we have values\n";
                push( @output, "\n$key:\n");
                # print $append_to_var_file_fh "\n$key:\n";
                # print  "$key:\n";
                my @array = split /\;/, $values;
                push( @output, "  - '$_'\n") foreach(@array);
                # print $append_to_var_file_fh "  - '$_'\n" foreach(@array);
                # print  "  - '$_'\n" foreach(@array);
                next;
            }
            $key_var =~ s/\:/: /;
            push( @output, "$key_var\n");
            # print $append_to_var_file_fh "$key_var\n";
            # print  "$key_var\n";
        }
    }
    if (@output > 1 )
    {
        print $append_to_var_file_fh "$_" foreach @output;
        print "Vars File: '$vars_file_path' has been Modified!\n";
    }
    close $append_to_var_file_fh;
}

`bash generate_mysql_ssl_certs_with_expiry_date.sh`