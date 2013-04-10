package App::MPDJ;

use strict;
use warnings;
use 5.010;

our $VERSION = '1.02';

use Audio::MPD;
use Getopt::Long;
use Proc::Daemon;

sub new {
  my ($class, @options) = @_;

  my $self = bless {
    action    => undef,
    after     => 2,
    before    => 2,
    crossfade => 0,
    daemon    => 1,
    mpd       => undef,
    mpd_conn  => 'localhost',
    verbose   => 0,
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
    'h|help'        => sub { $self->{action} = 'show_help' },
    'V|version'     => sub { $self->{action} = 'show_version' },
    'mpd=s'         => \$self->{mpd_conn},
    'a|after=i'     => \$self->{after},
    'b|before=i'    => \$self->{before},
    'x|crossfade=i' => \$self->{crossfade},
    'D|daemon!'     => \$self->{daemon},
    'v|verbose!'    => \$self->{verbose},
  );
}

sub connect {
  my ($self) = @_;

  my $options = {};
  $options->{host} = $self->{mpd_conn} if $self->{mpd_conn};

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

    sleep 1;
  }
}

sub configure {
  my ($self) = @_;

  $self->say('Configuring MPD server');

  $self->mpd->repeat(0);
  $self->mpd->random(0);
  $self->mpd->fade($self->{crossfade});
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

  if (my $count = $self->mpd->status->song - $self->{before}) {
    $self->say("Deleting $count old songs");
    $self->mpd->playlist->delete(0 .. $count - 1);
  }
}

sub add_new_songs {
  my ($self) = @_;

  my $status = $self->mpd->status;
  if (my $count = $self->{after} + $status->song - $status->playlistlength + 1) {
    $self->say("Adding $count new songs");
    $self->add_song for 1 .. $count;
  }
}

sub add_song {
  my ($self) = @_;

  my @songs = $self->mpd->collection->all_songs;
  my $index = int(rand(scalar @songs));
  my $song = $songs[$index];

  $self->say('Adding ' . $song->file);
  $self->mpd->playlist->add($song->file);
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
  --mpd           MPD connection string (password\@host:port)
  -v,--verbose    Turn on chatty output
  --no-daemon     Turn off daemonizing
  -b,--before     Number of songs to keep in playlist before current song
  -a,--after      Number of songs to keep in playlist after current song
  -x,--crossfade  Seconds of crossfading between songs
  -V,--version    Show version information and exit
  -h,--help       Show this help and exit
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

Sets the MPD connection details.  See L<Audio::MPD#host> for more information.

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
