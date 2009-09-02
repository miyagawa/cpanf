use inc::Module::Install;
name 'App-CPAN-Fresh';
all_from 'lib/App/CPAN/Fresh.pm';

requires 'CPAN::Inject';
requires 'App::Cmd', '0.30';
requires 'JSON', '2.0';
requires 'URI';
requires 'LWP';
requires 'Time::Piece';

install_script 'cpanf';

build_requires 'Test::More';
use_test_base;
auto_include_deps;
author_tests('xt');
auto_set_repository;
WriteAll;
