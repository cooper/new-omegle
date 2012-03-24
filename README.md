# New::Omegle

This is a Perl interface to Omegle.com. It supports all Omegle events, allowing your program to respond to messages, typing, stopped typing, connects, and disconnects.
Using HTTP::Async, it is completely non-blocking and can be placed anywhere in your program. Recently, support has been added for using Omegle's reCAPTCHA API.

## license
You are free to modify and redistribute New::Omegle under the terms of the New BSD license. See LICENSE.

## variables

New::Omegle has a two package variables for your use.

- __$New::Omegle::online__: the number of users on Omegle. it can be refreshed with the update() method of any New::Omegle instance.
- __@New::Omegle::servers__: if dynamic server select is enabled, this is the list of available Omegle servers as fetched by update().

## methods

You should _definitely_ look at the example for an easy demonstration.

### $om = New::Omegle->new(%options)
Creates an Omegle session object. All options are optional. Callbacks must be CODE references.
The New::Omegle instance is the first argument of all callbacks.

- __on_connect__: callback called when the stranger connects
- __on_disconnect__: callback called when the stranger disconnects
- __on_chat__ (msg): callback called when the stranger sends a message
- __on_type__: callback called when the stranger begins to type
- __on_stoptype__: callback called when the stranger stops typing
- __on_commonlikes__ (likes): callback called when common interests are found
- __on_gotcaptcha__ (image URL): callback called when human verification is required
- __use_likes__: true if you wish to look for strangers similar to you
- __topics__: array reference of your interests
- __server__: specify a server (by default it alternates through all servers)
- __static__: if true, do not cycle through server list

```perl
my $om = New::Omegle->new(
    on_chat        => \&chat_cb,
    on_type        => \&type_cb,
    on_stoptype    => \&stoptype_cb,
    on_disconnect  => \&disconnect_cb,
    on_connect     => \&connect_cb,
    on_commonlikes => \&commonlikes_cb,
    on_gotcaptcha  => \&gotcaptcha_cb,
    server         => 'bajor.omegle.com',  # don't use this option without reason
    topics         => ['IRC', 'Omegle', 'ponies'],
    use_likes      => 1
);
```

### $om->start()
Connects to Omegle and returns your session's ID. start() also sets the "id" key of the object.

```perl
my $id = $om->start();
```

### $om->go()
Perhaps the most important method - checks for new events, handles pending events, etc. You probably want to put this in the "main loop" of your program.
Returns the last HTTP::Async object or `undef` if there is no session connected.

```perl
while (1) {
    $om->go();
    sleep 1
}
```

### $om->type()
Makes it appear that you are typing.
Returns the last HTTP::Async object or `undef` if there is no session connected.

```perl
$om->type();
```

### $om->stoptype()
Makes it appear that you have stopped typing.
Returns the last HTTP::Async object or `undef` if there is no session connected.

```perl
$om->stoptype();
```

### $om->say($message)
Sends a message to the stranger.
Returns the last pending HTTP::Async object or `undef` if there is no session connected.

```perl
$om->say('heybby :]');
```

### $om->disconnect()
Disconnects from the current session.
Returns the last pending HTTP::Async object or `undef` if there is no session connected.
You can immediately start a new session on the same object with `$om->start()`.

```perl
$om->disconnect();
```

### $om->submit_captcha($answer)
Submits a response to recaptcha. If incorrect, a new captcha will be presented.

### $om->update()
Updates the Omegle server list and online user count. You typically don't need to use
this directly.
