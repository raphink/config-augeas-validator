use warnings;
use strict;
use Test::More tests => 2;
use Config::Augeas::Validator;

my $sudo_validator = Config::Augeas::Validator->new(conf => "examples/sudo.ini");
$sudo_validator->play_all('fakeroot/etc/sudoers');
is($sudo_validator->{err}, '0', "Sudo test returned without error");

my $sudo_fail_validator = Config::Augeas::Validator->new(conf => "examples/sudo_fail.ini");
$sudo_fail_validator->play_all('fakeroot/etc/sudoers');
isnt($sudo_fail_validator->{err}, '0', "Sudo test returned with error");

