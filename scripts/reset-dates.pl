#!/usr/bin/env perl
#*****************************************************************************************
# reset-dates.pl
#
# This script will allow me to reset the file creation and modification dates of files in
# a given directory tree. date information is also edited if my personal source file
# header comment block is detected
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :  28-Apr-2024  10:00pm
# Modified :
#
# Copyright © 2024 By Gary Ash All rights reserved.
#*****************************************************************************************

#****************************************************************************************
# libraries
#****************************************************************************************
use strict;
use warnings;
use File::Find;
use POSIX qw(strftime);

my %processFilesOptions = (
    wanted      => \&processFiles,
    no_chdir    => 1,
    bydepth     => 0,
    follow_skip => 2,
);

our $SetFileDate = strftime "%D %I:%M %p",        localtime;
our $currentDate = strftime "%e-%b-%Y  %-I:%M%p", localtime;
our $currentYear = strftime "%Y",                 localtime;
$currentDate =~ s/AM/am/;
$currentDate =~ s/PM/pm/;

if (@ARGV != 2 && @ARGV != 1) {
    print "reset-date.pl \"company name\" <directory>\n";
    exit(1);
}

my $company  = $ARGV[0];
my $workRoot = (@ARGV == 2) ? $ARGV[1] : ".";

find(\%processFilesOptions, $workRoot);
`xattr -cr $workRoot/*`;
`find $workRoot/ -exec SetFile -d "$SetFileDate" -m "$SetFileDate" {} \\;`;
`find "$workRoot/" \\( -name "*~" -or -name ".*~" -or -name "#*#" -or -name ".#*#" -or -name "*.o" -or -name "*(deleted*" -or -name "*conflicted*" -or -name "*.DS_Store" \\) -exec rm -frv {} \\;`;

#*****************************************************************************************
# process a source file
#*****************************************************************************************
sub processFiles {
    return if $_ eq "." or $_ eq "..";
    return if !-f $_;
    return if index($_, '\r') > 0;

    if (open(my $sourcefile, "<$File::Find::name")) {
        my $source = do { local $/; <$sourcefile> };
        close($sourcefile);

        $source =~ s/\x{43}reated  :\s$|\x{43}reated  :\s*\d\d-...-\d*\s*\d*:\d*.*/\x{43}reated  :  $currentDate/g;
        $source =~ s/\x{4D}odified :\s$|\x{4D}odified :\s*\d\d-...-\d*\s*\d*:\d*.*/\x{4D}odified :/g;
        $source =~ s/\x{43}opyright © [0-9\-]* .*\n/\x{43}opyright © $currentYear By $company All rights reserved.\n/g;

        if (open($sourcefile, ">$File::Find::name")) {
            print $sourcefile $source;
            close($sourcefile);

        }
        else {
            print "*** Unable to read the $File::Find::name - $!\n";
        }
    }
    else {
        print "*** Unable to read the $File::Find::name - $!\n";
    }
}
