#!/usr/bin/perl

use ExtUtils::MakeMaker;

unless($ENV{SKIP_MPG123_TEST}) {
    my @paths = split /:/, $ENV{PATH};
    my $count = 0;
    foreach my $path (@paths) {
        if(-x $path . '/mpg123') {
            $count++;
        }
    }
    
    unless($count) {
        no_mpg123();
    }
}

WriteMakefile(
    NAME		    => 'POE::Component::MPG123',
    VERSION_FROM	=> 'MPG123.pm', 
    AUTHOR          => 'Matt Cashner (eek@eekeek.org)',
    ABSTRACT        => 'POE Component for accessing and working with mpg123, an mp3 player.',
    PREREQ_PM       => { POE => '0.22' },
);

sub no_mpg123 {
    print <<DEATH;
===========================================================
FATAL ERROR DETECTED!!!
        
This module wraps the program mpg123, which you don't seem 
to have. You either need to install mpg123 or make sure 
that it is in the environment's PATH. 

===========================================================
DEATH
    exit(1);
}

