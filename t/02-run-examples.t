use warnings;
use strict;
use Test::More tests => 1;
use Config::Augeas::Validator;

my $validator = Config::Augeas::Validator->new(conf => "examples/sudo.ini");
$validator->play_all('fakeroot/etc/sudoers');
is($validator->{err}, '0', "Sudo test returned without error");

