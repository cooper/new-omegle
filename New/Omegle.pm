#!/usr/bin/perl
# Copyright (c) 2011-2012, Mitchell Cooper
package New::Omegle;

use warnings;
use strict;
use 5.010;

use HTTP::Async;
use HTTP::Request::Common;
use Furl;
use JSON;
use URI::Escape::XS;

our ($VERSION, $online, $ua, @servers,
     $updated, $lastserver, %response) = (3.1, 0, Furl->new);

# New::Omegle->new(%opts)
# creates a new New::Omegle session instance.
sub new {
    my ($class, %opts) = @_;
    update() if !$online;
    $opts{async} = HTTP::Async->new;
    bless my $om = \%opts, $class;
    return $om;
}

# $om->start()
# establishes a new omegle session and returns its id.
sub start {
    my $om = shift;
    $om->{last_time} = time;
    $om->{async}   ||= HTTP::Async->new;
    $om->{server}    = &newserver unless $om->{static};

    my $startopts = '?rcs=&spid=';

    # enable question mode
    if ($om->{use_question}) {
        $om->{spysession} = 1;
        $startopts .= '&ask='.encodeURIComponent($om->{question});
    }

    # get ID
    _post("http://$$om{server}/start$startopts") =~ m/^"(.+)"$/;
    $om->{id} = $1;

    $om->{stopsearching} = time() + 5 if $om->{use_likes};
    return $om->{id};
}

# $om->say($msg)
# send a message
sub say {
    my ($om, $msg) = @_;
    return if $om->{spysession};
    return unless $om->{id};
    $om->post('send', [ msg => $msg ]);
}

# om->type()
# make it appear that you are typing
sub type {
    my $om = shift;
    return if $om->{spysession};
    return unless $om->{id};
    $om->post('typing');
}

# $om->stoptype()
# make it appear that you have stopped typing
sub stoptype {
    my $om = shift;
    return if $om->{spysession};
    return unless $om->{id};
    $om->post('stoptyping');
}

# $om->disconnect()
# disconnect from the stranger
sub disconnect {
    my $om = shift;
    return unless $om->{id};
    $om->post('disconnect');
    delete $om->{connected};
    delete $om->{id};
    delete $om->{spysession};
}

# $om->submit_captcha($solution)
# submit recaptcha request
sub submit_captcha {
    my ($om, $response) = @_;
    $om->post('recaptcha', [
        challenge => delete $om->{challenge},
        response  => $response
    ]);
}

# $om->go()
# request and handle events: put this in your main loop
sub go {
    my $om = shift;
    return unless $om->{id};
    return if (($om->{last_time} + 2) > time);

    # stop searching for common likes
    if (defined $om->{stopsearching} && $om->{stopsearching} >= time) {
        $om->post('stoplookingforcommonlikes');
        $om->fire('stopsearching');
        delete $om->{stopsearching};
    }

    # look for new events
	foreach my $res ($om->get_next_events) {
	    next unless $res->[0];
        $om->handle_events($res->[0]->content, $res->[1]);
    }

    # update server list and user count
    update() if $updated && $updated + 300 < time;

    $om->request_next_event;
    $om->{last_time} = time;
}

# $om->request_next_event()
# asks the omegle server for more events. intended for internal use.
sub request_next_event {
    my $om = shift;
    return unless $om->{id};
    $om->post('events');
}

# $om->get_next_events
# returns an array of array references [response, id]
# intended for internal use.
sub get_next_events {
    my $om = shift;
    my @f = ();
    while (my @res = $om->{async}->next_response) { push @f, \@res }
    return @f;
}

# $om->handle_json($data, $req_id)
# parse JSON data and interpret it as individual events.
# intended for internal use.
sub handle_events {
    my ($om, $data, $req_id) = @_;

    # waiting handler
    if ($response{$req_id}) {
        return unless (delete $response{$req_id})->($data);
    }

    # array of events must start with [
    return unless $data =~ m/^\[/;

    # event JSON
    my $events = JSON::decode_json($data);
    foreach my $event (@$events) {
        $om->handle_event(@$event);
    }
}

# $om->fire($callback, @args)
# fires callbacks. intended for internal use.
sub fire {
    my ($om, $callback, @args) = @_;
    if ($om->{"on_$callback"}) {
        return $om->{"on_$callback"}($om, @args);
    }
    return;
}

# $om->handle_event(@event)
# handles a single event from parsed JSON. intended for internal use.
sub handle_event {
    my ($om, @event) = @_;
#server::lookup_by_name('AlphaChat')->privmsg('#cooper', "EVENT: $event[0](@event[1..$#event])");
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

        # question is asked
        when ('question') {
            $om->fire('question', $event[1]);
        }

        # spyee disconnected
        when ('spyDisconnected') {
            my $which = $event[1];
            $which =~ s/Stranger //;
            $om->fire('spydisconnect', $which);
            delete $om->{spysession};
        }

        # spyee is typing
        when ('spyTyping') {
            my $which = $event[1];
            $which =~ s/Stranger //;
            $om->fire('spytype', $which) unless $om->{"typing_$which"};
            $om->{"typing_$which"} = 1;
        }

        # spyee stopped typing
        when ('spyStoppedTyping') {
            my $which = $event[1];
            $which =~ s/Stranger //;
            $om->fire('spystoptype', $which);
            delete $om->{"typing_$which"};
        }

        # spyee said something
        when ('spyMessage') {
            my $which = $event[1];
            $which =~ s/Stranger //;
            $om->fire('spychat', $which, $event[2]);
            delete $om->{"typing_$which"};
        }


        # number of people online
        when ('count') {
            $online = $event[1];
            $om->fire('count', $event[1]);
        }

        # server requests captcha
        when (['recaptchaRequired', 'recaptchaRejected']) {
            $om->fire('wantcaptcha');
            my $data = _get("http://google.com/recaptcha/api/challenge?k=$event[1]&ajax=1");
            return unless $data =~ m/challenge : '(.+)'/;
            $om->{challenge} = $1;
            $om->fire('gotcaptcha', "http://www.google.com/recaptcha/api/image?c=$1");
        }
    }
    return 1
}

# $om->post($page, $options)
# asynchronously posts a request but does not wait for a response.
# intended for internal use.
sub post {
    my ($om, $event, @opts) = (shift, shift, @{+shift || []});
    $om->{async}->add(POST "http://$$om{server}/$event", [ id => $om->{id}, @opts ]);
}

# $om->get($page, $options)
# asynchronously gets a request but does not wait for a response.
# intended for internal use.
sub get {
    my ($om, $event, @opts) = (shift, shift, @{+shift || []});
    $om->{async}->add(GET "http://$$om{server}/$event", [ id => $om->{id}, @opts ]);
}

# update()
# update status, user count, and server list. intended for internal use.
sub update {
    my $data    = JSON::decode_json(_get('http://omegle.com/status'));
    @servers    = @{$data->{servers}};
    $lastserver = $#servers;
    $online     = $data->{count};
    $updated    = time;
}

# newserver()
# returns the index of the next server in line to be used
sub newserver {
    $servers[$lastserver == $#servers ? $lastserver = 0 : ++$lastserver];
}

# _post($url, $args)
# _get ($url, $args)
# returns the content of a request. intended for internal use.
sub _post { $ua->post(shift, [], @{+shift || []})->content }
sub _get  { $ua->get (shift, [], @{+shift || []})->content }

1
