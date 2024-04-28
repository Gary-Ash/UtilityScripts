#!/usr/bin/env perl
#*****************************************************************************************
# load-simulator.pl
#
# This script will restore the state of the iOS simulator
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  28-Apr-2024  10:00pm
# Modified :
#
# Copyright © 2024 By Gary Ash All rights reserved.
#*****************************************************************************************

#*****************************************************************************************
# libraries used
#*****************************************************************************************
use strict;
use warnings;
use Foundation;
use File::Copy;
use File::Find;

#*****************************************************************************************
# main line
#*****************************************************************************************
our %simulators;
our $mediaList = "";

my $HOME           = $ENV{"HOME"};
my $simulatorsLoc  = "$HOME/Library/Developer/CoreSimulator/Devices";
my $media          = "$HOME/Documents/GeeDblA/Resources/Development/Apple/SimulatorBackup";

find(\&getSimulators, $simulatorsLoc);
find(\&addMedia, $media);

`xcrun simctl shutdown all;xcrun simctl delete unavailable;xcrun simctl erase all`;
for (keys %simulators) {
    `xcrun simctl boot "$_" &> /dev/null`;
    if (system("xcrun simctl addmedia $simulators{$_} $mediaList &> /dev/null") != 0) {
        print "**** Error loading simulator\n";
        exit(1);
    }
}
`xcrun simctl shutdown all`;

#*****************************************************************************************
# this routine will load a hash with names and UUIDs of the currently defined simulators
#*****************************************************************************************
sub getSimulators {
    return if ($File::Find::name !~ /\/device.plist/);
    my $plist = NSMutableDictionary->dictionaryWithContentsOfFile_($File::Find::name);
    if ($plist && $$plist) {
        my $platform = $plist->objectForKey_("runtime")->UTF8String;
        if ($platform =~ /.*iOS*/) {
            my $name = $plist->objectForKey_("name")->UTF8String;
            my $uuid = $plist->objectForKey_("UDID")->UTF8String;;
            $simulators{$name} = $uuid;
        }
    }
}

#*****************************************************************************************
# this routine will load a media into the current simulator
#*****************************************************************************************
sub addMedia {
    return if $_ eq "." or $_ eq ".." or $_ eq ".DS_Store";
    return if !-f $_;

    if ($mediaList ne "") {
        $mediaList .= " ";
    }
    $mediaList .= $File::Find::name;
}