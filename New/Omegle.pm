#!/usr/bin/perl
# Copyright (c) 2011, Mitchell Cooper
package New::Omegle;

use warnings;
use strict;
use 5.010;

use HTTP::Async;
use HTTP::Request::Common;
use JSON;

our ($VERSION, $async, $JSON, $online,
     $updated, @servers, $lastserver ) = (1.6, HTTP::Async->new, JSON->new, 0);
my  ($last_time, %requests, @sessions) = time;

# New::Omegle->update()
# updates the server list, global stranger count, and other information.
sub update {
    $JSON->allow_nonref;
    $async->add(POST "http://omegle.com/status");
    my $data    = $JSON->decode($async->wait_for_next_response->content); # assume success
    @servers    = @{$data->{servers}};
    $lastserver = int rand @servers;
    $online     = $data->{count};
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

# New::Omegle->go()
# requests next events
sub go {
    return if $last_time + 2 > time;
    $last_time = time;

    # get next responses
    while (my ($res, $id) = $async->next_response) {
        if ($requests{$id}) {
            $requests{$id}[0]($requests{$id}[1], $res->content);
            delete $requests{$id};
        }
    }

    # ask for more events
    foreach my $om (@sessions) {
        $om->async_post('events', [], sub {
            my ($om, $json) = @_;
            say $json;
            $json = $JSON->decode($json) or return;
            $om->handle_event(@$_) foreach @$json;
        });
    }

    # update server list and user count
    update() if $updated + 120 < time;

    1
}

# $om->start()
# registers a new session. returns omegle instance (not ID!)
sub start {
    my $om = shift;

    # start the session, fetch the id
    $om->async_post('start', [], sub {
        my ($om, $data) = @_;
        if ($data =~ m/"(.+)"/) {
            $om->{id} = $1;
            say $1;
            $om->fire('session', $1);
        }
        else {
            $om->fire('error');
        }
    });

    # add to running sessions
    push @sessions, $om;

    return $om;
}

# $om->fire($callback, @args)
# fires callbacks. intended for internal use.
sub fire {
    my ($om, $callback, @args) = @_;
    if ($om->{"on_$callback"}) {
        return $om->{"on_$callback"}(@args);
    }
    return;
}

# $om->handle_event(@event)
# handles an event from /events. intended for internal use.
sub handle_event {
    my ($om, @event) = @_;
    given ($event[0]) {

        # session established
        when ('connected') {
            $om->fire('connect');
            $om->{connected} = 1;
        }

        # stranger said something
        when ('gotMessage') {
            $om->fire('chat', $event[1]);
            delete $om->{typing};
        }

        # stranger disconnected
        when ('strangerDisconnected') {
            $om->fire('disconnect');
            delete $om->{id};
            delete $om->{connected};
        }

        # stranger is typing
        when ('typing') {
            $om->fire('type') unless $om->{typing};
            $om->{typing} = 1;
        }

        # stranger stopped typing
        when ('stoppedTyping') {
            $om->fire('stoptype') if $om->{typing};
            delete $om->{typing};
        }

        # stranger has similar interests
        when ('commonLikes') {
            $om->fire('commonlikes', $event[1]);
        }

        # number of people online
        when ('count') {
            $online = $event[1];
            $om->fire('count', $event[1]);
        }

        # server requests captcha
        when (['recaptchaRequired', 'recaptchaRejected']) {

        }
    }
    return 1;
}

# $om->async_post($page, $args, $callback)
# asynchronously sends a POST request and calls the callback with its response.
# intended for internal use.
sub async_post {
    my ($om, $page, $args, $callback) = @_;
    $args  = [@$args, id => $om->{id} ] if $om->{id};
    my $id = $async->add(POST "http://$$om{server}/$page", $args);
    $requests{$id} = [$callback, $om];
}

# newserver()
# returns the index of the next server in line to be used.
sub newserver {
    $servers[$lastserver == $#servers ? $lastserver = 0 : ++$lastserver];
}

1
