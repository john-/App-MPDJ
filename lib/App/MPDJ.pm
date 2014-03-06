package App::MPDJ;

use strict;
use warnings;
use 5.010;

our $VERSION = '1.07';

use Getopt::Long;
use Net::MPD;
use Proc::Daemon;
use Log::Dispatch;
use AppConfig;

sub new {
  my ($class, @options) = @_;

  my $config = AppConfig->new( {
    ERROR => \&invocation_error,
    CASE => 1,
  } );

  my $self = bless {
    action     => undef,
    last_call  => 0,
    config     => $config,
    @options
  }, $class;
}

sub mpd {
  my ($self) = @_;

  $self->{mpd};
}

sub parse_options {
  my ($self, @args) = @_;

  my @args_copy = @args;  # make a copy as there are two calls to getopt

  my @configurable = (
    [ "conf|f=s",                { VALIDATE => \&check_file } ],
    [ "before|b=i",              { DEFAULT =>  2            } ],
    [ "after|a=i",               { DEFAULT =>  2            } ],
    [ "calls-path|calls_path=s", { DEFAULT => 'calls'       } ],
    [ "calls-freq|calls_freq=i", { DEFAULT =>  3600         } ],
    [ "daemon|D!",               { DEFAULT =>  1            } ],
    [ "mpd=s",                   { DEFAULT => 'localhost'   } ],
    [ "music-path|music_path=s", { DEFAULT => 'music'       } ],
    [ "syslog|s=s",              { DEFAULT => ''            } ],
    [ "conlog|l=s",              { DEFAULT => ''            } ],
    [ "help|h",                  { ACTION  => sub { $self->{action} = 'show_help'    } } ],
    [ "version|V",               { ACTION  => sub { $self->{action} = 'show_version' } } ],
  );

  foreach (@configurable) {
      $self->{config}->define( $_->[0], $_->[1] );
  }

  $self->{config}->getopt(\@args);  # to get --conf option, if any

  foreach my $config ( ($self->{config}->conf || '/etc/mpdj.conf', "$ENV{HOME}/.mpdjrc") ) {
    if (-e $config) {
	say "Loading config ($config)" if $self->{config}->conlog;
      $self->{config}->file($config);
    } else {
      say "Config file skipped ($config)" if $self->{config}->conlog;
    }
  }

  $self->{config}->getopt(\@args_copy); # to override config file
}

sub connect {
  my ($self) = @_;

  $self->{mpd} = Net::MPD->connect($self->{config}->mpd());
}

sub execute {
  my ($self) = @_;

  if (my $action = $self->{action}) {
    $self->$action() and return 1;
  }

  @SIG{qw( INT TERM HUP )} = sub { $self->safe_exit() };

  my @loggers;
  push @loggers, ( [ 'Screen', min_level => $self->{config}->conlog, newline => 1    ] ) if $self->{config}->conlog;
  push @loggers, ( [ 'Syslog', min_level => $self->{config}->syslog, ident => 'mpdj' ] ) if $self->{config}->syslog;

  $self->{log} = Log::Dispatch->new(outputs => \@loggers);

  if ($self->{config}->daemon) {
    $self->{log}->notice('Forking to background');
    Proc::Daemon::Init;
  }

  $self->connect;
  $self->configure;

  $self->mpd->subscribe('mpdj');

  $self->update_cache;

  while (1) {
    $self->{log}->debug('Waiting');
    my @changes =
      $self->mpd->idle(qw(database player playlist message options));
    $self->mpd->update_status();

    foreach my $subsystem (@changes) {
      my $function = $subsystem . '_changed';
      $self->$function();
    }
  }
}

sub configure {
  my ($self) = @_;

  $self->{log}->notice('Configuring MPD server');

  $self->mpd->repeat(0);
  $self->mpd->random(0);

  if ($self->{config}->calls_freq) {
    my $now = time;
    $self->{last_call} = $now - $now % $self->{config}->calls_freq;
    $self->{log}->notice("Set last call to $self->{last_call}");
  }
}

sub update_cache {
  my ($self) = @_;

  $self->{log}->notice('Updating music and calls cache...');

  foreach my $category (('music', 'calls')) {

    my $path = "${category}_path";  # TODO:  Figure out how to not require putting in var first
    @{$self->{$category}} = grep { $_->{type} eq 'file' } $self->mpd->list_all($self->{config}->$path);

    my $total = scalar(@{ $self->{$category} });
    if ($total) {
      $self->{log}
        ->notice(sprintf("Total %s available: %d", $category, $total));
    } else {
      $self->{log}->warning("No $category available.  Path should be mpd path not file system.");
    }
  }
}

sub remove_old_songs {
  my ($self) = @_;

  my $song = $self->mpd->song || 0;
  my $count = $song - $self->{config}->before;
  if ($count > 0) {
    $self->{log}->info("Deleting $count old songs");
    $self->mpd->delete("0:$count");
  }
}

sub add_new_songs {
  my ($self) = @_;

  my $song = $self->mpd->song || 0;
  my $count = $self->{config}->after + $song - $self->mpd->playlist_length + 1;
  if ($count > 0) {
    $self->{log}->info("Adding $count new songs");
    $self->add_song for 1 .. $count;
  }
}

sub add_song {
  my ($self) = @_;

  $self->add_random_item_from_category('music');
}

sub add_call {
  my ($self) = @_;

  $self->{log}->info('Injecting call');

  $self->add_random_item_from_category('calls', 'immediate');

  my $now = time;
  $self->{last_call} = $now - $now % $self->{config}->calls_freq();
  $self->{log}->info('Set last call to ' . $self->{last_call});
}

sub add_random_item_from_category {
  my ($self, $category, $next) = @_;

  my @items = @{ $self->{$category} };

  my $index = int(rand(scalar @items));
  my $item  = $items[$index];

  my $uri  = $item->{uri};
  my $song = $self->mpd->song || 0;
  my $pos  = $next ? $song + 1 : $self->mpd->playlist_length;
  $self->{log}->info('Adding ' . $uri . ' at position ' . $pos);

  $self->mpd->add_id($uri, $pos);
}

sub time_for_call {
  my ($self) = @_;

  return unless $self->{config}->calls_freq();
  return time - $self->{last_call} > $self->{config}->calls_freq();
}

sub check_file {

    return -e $_[1];
}

sub show_version {
  my ($self) = @_;

  say "mpdj (App::MPDJ) version $VERSION";
}

sub safe_exit {
  my ($self) = @_;

  $self->{log}->log_and_die(level => 'notice', message => 'Ending');
}

sub show_help {
  my ($self) = @_;

  print <<HELP;
Usage: mpdj [options]

Options:
  --mpd             MPD connection string (password\@host:port)
  -s, --syslog      Turns on syslog output (debug, info, notice, warn[ing], error, etc)
  -l,--conlog       Turns on console output (same choices as --syslog)
  --no-daemon       Turn off daemonizing
  -b,--before       Number of songs to keep in playlist before current song
  -a,--after        Number of songs to keep in playlist after current song
  -c,--calls-freq   Frequency to inject call signs in seconds
  --calls-path      Path to call sign files
  --music-path      Path to music files
  -f, --conf        Config file to use instead of /etc/mpdj.conf
  -V,--version      Show version information and exit
  -h,--help         Show this help and exit
HELP

}

sub database_changed {
  my ($self) = @_;

  $self->update_cache;
}

sub player_changed {
  my ($self) = @_;

  $self->add_call() if $self->time_for_call();
  $self->add_new_songs();
  $self->remove_old_songs();
}

sub playlist_changed {
  my ($self) = @_;

  $self->player_changed();
}

sub message_changed {
  my $self = shift;

  my @messages = $self->mpd->read_messages();

  foreach my $message (@messages) {
    my $function = 'handle_message_' . $message->{channel};
    $self->$function($message->{message});
  }
}

sub options_changed {
  my $self = shift;

  $self->{log}->notice('Resetting configuration');

  $self->mpd->repeat(0);
  $self->mpd->random(0);
}

sub handle_message_mpdj {
  my ($self, $message) = @_;

  my ($option, $value) = split /\s+/, $message, 2;

  # TODO: Understand this.  Does it break with new config system
  if ($option =~ /^(?:before|after|calls_freq)$/) {
    return unless $value =~ /^\d+$/;
    $self->{log}->info('Setting ' . $option . ' to ' . $value);
    $self->{$option} = $value;
    $self->player_changed();
  }
}

sub invocation_error {

    # TODO: Currently exits program after first error.  There may be more after this one to show.
    say "error: @_";

    show_help;

    exit;
}

1;

__END__

=encoding utf-8

=head1 NAME

App::MPDJ - MPD DJ.

=head1 SYNOPSIS

  > mpdj
  > mpdj --before 2 --after 6
  > mpdj --no-daemon --conlog info

=head1 DESCRIPTION

C<App::MPDJ> is an automatic DJ for your C<MPD> server.  It will manage a queue
of random songs for you just like a real DJ.

=head1 OPTIONS

=over 4

=item --mpd

Sets the MPD connection details.  Should be a string like password@host:port.
The password and port are both optional.

=item -s, --syslog

Turns on sending of log information to syslog at specified level.  Level is a
required parameter can be one of debug, info, notice, warn[ing], err[or],
crit[ical], alert or emerg[ency].

=item -l, --conlog

Turns on sending of log information to console at specified level.  Level is a
required parameter can be one of debug, info, notice, warn[ing], err[or],
crit[ical], alert or emerg[ency].

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

=item -f --conf

Config file to use instead of /etc/mpdj.conf.

=item -V, --version

Show the current version of the script installed and exit.

=item -h, --help

Show this help and exit.

=back

=head1 CONFIGURATION FILES

Lowest to highest priority: /etc/mpdj.conf or config file specified on command line, ~/.mpdjrc, and finally command line options.  Format of configuration file is the ini file format as supported by AppConfig.

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
