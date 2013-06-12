package App::MPDJ;

use strict;
use warnings;
use 5.010;

our $VERSION = '1.04';

use Audio::MPD;
use Getopt::Long;
use Proc::Daemon;

sub new {
  my ($class, @options) = @_;

  my $self = bless {
    action     => undef,
    after      => 2,
    before     => 2,
    calls_path => 'calls',
    calls_freq => 3600,
    crossfade  => 0,
    daemon     => 1,
    last_call  => 0,
    mpd        => undef,
    mpd_conn   => 'localhost',
    music_path => 'music',
    verbose    => 0,
    @options
  }, $class;
}

sub mpd {
  my ($self) = @_;

  $self->{mpd};
}

sub say {
  my ($self, @args) = @_;

  say @args if $self->{verbose};
}

sub parse_options {
  my ($self, @options) = @_;

  local @ARGV = @options;

  Getopt::Long::Configure('bundling');
  Getopt::Long::GetOptions(
    'D|daemon!'      => \$self->{daemon},
    'V|version'      => sub { $self->{action} = 'show_version' },
    'a|after=i'      => \$self->{after},
    'b|before=i'     => \$self->{before},
    'calls-path=s'   => \$self->{calls_path},
    'c|calls-freq=i' => \$self->{calls_freq},
    'h|help'         => sub { $self->{action} = 'show_help' },
    'mpd=s'          => \$self->{mpd_conn},
    'music-path=s'   => \$self->{music_path},
    'v|verbose!'     => \$self->{verbose},
    'x|crossfade=i'  => \$self->{crossfade},
  );
}

sub connect {
  my ($self) = @_;

  my $options = {};

  my (@items) = ($self->{mpd_conn} =~ /^(?:([^@]+)@)?([^:]+)(?::(\d+))?$/);

  $options->{password} = $items[0] if $items[0];
  $options->{host}     = $items[1] if $items[1];
  $options->{port}     = $items[2] if $items[2];

  $self->{mpd} = Audio::MPD->new($options);
}

sub execute {
  my ($self) = @_;

  if (my $action = $self->{action}) {
    $self->$action() and return 1;
  }

  if ($self->{daemon}) {
    $self->say('Forking to background');
    Proc::Daemon::Init;
  }

  $self->connect;
  $self->configure;

  while (1) {
    $self->ensure_playing;
    $self->remove_old_songs;
    $self->add_new_songs;

    $self->add_call if $self->time_for_call;

    sleep 1;
  }
}

sub configure {
  my ($self) = @_;

  $self->say('Configuring MPD server');

  $self->mpd->repeat(0);
  $self->mpd->random(0);
  $self->mpd->fade($self->{crossfade});

  if ($self->{calls_freq}) {
    my $now = time;
    $self->{last_call} = $now - $now % $self->{calls_freq};
    $self->say("Set last call to $self->{last_call}");
  }
}

sub ensure_playing {
  my ($self) = @_;

  my $status = $self->mpd->status;
  unless ($status->state eq 'play') {
    $self->say('MPD not playing, enabling');

    $self->add_song if $status->playlistlength == 0;
    $self->mpd->play;
  }
}

sub remove_old_songs {
  my ($self) = @_;

  my $count = $self->mpd->status->song - $self->{before};
  if ($count > 0) {
    $self->say("Deleting $count old songs");
    $self->mpd->playlist->delete(0 .. $count - 1);
  }
}

sub add_new_songs {
  my ($self) = @_;

  my $status = $self->mpd->status;
  my $count = $self->{after} + $status->song - $status->playlistlength + 1;
  if ($count > 0) {
    $self->say("Adding $count new songs");
    $self->add_song for 1 .. $count;
  }
}

sub add_song {
  my ($self) = @_;

  $self->add_random_item_from_path($self->{music_path});
}

sub add_call {
  my ($self) = @_;

  $self->say('Injecting call');

  $self->add_random_item_from_path($self->{calls_path}, 'immediate');
  $self->{last_call} = time;
}

sub add_random_item_from_path {
  my ($self, $path, $next) = @_;

  my @items = grep { $_->isa('Audio::MPD::Common::Item::Song') }
    $self->mpd->collection->all_items_simple($path);

  my $index = int(rand(scalar @items));
  my $item = $items[$index];

  $self->say('Adding ' . $item->file);

  my $playlist = $self->mpd->playlist;

  $playlist->add($item->file);

  if ($next) {
    my $status = $self->mpd->status;
    $playlist->move($status->playlistlength - 1, $status->song + 1);
  }
}

sub time_for_call {
  my ($self) = @_;

  return unless $self->{calls_freq};
  return time - $self->{last_call} > $self->{calls_freq};
}

sub show_version {
  my ($self) = @_;

  say "mpdj (App::MPDJ) version $VERSION";
}

sub show_help {
  my ($self) = @_;

  print <<HELP;
Usage: mpdj [options]

Options:
  --mpd             MPD connection string (password\@host:port)
  -v,--verbose      Turn on chatty output
  --no-daemon       Turn off daemonizing
  -b,--before       Number of songs to keep in playlist before current song
  -a,--after        Number of songs to keep in playlist after current song
  -c,--calls-freq   Frequency to inject call signs in seconds
  --calls-path      Path to call sign files
  --music-path      Path to music files
  -x,--crossfade    Seconds of crossfading between songs
  -V,--version      Show version information and exit
  -h,--help         Show this help and exit
HELP
}

1;

__END__

=encoding utf-8

=head1 NAME

App::MPDJ - MPD DJ.

=head1 SYNOPSIS

  > mpdj
  > mpdj --before 2 --after 6 --crossfade 5
  > mpdj --no-daemon --verbose

=head1 DESCRIPTION

C<App::MPDJ> is an automatic DJ for your C<MPD> server.  It will manage a queue
of random songs for you just like a real DJ.

=head1 OPTIONS

=over 4

=item --mpd

Sets the MPD connection details.  Should be a string like password@host:port.
The password and port are both optional.

=item -v, --verbose

Makes the output verbose.  Default is to be quiet.

=item --no-daemon

Run in the foreground instead of trying to fork and exit.

=item -b, --before

Number of songs to keep in the playlist before the current song.  The default
is 2.

=item -a, --after

Number of songs to queue up in the playlist after the current song.  The
default is 2.

=item -c, --calls-freq

Frequency in seconds for call signs to be injected.  The default is 3600 (one
hour).  A value of 0 will disable call sign injection.

=item --calls-path

Path to call sign files.  The default is 'calls'.

=item --music-path

Path to music files.  The default is 'music'.

=item -x, --crossfade

Set the seconds of crossfade to use.  The default is 0 seconds which means no
crossfading will happen.

=item -V, --version

Show the current version of the script installed and exit.

=item -h, --help

Show this help and exit.

=back

=head1 AUTHOR

Alan Berndt E<lt>alan@eatabrick.orgE<gt>

=head1 COPYRIGHT

Copyright 2013- Alan Berndt

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

L<Audio::MPD>

=cut
