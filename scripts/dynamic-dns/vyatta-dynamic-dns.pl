#!/usr/bin/perl
#
# Module: vyatta-dynamic-dns.pl
#
# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2008 Vyatta, Inc.
# All Rights Reserved.
#
# Author: Mohit Mehta
# Date: September 2008
# Description: Script to run ddclient per interface as set in Vyatta CLI
#
# **** End License ****
#

use lib "/opt/vyatta/share/perl5/";
use Vyatta::Config;
use Vyatta::Misc;
use Getopt::Long;

use strict;
use warnings;

my $ddclient_run_dir = '/var/run/ddclient';
my $ddclient_cache_dir = '/var/cache/ddclient';
my $ddclient_config_dir = '/etc/ddclient';

#
# main
#

my ($update_dynamicdns, $op_mode_update_dynamicdns, $stop_dynamicdns, $interface);

GetOptions(
    "update-dynamicdns!"            => \$update_dynamicdns,
    "stop-dynamicdns!"              => \$stop_dynamicdns,
    "op-mode-update-dynamicdns!"    => \$op_mode_update_dynamicdns,
    "interface=s"                   => \$interface
);

if (defined $update_dynamicdns) {
    my $config;
    $config  = dynamicdns_get_constants();
    $config .= dynamicdns_get_values();
    dynamicdns_write_file($config);
    dynamicdns_restart();
}

dynamicdns_restart() if (defined $op_mode_update_dynamicdns);
dynamicdns_stop()    if (defined $stop_dynamicdns);

exit 0;

#
# subroutines
#

sub dynamicdns_restart {
    dynamicdns_stop();
    dynamicdns_start();
}

sub dynamicdns_start {
    mkdir $ddclient_run_dir
        unless (-d $ddclient_run_dir);
    mkdir $ddclient_cache_dir
        unless (-d $ddclient_cache_dir);

    system("/usr/sbin/ddclient -file $ddclient_config_dir/ddclient_$interface.conf >&/dev/null");

}

sub dynamicdns_stop {
    system("kill -9 `cat $ddclient_run_dir/ddclient_$interface.pid 2>/dev/null` >&/dev/null");
    system("rm -f $ddclient_cache_dir/ddclient_$interface.cache >&/dev/null");
}

sub dynamicdns_get_constants {
    my $output;

    my $date = `date`;
    chomp $date;
    $output  = "#\n# autogenerated by vyatta-dynamic-dns.pl on $date\n#\n";
    $output .= "daemon=1m\n";
    $output .= "syslog=yes\n";
    $output .= "ssl=yes\n";
    $output .= "pid=$ddclient_run_dir/ddclient_$interface.pid\n";
    $output .= "cache=$ddclient_cache_dir/ddclient_$interface.cache\n";
    $output .= "use=if, if=$interface\n\n\n";
    return $output;
}

sub dynamicdns_get_values {

    my $output = '';
    my $config = new Vyatta::Config;
    $config->setLevel("service dns dynamic interface $interface");

    my @services = $config->listNodes("service");
    foreach my $service (@services) {
        $config->setLevel("service dns dynamic interface $interface service $service");
        $service="freedns" if ($service eq "afraid");
        $service="dslreports1" if ($service eq "dslreports");
        $service="dyndns2" if ($service eq "dyndns");
        $service="zoneedit1" if ($service eq "zoneedit");
        my $login = $config->returnValue("login");
        my $password = $config->returnValue("password");
        my @hostnames = $config->returnValues("host-name");
        my $server = $config->returnValue("server");

        foreach my $hostname (@hostnames) {
            $output .= "server=$server," if defined $server;
            $output .= "protocol=$service\n";
            $output .= "max-interval=28d\n";
            $output .= "login=$login\n";
            $output .= "password='$password'\n";
            $output .= "$hostname\n\n";
        }
    }

    return $output;
}

sub dynamicdns_write_file {
    my ($config) = @_;

    mkdir $ddclient_config_dir
        unless (-d $ddclient_config_dir);

    open(my $fh, '>', "$ddclient_config_dir/ddclient_$interface.conf")
        || die "Couldn't open \"$ddclient_config_dir/ddclient_$interface.conf\" - $!";
    print $fh $config;
    close $fh;
}

