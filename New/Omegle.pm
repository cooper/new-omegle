#!/usr/bin/perl
# Copyright (c) 2011, Mitchell Cooper
package New::Omegle;

use warnings;
use strict;
use 5.010;

use HTTP::Async;
use HTTP::Request::Common;
use JSON;

our ($VERSION, $async, $online, @servers, $updated, $lastserver) = (1.6, HTTP::Async->new, 0);
my  $last_time = time;

# New::Omegle->update()
# updates the server list, global stranger count, and other information.
sub update {
    $async->add(POST "http://omegle.com/status");
    my $data    = JSON::decode_json($async->wait_for_next_response->content); # assume success
    @servers    = @{$data->{servers}};
    $lastserver = int rand @servers;
    $updated    = time;
}

# New::Omegle->new(%opts)
# creates a New::Omegle session object.
sub new {
    my ($class, %opts) = @_;

    # they haven't called New::Omegle->update(), so I can't choose a server.
    return unless $online;

    $opts{server} = &newserver;    
    bless \%opts, $class;
}

# newserver()
# returns the index of the next server in line to be used.
sub newserver {
    $servers[$lastserver == $#servers ? $lastserver = 0 : ++$lastserver];
}

1
