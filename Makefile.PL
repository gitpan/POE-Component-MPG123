#!/usr/bin/perl

use ExtUtils::MakeMaker;


WriteMakefile(
    NAME		    => 'POE::Component::MPG123',
    VERSION_FROM	=> 'MPG123.pm', 
    AUTHOR          => 'Matt Cashner (eek@eekeek.org)',
    ABSTRACT        => 'POE Component for accessing and working with mpg123, an mp3 player.',
    PREREQ_PM       => { POE => '0.1501' },
);
