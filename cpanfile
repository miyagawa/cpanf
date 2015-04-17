requires 'App::Cmd', '0.30';
requires 'CPAN::Inject';
requires 'Filter::Util::Call';
requires 'JSON', '2.0';
requires 'LWP';
requires 'Time::Piece';
requires 'URI';
requires 'perl', '5.008001';

on build => sub {
    requires 'Test::More';
};
