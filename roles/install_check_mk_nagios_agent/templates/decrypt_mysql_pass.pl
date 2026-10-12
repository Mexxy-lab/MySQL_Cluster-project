#! /usr/bin/perl -w
    eval 'exec /usr/bin/perl -S $0 ${1+"$@"}'
        if 0; #$running_under_some_shell
# WARNING: This file is managed by ansible. Manual changes to this file will/may be overwritten.
#AUTHOR                 =  IKECHUKWU MACDAVID UMEJIOFOR (MAJOR)
#EMAIL                  =  mailmajor01@gmail.com
#DATE                   =  29 February 2016
#PHONE                  =  07867430002
#SCRIPT/FILE PURPOSE    =  Nagios Plugin Auxilliary Script
#SCRIPT LOCATION        = '/usr/lib/check_mk_agent_aux_scripts/decrypt_mysql_pass.pl'
use strict;
use warnings FATAL => 'all';
use MIME::Base64;
use Crypt::Blowfish;

my $g_key = decode_base64('{{ db_key }}');

## decrypt_text
sub decrypt_text {
    my $encrypted_text = $_[0];

    my (@encrypted_chunks, $encrypted_chunk, $plain_text);

    $plain_text = "";
    @encrypted_chunks = ($encrypted_text =~ /.{1,16}/g); # Chop any size of the text into up to 16 charachers and put each chunk into an array

    foreach $encrypted_chunk (@encrypted_chunks) {
        $plain_text = sprintf( "%s%s", $plain_text, decrypt_8_chars( $encrypted_chunk ) );
    }

    return $plain_text;
} # decrypt_text

## decrypt_8_chars 
sub decrypt_8_chars {
    my ($encrypted_text) = @_;

    my ($encrypted_data, $plain_text, $cipher);

    $cipher = new Crypt::Blowfish $g_key;
    $encrypted_data = pack( "H16", $encrypted_text );

    $plain_text = $cipher->decrypt( $encrypted_data );
    $plain_text =~ s/\0//g; # Shrink the string by removing appended with NULL characters

    return $plain_text;
}    #decrypt_8_chars


Main: {
    my ($plaintext, $ciphertext );
    # my ($plaintext);                       # testing and debugging
    $ciphertext = shift;

    die "***Err: Main() Provide keyphrase\n\n", printUsage()
        unless defined( $ciphertext );

    $plaintext = decrypt_text( $ciphertext );
    print "$plaintext\n";

    #  $ciphertext = encrypt_text($plaintext);
}    #Main

##########################
# print Usage
##########################
sub printUsage {
    print <<__Usage__;
usage:
  perl $0 <keyphrase>
__Usage__
    exit;
}   #printUsage

