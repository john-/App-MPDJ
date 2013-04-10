requires 'perl', '5.010';

requires 'Audio::MPD';
requires 'Getopt::Long';
requires 'Proc::Daemon';

on test => sub {
    requires 'Test::More', '0.88';
};
