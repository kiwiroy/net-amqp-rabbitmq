use Test::More tests => 16;
use strict;
use warnings;

use FindBin qw/$Bin/;
use lib "$Bin/lib";
use NAR::Helper;
use POSIX;
use sigtrap qw/ALRM/;

our $waiting = 1;

# Failure here results in a blocking wait which will never clear.
$SIG{ALRM} = sub {
  die("ack!") unless !$waiting;
};

my $helper = NAR::Helper->new;

ok $helper->connect, "connected";
ok $helper->channel_open, "channel_open";

ok $helper->exchange_declare( { exchange_type => 'headers', auto_delete => 0 } ), "default exchange declare";
my $queue = $helper->queue_declare( { auto_delete => 0 }, undef, 1 );
ok $queue, "queue_declare";

my $headers = { foo => '😊😭' };
my $declared_headers = {'foo' => utf8::downgrade($headers->{foo}) };
ok $helper->queue_bind( $queue, undef, undef, $declared_headers ), "queue bind";
ok $helper->drain( $queue ), "drain queue";

# This message doesn't have the correct headers so will not be routed to the queue
ok $helper->publish( "Unroutable" ), "publish unroutable message";
ok $helper->publish( "Routable", { headers => $headers } ), "publish routable message";

ok $helper->consume( $queue );

# Set an alarm
POSIX::alarm(5);
my $msg = $helper->recv;
$waiting = 0;
ok $msg, "recv";
is $msg->{body}, "Routable", "Got expected message";

my $message_count;

ok $helper->queue_unbind( $queue, undef, undef, $headers ), "queue_unbind";
ok $helper->queue_delete( $queue );
ok !$helper->queue_bind( $queue, undef, undef, $headers ), "queue bind";

# Let's do some negative testing
ok !$helper->queue_bind( "", undef, undef, $headers  ), "Binding to queue without a queue name";
ok !$helper->queue_bind( $queue, "", undef, $headers  ), "Binding to queue without an exchange";

END {
    #reconnect first
    $helper->connect;
    $helper->channel_open;

    $helper->exchange_delete;
    $helper->channel_close;
    $helper->disconnect;
}
