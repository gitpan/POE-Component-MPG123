#!/usr/bin/perl -w

use strict;

sub POE::Kernel::ASSERT_DEFAULT () { 1 }
use POE qw(Component::MPG123);

# Cheezy test setup to eliminate a dependency on Test::More.

BEGIN {
  $| = 1;
  print "1..11\n";
}

POE::Component::MPG123->spawn( alias => 'tester' );

# Find the test song!

my $test_song = './test.mp3';
$test_song = '../' . $test_song unless -f $test_song;
$test_song = '../' . $test_song unless -f $test_song;
die "could not find test.mp3"   unless -f $test_song;

#------------------------------------------------------------------------------

# I started the Session with just _start and _default states until I
# figured out how to find test.mp3 (above) regardless whether the test
# was run from the main distribution directory or ./t

# Once it got that far, I decided to catch status events because they
# scrolled everything off the screen.  Ensuring that all the frame
# status events arrived seemed like a good start, so I recorded the
# total frames and time from status 0.

#------------------------------------------------------------------------------

# Start a session to exercise the component.

POE::Session->create
  ( inline_states =>
    { _start => sub {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->alias_set( 'tester' );

        # Set our expectations.  We only expect mpg123 to quit after
        # we tell it to.  If it does before then, something's in
        # trouble.
        $heap->{expecting_quit} = 0;

        # Count how many times we play the song.  On the first play,
        # test pause/resume.  On the second play, test stop.
        $heap->{play_count}     = 0;

        # Start the song.
        $kernel->post( mpg123 => play => $test_song );
      },

      # A cheap final test.

      _stop => sub {
        print "ok 11\n";
      },

      ### Status tests.

      # Receive status events from mpg123.  We're going to count them
      # and make sure we get every one.

      status => sub {
        my ( $kernel, $heap,
             $frames_played, $frames_left, $time_played, $time_left
           ) = @_[KERNEL, HEAP, ARG0..ARG3];

        # Frame 0 describes the song's times.  Record the total frame
        # count and total time.  Immediately try to pause the song,
        # exercising pause/resume.  Latency is about 7 frames on an
        # Athlon 1GHz.  The test file is 192 frames (about 5 seconds).
        # It's also pure silence so (1) nobody is deafened, (2) no
        # audio equipment burns out, (3) it compresses extremely well.

        unless ($frames_played) {
          $heap->{total_frames} = $frames_left;
          $heap->{total_time}   = $time_left;

          $heap->{play_count}++;

          if ($heap->{play_count} == 1) {
            $kernel->post( mpg123 => 'pause' );
            $kernel->delay( pause_timeout => 1 );
            return;
          }

          if ($heap->{play_count} == 2) {
            $kernel->post( mpg123 => 'stop' );
            $kernel->delay( stop_timeout => 1 );
            return;
          }

          die "internal inconsistency";
        }

        # Count the frames we receive (after the 0th, which doesn't
        # count itself).  Also record the elapsed time information
        # from the last frame we get.

        $heap->{frame_count}++;
        $heap->{last_frame} = $frames_played;
        $heap->{last_time}  = $time_played;

        # Rather than wait for a specific frame and call it the end of
        # the song, I'll set a brief delay here to time out if frames
        # stop playing.

        $kernel->delay( song_timeout => 0.25 );
      },

      ### Test Group 1: Song and file information events are posted
      ### even before the 0th frame, so they are the first tests to
      ### occur each time the song is played.

      # Verify that the song information is correct.  This test relies
      # on a specific mp3 file as the test subject.

      song_info => sub {
        my ($kernel, $heap, $info) = @_[KERNEL, HEAP, ARG0];

        my $not_ok = 0;
        $not_ok++ unless delete $info->{album} eq 'Test Album';
        $not_ok++ unless delete $info->{artist} eq 'Test Artist';
        $not_ok++ unless delete $info->{comment} eq 'Test Comment';
        $not_ok++ unless delete $info->{genre} eq 'Porn Groove';
        $not_ok++ unless delete $info->{title} eq 'Test Title';
        $not_ok++ unless delete $info->{type} eq 'id3';
        $not_ok++ unless delete $info->{year} eq '4321';
        $not_ok++ if keys %$info;

        print 'not ' if $not_ok;

        # This test has different numbers depending whether this is
        # the first time the test mp3 was played.  These events are
        # fired before the 0th frame, so the play counts are one less
        # than real.

        if ($heap->{play_count} == 0) {
          print "ok 1\n";
          return;
        }

        if ($heap->{play_count} == 1) {
          print "ok 7\n";
          return;
        }

        die "internal inconsistency";
      },

      file_info => sub {
        my ($kernel, $heap, $info) = @_[KERNEL, HEAP, ARG0];

        my $not_ok = 0;
        $not_ok++ unless delete $info->{bitrate} eq 128;
        $not_ok++ unless delete $info->{bpf} eq 417;
        $not_ok++ unless delete $info->{channels} eq 2;
        $not_ok++ unless delete $info->{copyrighted} eq 1;
        $not_ok++ unless delete $info->{crc} eq 1;
        $not_ok++ unless delete $info->{emphasis} eq 0;
        $not_ok++ unless delete $info->{extension} eq 0;
        $not_ok++ unless delete $info->{layer} eq 3;
        $not_ok++ unless delete $info->{lsf} eq 0;
        $not_ok++ unless delete $info->{mode} eq 'Joint-Stereo';
        $not_ok++ unless delete $info->{mode_extension} eq 2;
        $not_ok++ unless delete $info->{samplerate} eq 44100;
        $not_ok++ unless delete $info->{type} eq '1.0';
        $not_ok++ if keys %$info;

        print 'not ' if $not_ok;

        # This test has different numbers depending whether this is
        # the first time the test mp3 was played.  These events are
        # fired before the 0th frame, so the play counts are one less
        # than real.

        if ($heap->{play_count} == 0) {
          print "ok 2\n";
          return;
        }
        if ($heap->{play_count} == 1) {
          print "ok 8\n";
        }
      },

      ### Test Group 2: Pause and resume tests.  These are invoked
      ### immediately upon receipt of song frame 0.

      # The song didn't pause or resume in a timely fashion.  Bail out
      # of the test program, skipping what tests weren't tested.  We
      # expect mpg123 to quit after this.

      pause_timeout => sub {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $heap->{expecting_quit} = 1;
        $kernel->post( mpg123 => 'quit' );

        if ($heap->{play_count} == 1) {
          print "not ok 4\n";
          print "not ok 5\n";
          return;
        }
        if ($heap->{play_count} == 2) {
          print "not ok 9\n";
          return;
        }
      },

      # The pause succeeded.  Reset the pause timeout and try to
      # resume the song.

      song_paused => sub {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay( pause_timeout => 1 );
        $kernel->post( mpg123 => 'pause' );
      },

      # The song resumed after we asked it to.  Turn off the pause
      # timeout and record a successful test.

      song_resumed => sub {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay( 'pause_timeout' );
        print "ok 3\n";
      },

      # The song stopped naturally.  Disable the song timeout, and
      # shut down the mpg123 player.

      song_stopped => sub {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay( 'song_timeout' );
        $kernel->delay( 'stop_timeout' );
        $kernel->post( mpg123 => 'quit' );
        $heap->{expecting_quit} = 1;

        # The first play is allowed to complete naturally.

        if ($heap->{play_count} == 1) {
          print 'not ' unless $heap->{total_frames} == $heap->{frame_count};
          print "ok 4\n";
          print 'not ' unless $heap->{total_frames} == $heap->{last_frame};
          print "ok 5\n";
          return;
        }

        # The second play was stopped early, so we don't test for full
        # completion.

        if ($heap->{play_count} == 2) {
          print "ok 9\n";
          return;
        }
        die "internal inconsistency";
      },

      ### Test Group 3: Player shutdown after the song is done.  These
      ### occur last in any given play pass.

      # The player has quit.  Were we expecting that?  Start another
      # player; we still need to test stop.

      player_quit => sub {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        print 'not ' unless $heap->{expecting_quit};

        # Not expecting a player_quit anymore.
        $heap->{expecting_quit} = 0;

        if ($heap->{play_count} == 1) {
          print "ok 6\n";

          POE::Component::MPG123->spawn( alias => 'tester' );
          $kernel->post( mpg123 => play => $test_song );
          return;
        }

        if ($heap->{play_count} == 2) {
          print "ok 10\n";
          return;
        }

        die "internal inconsistency";
      },

      ### Miscellaneous event handlers.

      # Trap events we're not using.  This prevents ASSERT_STATES from
      # killing the test.

      debug   => sub { },
      _child  => sub { },
      _signal => sub { 0 },
    },
  );

$poe_kernel->run();
exit 0;
