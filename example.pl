#!/usr/bin/perl
use warnings;
use strict;

use New::Omegle;

# this creates an omegle object. you can have as many
# objects as you wish to have, each connecting to
# separate omegle sessions. all callbacks are optional.
# there is also a "server" option to specify a server.
# if no server is provided, one will be chosen at random.
my $om = New::Omegle->new(
    on_chat       => \&chat_cb,
    on_type       => \&type_cb,
    on_stoptype   => \&stoptype_cb,
    on_disconnect => \&disconnect_cb,
    on_connect    => \&connect_cb
);

# this creates a new Omegle session and returns the ID.
# it also sets the "id" key of your session object.
$om->start();

while (1) {
    # the go() method checks for new events and handles
    # pending events. you can place this anywhere, such
    # as the main loop of your program or bot.
    $om->go();

    # you can throw anything in your loop, making it
    # suitable for programs such as IRC bots
    print "do something else because it doesn't block! :O\n";

    # make it appear that you are typing
    $om->type();

    # make it appear that you have stopped typing
    $om->stoptype();

    # send a message
    $om->say('Hello world!');

    sleep 1 # probably a good idea to limit your
            # event request rate
}

# connect callback:
# called when the stranger connects
sub connect_cb {
    my $om = shift;
    print "You are now chatting with $$om{id}. Say hi!\n"
}

# chat callback:
# called when the stranger chats with you
sub chat_cb {
    my ($om, $message) = @_;
    print "$$om{id} says: $message\n"
}

# type callback:
# called when the stranger begins to type
sub type_cb {
    my $om = shift;
    print "$$om{id} is typing...\n"
}

# stoptype callback:
# called when the stranger stops typing
sub stoptype_cb {
    my $om = shift;
    print "$$om{id} has stopped typing.\n"
}

# disconnect callback:
# called when the stranger disconnects
sub disconnect_cb {
    my $om = shift;
    print "$$om{id} has disconnected.\n"
}

1
