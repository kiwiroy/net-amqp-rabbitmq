use Test::More;
use strict;
use warnings;

use FindBin qw/$Bin/;
use lib "$Bin/lib";
use NAR::Helper;

my $helper = NAR::Helper->new;
my $has_lwp = eval q{ use LWP::UserAgent; 1 };
if ( !$has_lwp ) {
    plan skip_all => 'LWP::UserAgent not available';
}
else {
    plan tests => 12;
}

ok $helper->connect, "connected";
ok $helper->channel_open, "channel_open";

my @dtags=( 1, 2 );

ok $helper->exchange_declare( { exchange_type => "fanout", passive => 0, durable => 1, auto_delete => 1 } ), "exchange declare";
ok $helper->queue_declare, "queue declare";
ok $helper->queue_bind, "queue bind";
ok $helper->consume, "consume";

# XXX Temporarily use LWP::UserAgent to inject boolean values.
#     This might be rewritten once it's possible to publish
#     boolean values with Net::AMQP::RabbitMQ itself.
my $ua = LWP::UserAgent->new;
my $url = "http://$helper->{username}:$helper->{password}\@$helper->{host}:15672/api/exchanges/%2F/$helper->{exchange}/publish";
for my $test_def (['true', 1], ['false', 0]) {
    my($boolean_value, $perl_value) = @$test_def;
    my $resp = $ua->post($url, Content => <<"EOF");
{"properties":{"headers":{"booltest":$boolean_value,"boollist":[true,false]}},"routing_key":"$helper->{routekey}","payload":"test boolean","payload_encoding":"string"}
EOF
    ok $resp->is_success, "Publishing message with boolean value $boolean_value"
    or die "Publishing booltest message failed: " . $resp->as_string;

    my $rv = $helper->recv;
    ok $rv, "recv";

    my $expected_dtag = shift @dtags;
    is_deeply(
        $rv,
        {
            body         => 'test boolean',
            routing_key  => $helper->{routekey},
            delivery_tag => $expected_dtag,
            redelivered  => 0,
            exchange     => $helper->{exchange},
            consumer_tag => 'ctag',
            props        => {
                headers => {
                    booltest => $perl_value,
                    boollist => [ 1, 0 ]
                }
            },
        },
        "payload and header with boolean value $boolean_value"
    );
}

END {
    if ( $has_lwp ) {
        $helper->cleanup;
    }
}
