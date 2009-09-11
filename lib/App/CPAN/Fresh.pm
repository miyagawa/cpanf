package App::CPAN::Fresh;

use strict;
use 5.008_001;
our $VERSION = '0.07';

use base qw(App::Cmd::Simple);

use Carp;
use CPAN::Inject;
use Time::Piece;
use File::Temp;
use JSON;
use LWP::UserAgent;
use URI;

my $duration = 2 * 24 * 60 * 60;

sub opt_spec {
    return (
        [ "install|i", "install the module" ],
        [ "list|l", "list the recent uploads" ],
        [ "test|t", "test the dist" ],
        [ "force|f", "force install" ],
        [ "devel|d", "install even if it's a devel release" ],
        [ "help|h", "displays usage info" ],
    );
}

sub execute {
    my($self, $opt, $args) = @_;

    if ($opt->{list} && $args->[0]) {
        $self->search($args->[0]);
    } elsif ($opt->{list}) {
        $self->recent;
    } elsif ($opt->{help} || !@$args) {
        $self->usage;
    } else {
        $self->handle($opt, $args);
    }
}

sub recent {
    my $self = shift;
    my $res = $self->call("/feed/cpan");
    $self->display_results($res);
}

sub search {
    my($self, $q) = @_;
    my $res = $self->call("/search", { q => "$q group:cpan" });
    $self->display_results($res);
}

sub usage {
    require Pod::Usage;
    Pod::Usage::pod2usage(0);
}

sub handle {
    my($self, $opt, $dists) = @_;

    my @install;
    for my $dist (@$dists) {
        my $path = $self->inject($dist, $opt);
        if ($path) {
            push @install, $path;
        } else {
            print "$dist is not found or not in the fresh uploads. Falling back to your mirror.\n";
            push @install, $dist;
        }
    }

    my $method = "install";
    $method = "test" if $opt->{test};

    if (@install) {
        require CPAN;
        if ($opt->{force}) {
            CPAN::Shell->force($method, @install);
        } else {
            CPAN::Shell->$method(@install);
        }
    }
}

sub inject {
    my($self, $dist, $opt) = @_;
    $dist =~ s/::/-/g;

    for my $method ([ "/feed/cpan" ], [ "/search", { q => "$dist group:cpan" } ]) {
        my $res = $self->call($method->[0], $method->[1]);
        for my $entry (@{$res->{entries}}) {
            my $info = $self->parse_entry($entry->{body}, $entry->{date}) or next;
            if ($info->{dist} eq $dist) {
                if ($info->{version} =~ /_/ && !$opt->{devel}) {
                    warn "$info->{dist}-$info->{version} found: No -d option, skipping\n";
                    return;
                }
                return $self->do_inject($info);
            }
        }
    }

    return;
}

sub do_inject {
    my($self, $info) = @_;

    my $dir = File::Temp::tempdir(CLEANUP => 1);
    my $local = "$dir/$info->{dist}-$info->{version}.tar.gz";

    print "Fetching $info->{url}\n";
    my $res = $self->new_ua->mirror($info->{url}, $local);
    if ($res->is_error) {
        croak "Fetching $info->{url} failed: ", $res->status_line;
    }

    CPAN::Inject->from_cpan_config->add(file => $local);
}

sub display_results {
    my($self, $res) = @_;
    for my $entry (@{$res->{entries}}) {
        my $info = $self->parse_entry($entry->{body}, $entry->{date}) or next;
        printf "%s-%s (%s)\n", $info->{dist}, $info->{version}, $info->{author};
    }
}

sub parse_entry {
    my($self, $body, $date) = @_;

    my $time = Time::Piece->strptime($date, "%Y-%m-%dT%H:%M:%SZ") or return;
    if (time - $time->epoch > $duration) {
        # entry found, but it's old
        return;
    }

    if ($body =~ /^([\w\-]+) ([0-9\._]*) by (.+?) - <a.*href="(http:.*?\.tar\.gz)"/) {
        return {
            dist    => $1,
            version => $2,
            author  => $3,
            url     => $4,
        };
    }

    return;
}

sub new_ua {
    my $self = shift;
    LWP::UserAgent->new(agent => "cpanf/$VERSION", env_proxy => 1);
}

sub call {
    my($self, $method, $opts) = @_;

    my $uri = URI->new("http://friendfeed-api.com/v2$method");
    $uri->query_form(%$opts) if $opts;

    my $ua  = $self->new_ua;
    my $res = $ua->get($uri);

    if ($res->is_error) {
        croak "HTTP error: ", $res->status_line;
    }

    JSON::decode_json($res->content);
}

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

App::CPAN::Fresh - Query and install CPAN modules realtime from the fresh mirror

=head1 DESCRIPTION

App::CPAN::Fresh is a backend for I<cpanf> command.

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<cpanf>

=cut
