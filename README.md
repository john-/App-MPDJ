# NAME

App::MPDJ - MPD DJ.

# SYNOPSIS

    > mpdj
    > mpdj --before 2 --after 6
    > mpdj --no-daemon --verbose

# DESCRIPTION

`App::MPDJ` is an automatic DJ for your `MPD` server.  It will manage a queue
of random songs for you just like a real DJ.

# OPTIONS

- \--mpd

    Sets the MPD connection details.  Should be a string like password@host:port.
    The password and port are both optional.

- \-s, --syslog

    Turns on sending of log information to syslog at specified level.  Level is a
    required parameter and can be one of debug, info, notice, warn[ing], err[or], crit[ical],
    alert or emerg[ency].

- \-l, --conlog

    Turns on sending of log information to console at specified level.  Level is a
    required parameter can be one of debug, info, notice, warn[ing], err[or], crit[ical],
    alert or emerg[ency].

- \--no-daemon

    Run in the foreground instead of trying to fork and exit.

- \-b, --before

    Number of songs to keep in the playlist before the current song.  The default
    is 2.

- \-a, --after

    Number of songs to queue up in the playlist after the current song.  The
    default is 2.

- \-c, --calls-freq

    Frequency in seconds for call signs to be injected.  The default is 3600 (one
    hour).  A value of 0 will disable call sign injection.

- \--calls-path

    Path to call sign files.  The default is 'calls'.

- \--music-path

    Path to music files.  The default is 'music'.

- \-V, --version

    Show the current version of the script installed and exit.

- \-h, --help

    Show this help and exit.

# AUTHOR

Alan Berndt <alan@eatabrick.org>

# COPYRIGHT

Copyright 2013- Alan Berndt

# LICENSE

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

# SEE ALSO

[Audio::MPD](http://search.cpan.org/perldoc?Audio::MPD)
