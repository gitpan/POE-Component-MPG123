#$Header: /cvsroot/POE-Component-MPG123/MPG123.pm,v 1.15 2002/08/17 23:26:13 sungo Exp $
package POE::Component::MPG123;

use warnings;
use strict;
use Carp;
use POE qw( Wheel::Run 
            Filter::Line 
            Driver::SysRW 
          );
use vars qw($VERSION);

$VERSION = (qw($Revision: 1.15 $))[1];
my %pid;	# keeps a list of process id's for players spawned
my $alias;	# last used alias
my $err;	# last error generated

# mpg123 component.

sub fixup {
    my $foo = shift;
    $foo =~ s/^[\x00-\x1F\s]*//;
    $foo =~ s/[\x00-\x1F\s]*$//;
    $foo;
}

sub spawn {
    my $class = shift;
    my %args = @_;
    $args{alias} ||= 'console';

    POE::Session->create( 
        inline_states => { 
            _start     => \&_start,
            _stop      => \&_stop,
        
            cmd_sent   => \&cmd_sent,
            got_output => \&got_output,
            got_error  => \&got_error,
        
            play       => \&play,
            stop       => \&stop,
            pause      => \&pause,
        
            stat       => \&stat,
            shutdown   => \&shutdown,
            quit       => \&quit,
			vol        => \&vol,
			xcmd       => \&xcmd,

            sig_child  => \&sig_child,
            force_quit => \&force_quit,

            _signal    => sub { 0 },
        },
        args => [ \%args ],
    );
}

sub _start { #{{{
    my ($kernel,$heap,$args) = @_[KERNEL,HEAP,ARG0];
	my @args = split /\s+/, $args->{mpg123} if $args->{mpg123};

    $kernel->alias_set('mpg123');
    $heap->{interface} = $args->{alias};

    $heap->{player} = POE::Wheel::Run->new ( 
         Program     => [ 'mpg123', '-R', '--aggressive', @args, '' ],
         StdioFilter  => POE::Filter::Line->new( Literal => "\n" ),
         StderrFilter => POE::Filter::Line->new( Literal => "\n" ),
         StdinEvent  => 'cmd_sent',
         StdoutEvent => 'got_output',
         StderrEvent => 'got_error',
         );
    $kernel->sig( CHLD => 'sig_child' );
	$pid{ $heap->{interface} } = $heap->{player}->PID;
	$alias = $heap->{interface};
}#}}}

sub _stop { #{{{
    my ($kernel,$heap) = @_[KERNEL,HEAP];
    if (defined $heap->{player}) {
      kill 9, $heap->{player}->PID;
      delete $heap->{player};
    }
}#}}}

# To make sure stuff got flushed to mpg123.
sub cmd_sent { #{{{
    $_[KERNEL]->post( $_[HEAP]->{interface} => debug => "command sent" ) ;
}#}}}

# Parse MPG123 responses, and forward them to the console in
# some pretty format.
sub got_output {  #{{{
    my ($kernel, $heap, $response) = @_[KERNEL, HEAP, ARG0];

    # Frame status.  Goes first because there are so many.
    if ( $response =~ /^\@F (.*?)\s*$/ ) {
        # frames (played, left); seconds (played, left)
        $kernel->post( $heap->{interface} => status => split( /\s+/, $1 ) );
        return;
    }

    # Whoops!
    elsif ( $response =~  /^\@E (.*?)\s*$/ ) {
        $_[KERNEL]->post( $heap->{interface} => debug => "mpg123 error: $1" );
        return;
    }

    # ID3 tags
    elsif ( $response =~ /^\@I ID3:(.+?)\s*$/) {
        my ($title, $artist, $album, $year, $comment, $genre) =
        unpack( 'A30 A30 A30 A4 A30 A*', $1 );
        $kernel->post( $heap->{interface} => song_info =>
                         { type    => 'id3',
                           title   => fixup($title),
                           artist  => fixup($artist),
                           album   => fixup($album),
                           year    => fixup($year),
                           comment => fixup($comment),
                           genre   => fixup($genre),
                         },
                    );
        return;
    }

    # No ID3 tags
    elsif ( $response =~ /^\@I (.*?)\s*$/ ) {
        $kernel->post( $heap->{interface} => song_info =>
                         { type     => 'filename',
                           filename => fixup($1),
                         },
                       );
        return;
    }

        # MPG123 is okay.
    if ( $response =~ /^\@R (.*?)\s*$/ ) {
        $kernel->post( $heap->{interface} => debug => "mpg123 version: $1" );
        return;
    }

    # Song status.
    if ( $response =~ /^\@S (.*?)\s*$/ ) {
        my ($type, $layer, $samplerate, $mode, $mode_extension, $bpf,
              $channels, $copyrighted, $crc, $emphasis, $bitrate,
              $extension, $lsf
           ) = split( /\s+/, $1 );

        my $tpf = ( ( ($layer > 1) ? 1152 : 384 ) / $samplerate );
        $tpf /= 2 if $lsf;

        $kernel->post( $heap->{interface} => file_info =>
                         { type           => $type,
                           layer          => $layer,
                           samplerate     => $samplerate,
                           mode           => $mode,
                           mode_extension => $mode_extension,
                           bpf            => $bpf,
                           channels       => $channels,
                           copyrighted    => $copyrighted,
                           crc            => $crc,
                           emphasis       => $emphasis,
                           bitrate        => $bitrate,
                           extension      => $extension,
                           lsf            => ((defined $lsf) ? $lsf : 0)
                         },
                    );
        return;
    }

        # Play status!
    elsif ( $response =~ /^\@P (\d+)\s*$/ ) {
        if ($1 == 0) {
            $kernel->post( $heap->{interface} => 'song_stopped' );
            return;
        }
        elsif ($1 == 1) {
            $kernel->post( $heap->{interface} => 'song_paused' );
            return;
        }
        elsif ($1 == 2) {
            $kernel->post( $heap->{interface} => 'song_resumed' );
            return;
        }
        elsif ($1 == 3) {
            $kernel->post( $heap->{interface} => 'song_ended' );
            return;
        }
    }

    $_[KERNEL]->post( $heap->{interface} => debug => $_[ARG0] );
}#}}}

sub got_error { #{{{
	my ($kernel, $heap) = @_[KERNEL, HEAP];
	$err = $_[ARG0];
    $kernel->post( $heap->{interface}, error => $err );
}#}}}

sub play { #{{{
    my ($heap, $file) = @_[HEAP, ARG0];
    $heap->{player}->put( "LOAD $file" );   
}#}}}

sub stop { #{{{
    my ($heap, $file) = @_[HEAP, ARG0];
    $heap->{player}->put( "STOP" );    
}#}}}

sub pause { #{{{
    my $heap = $_[HEAP];
    $heap->{player}->put( "PAUSE" );
}#}}}

sub stat { #{{{
    my $heap = $_[HEAP];
    $heap->{player}->put( "STAT" );   
}#}}}

sub vol { #{{{
    my ($heap, $vol) = @_[HEAP, ARG0];
	$vol ||= 0;
	return unless $vol =~ /^\d+$/;
    $heap->{player}->put( "VOL $vol" );   
}#}}}

sub xcmd { #{{{
    my ($heap, $cmd) = @_[HEAP, ARG0];
	return unless $cmd;
    $heap->{player}->put( $cmd );   
}#}}}

sub pid { #{{{
	my $alias = shift || $alias;
    return $pid{$alias};
}#}}}

sub shutdown { #{{{
    my ($kernel,$heap) = @_[KERNEL,HEAP];
    $kernel->alias_remove( 'mpg123' );
    $kernel->post( $heap->{interface} => 'player_quit' );
    delete $heap->{player};
}#}}}

sub sig_child {#{{{
    my ($kernel, $heap, $pid, $status) = @_[KERNEL, HEAP, ARG1, ARG2];
    if ($pid == $heap->{player}->PID) {
        $kernel->delay( 'force_quit' );
        $kernel->yield("shutdown");
    }
    return 0;
}#}}}

sub quit {#{{{
    $_[HEAP]->{player}->put( "QUIT" );
    $_[KERNEL]->delay( force_quit => 1 );
}#}}}

sub force_quit {#{{{
    my $heap = $_[HEAP];
    if (defined $heap->{player}) {
        kill 9, $heap->{player}->PID;
        $_[KERNEL]->delay( shutdown => 1 );
    }
}#}}}

1;

# Documentation #{{{

=head1 NAME

POE::Component::MPG123

=head1 SYNOPSIS
 
    use POE qw(Component::MPG123);
    my $alias = 'mp3weazel';

    POE::Component::MPG123->spawn( alias => $alias );

    $poe_kernel->run();

=head1 DESCRIPTION

POE Component for accessing and working with mpg123, an mp3 player. 

PoCo::MPG123's C<spawn()> method takes one named parameter:

=over 4

=item alias

    alias => $alias

C<alias> is the name of a session to which the callbacks below will be
posted.  This defaults to B<console>.

=back

=head2 Available events

All events are posted to a session named C<mpg123>.

=item play

    $kernel->post( mpg123 => play => $filename );

Load and play the mp3 found at C<$filename>. The parameter must either
be an existing mp3 file or the full url to an mp3 stream.

=item stop

    $kernel->post( mpg123 => 'stop' );

Stop playing the current track and unload it. This is like pressing stop
on your CD player, not your cassette tape deck. The track is actually
unloaded and you cannot continue from where you left off.

=item pause

    $kernel->post( mpg123 => 'pause' );

Pause or unpause the current track.

=item vol

	$kernel->post( mpg123, vol => $vol );

Sets the volume.  The $vol parameter should be an integer between 0 and 100 (inclusive) representing the percentage to set.  Note that this command can only be used with a patched version of mpg123 that supports the VOL command.  Use of this command in unpatched versions will result in undetermined behaviour.

=item xcmd

	$kernel->post( mpg123, xcmd => $cmd );

This message allows posting to the player any command not currently built into this component.  Use at your own risk!
 
=item quit 

    $kernel->post( mpg123 => 'quit' );

Stop playing the current track and shut down the mpg123 process.

=head2 Callbacks

As noted above, all callbacks are either posted to the session alias 
given to C<spawn()> or C<console>.

=item status

Fired during playback.  ARG0 is the number of frames played up till now.
ARG1 is the number of frames remaining to be played.  ARG2 is the
number of seconds played. ARG3 is the number of seconds remaining in the
track.

=item song_info

Fired when a song is loaded. ARG0 is a hash ref containing either ID3
tag information or the filename (if there is no ID3 tag). The C<type>
element of the hash is set to I<id3> in the former case and I<filename>
in the latter case. For type I<id3>, the hash elements are title, 
artist, album, year, comment, and genre. For type I<filename>, the hash
elements are filename.

=item file_info

Fired when a song is loaded. ARGO is a hash ref containing information
about the mp3 file/stream itself. Hash elements are type, layer,
samplerate, mode, mode_extension, bpf, channels, copyright, crc,
emphasis, bitrate, extension, and lsf.

=item song_stopped

Fired when a song stops. No args.

=item song_paused

Fired when a song becomes paused. No args.

=item song_resumed

Fired when a song resumes playback. No args.

=item song_ended

Fired when playing a song has finished.

=item player_quit

Fired when mpg123 goes away, either as the result of something stupid 
happening in mpg123 itself or as a result of a C<quit> event.  Suggested 
use is to either quit gracefully or create a new player.

=item debug

Fired when there is random not-useful-to-normal-people information. 
ARG0 is a string containing the debug message. Not recommended for 
production use.

=head1 AUTHOR

Matt Cashner (eek+poe@eekeek.org)

Erick Calder (ekkis@cpan.org)

Rocco Caputo (troc@netrus.net)

=head1 DATE

$Date: 2002/08/17 23:26:13 $

=head1 VERSION

$Revision: 1.15 $

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2000-2002 Matt Cashner, Erick Calder, and Rocco Caputo. This product is 
distributed under the MIT License. A copy of this license was included 
in a file called LICENSE. If for some reason, this file was not 
included, please see 
http://www.opensource.org/licenses/mit-license.html to obtain a copy 
of this license.

=cut

#}}}


