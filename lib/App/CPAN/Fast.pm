package App::CPAN::Fast;

use strict;
use 5.008_001;
our $VERSION = '0.02';

use base qw(App::Cmd::Simple);

use Carp;
use CPAN::Inject;
use File::Temp;
use JSON;
use LWP::UserAgent;
use URI;

sub opt_spec {
    return (
        [ "install|i", "install the module" ],
        [ "list|l", "list the recent uploads" ],
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
        $self->install($args);
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
    Pod::Usage::pod2usage();
}

sub install {
    my($self, $dists) = @_;

    my @injected;
    for my $dist (@$dists) {
        my $path = $self->inject($dist);
        if ($path) {
            push @injected, $path;
        } else {
            print "$dist not found.\n";
        }
    }

    if (@injected) {
        require CPAN;
        CPAN::Shell->install(@injected);
    }
}

sub inject {
    my($self, $dist) = @_;
    $dist =~ s/::/-/g;

    my $res = $self->call("/search", { q => "$dist group:cpan" });
    for my $entry (@{$res->{entries}}) {
        my $info = $self->parse_entry($entry->{body}) or next;
        if ($info->{dist} eq $dist) {
            return $self->do_inject($info);
        }
    }

    return;
}

sub do_inject {
    my($self, $info) = @_;

    my $dir = File::Temp::tempdir(CLEANUP => 1);
    my $local = "$dir/$info->{dist}-$info->{version}.tar.gz";

    my $res = $self->new_ua->mirror($info->{url}, $local);
    if ($res->is_error) {
        croak "Fetching $info->{url} failed: ", $res->status_line;
    }

    CPAN::Inject->from_cpan_config->add(file => $local);
}

sub display_results {
    my($self, $res) = @_;
    for my $entry (@{$res->{entries}}) {
        my $info = $self->parse_entry($entry->{body}) or next;
        printf "%s-%s (%s)\n", $info->{dist}, $info->{version}, $info->{author};
    }
}

sub parse_entry {
    my($self, $body) = @_;

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

App::CPAN::Fast - backend for I<cpanf> command

=head1 DESCRIPTION

App::CPAN::Fast is a backend for I<cpanf> command.

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<cpanf>

=cut
