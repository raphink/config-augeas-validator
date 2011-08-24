#    Copyright (c) 2011 Raphaël Pinson.
#
#    This library is free software; you can redistribute it and/or
#    modify it under the terms of the GNU Lesser Public License as
#    published by the Free Software Foundation; either version 2.1 of
#    the License, or (at your option) any later version.
#
#    Config-Model is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#    Lesser Public License for more details.
#
#    You should have received a copy of the GNU Lesser Public License
#    along with Config-Model; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
#    02110-1301 USA

package Config::Augeas::Validator;

use strict;
use warnings;
use base qw(Class::Accessor);
use Config::Augeas qw(get count_match print);
use Config::IniFiles;

our $VERSION = '0.0.1';

sub new {
   my $class = shift;
   my %options = @_;

   my $self = __PACKAGE__->SUPER::new();

   my $conffile = $options{conf};
   assert_notempty('conf', $conffile);
   $self->load_conf($conffile);

   # Get rules
   @{$self->{rules}} = split(/,\s*/,
                       $self->{cfg}->val('DEFAULT', 'rules'));

   $self->init_augeas;

   # Instantiate general error
   $self->{err} = 0;

   # Get return error code
   $self->{err_code} = $self->{cfg}->val('DEFAULT', 'err_code') || 1;

   return $self;
}


sub load_conf {
   my ($self, $conffile) = @_;

   $self->{cfg} = new Config::IniFiles( -file => $conffile );
   die "E: Section 'DEFAULT' does not exist in $conffile\n"
      unless $self->{cfg}->SectionExists('DEFAULT');
}


sub init_augeas {
   my ($self) = @_;

   # Initialize Augeas
   $self->{lens} = $self->{cfg}->val('DEFAULT', 'lens');
   assert_notempty('lens', $self->{lens});
   $self->{aug} = Config::Augeas->new( "no_load" => 1 );
   $self->{aug}->rm("/augeas/load/*[label() != \"$self->{lens}\"]");
}


sub play_all {
   my ($self, @files) = @_;
   for my $file (@files) {
      die "E: No such file $file\n" unless (-e $file);
      $self->set_aug_file($file);
      for my $rule (@{$self->{rules}}) {
         $self->play_rule($rule, $file);
      }
   }
}


sub set_aug_file {
   my ($self, $file) = @_;

   my $absfile = `readlink -f $file`;
   chomp($absfile);

   my $aug = $self->{aug};
   my $lens = $self->{lens};


   if ($aug->count_match("/augeas/load/$lens/lens") == 0) {
      # Lenses with no autoload xfm => bet on lns
      $aug->set("/augeas/load/$lens/lens", "$lens.lns");
   }
   $aug->rm("/augeas/load/$lens/incl");
   $aug->set("/augeas/load/$lens/incl", $absfile);
   $aug->defvar('file', "/files$absfile");
   $aug->load;

   my $err_path = "/augeas/files$absfile/error";
   my $err = $aug->get($err_path);
   if ($err) {
      print "E: Failed to parse file $file\n";
      print $aug->print($err_path);
      exit(1);
   }
}


sub play_rule {
   my ($self, $rule, $file) = @_;

   die "E: Section '$rule' does not exist\n" unless $self->{cfg}->SectionExists($rule);
   my $name = $self->{cfg}->val($rule, 'name');
   assert_notempty('name', $name);
   my $type = $self->{cfg}->val($rule, 'type');
   assert_notempty('type', $type);
   my $expr = $self->{cfg}->val($rule, 'expr');
   assert_notempty('expr', $expr);
   my $value = $self->{cfg}->val($rule, 'value');
   assert_notempty('value', $value);
   my $explanation = $self->{cfg}->val($rule, 'explanation');
   $explanation ||= '';

   $self->assert($name, $type, $expr, $value, $file, $explanation);
}


sub assert {
   my ($self, $name, $type, $expr, $value, $file, $explanation) = @_;

   if ($type eq 'count') {
      my $count = $self->{aug}->count_match("$expr");
      if ($count != $value) {
         print "E: File $file\n";
         print "E: Assertion '$name' of type $type returned $count for file $file, expected $value:\n";
	 print "   $explanation.\n";
	 $self->{err} = $self->{err_code};
      }
   } else {
      die "E: Unknown type '$type'\n";
   }
}


sub assert_notempty {
   my ($name, $var) = @_;

   die "E: Variable '$name' should not be empty\n"
      unless (defined($var)); 
}


1;


__END__


=head1 NAME

   Config::Augeas::Validator - A generic configuration validator API

=head1 SYNOPSIS

   use Config::Augeas::Validator;

   # Initialize
   my $validator = Config::Augeas::Validator->new(conf => $conffile);

   $validator->play_all(@files);
   exit $validator->{err};


=head1 CONFIGURATION

The B<Config::Augeas::Validator> configuration files are INI files.

=head2 DEFAULT SECTION

The B<DEFAULT> section is mandatory. It contains the following variables:

=over 8

=item B<rules>

The ordered list of the rules to run, separated with commas, for example:

C<rules=app_type, ai_bo_auth, dr_auth>

=item B<lens>

The name of the lens to use, for example:

C<lens=Httpd>

=item B<err_code>

The exit code to return when a test fails. This parameter is optional. Example:

C<err_code=3>

=back

=head2 RULES

Each section apart from the B<DEFAULT> section defines a rule, as listed in the B<rules> variable of the B<DEFAULT> section. Each rule contains several parameters.

=over 8

=item B<name>

The rule description, for example:

C<name=Application Type>

=item B<explanation>

The explanation for the rule, for example:

C<explanation=Check that application type is FOO or BAR>

=item B<type>

The type of rule. For now, B<Config::Augeas::Validator> only supports the B<count> type, which returns the count nodes matching B<expr>. Example:

C<type=count>

=item B<expr>

The B<Augeas> expression for the rule. The C<$file> variable is the path to the file in the B<Augeas> tree. Example:

C<expr=$file/VirtualHost[#comment =~ regexp("^1# +((AI|BO)\+?|DR)$")]>

=item B<value>

The value expected for the test. For example, if using the count type, the number of matches expected for the expression. Example:

C<value=1>


=back


=head1 SEE ALSO

L<Config::Augeas>

=head1 FILES

F<augeas-validator.ini>
    The default configuration file for B<Config::Augeas::Validator>.

=cut

