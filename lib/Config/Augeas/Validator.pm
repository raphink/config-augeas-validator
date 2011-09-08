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
use File::Find;

our $VERSION = '0.103';

sub new {
   my $class = shift;
   my %options = @_;

   my $self = __PACKAGE__->SUPER::new();

   $self->{conffile} = $options{conf};
   $self->{rulesdir} = $options{rulesdir};
   $self->{rulesdir} ||= "/etc/augeas-validator/rules.d";

   $self->{verbose} = $options{verbose};
   $self->{debug} = $options{debug};

   $self->{verbose} = 1 if $self->{debug};

   $self->{recurse} = $options{recurse};

   $self->{nofail} = $options{nofail};

   # Init hourglass
   $self->{tick} = 0;

   unless ($self->{conffile}) {
      assert_notempty('rulesdir', $self->{rulesdir});
   }

   $self->{aug} = Config::Augeas->new( "no_load" => 1 );

   # Instantiate general error
   $self->{err} = 0;

   return $self;
}

sub load_conf {
   my ($self, $conffile) = @_;

   $self->info_msg("Loading rule file $conffile");

   $self->{cfg} = new Config::IniFiles( -file => $conffile );
   die "E:[$conffile]: Section 'DEFAULT' does not exist.\n"
      unless $self->{cfg}->SectionExists('DEFAULT');
}


sub init_augeas {
   my ($self) = @_;

   # Initialize Augeas
   $self->{lens} = $self->{cfg}->val('DEFAULT', 'lens');
   assert_notempty('lens', $self->{lens});
   $self->{aug}->rm("/augeas/load/*[label() != \"$self->{lens}\"]");
}

sub play_one {
   my ($self, @files) = @_;

   # Get rules
   @{$self->{rules}} = split(/,\s*/,
                       $self->{cfg}->val('DEFAULT', 'rules'));

   # Get return error code
   $self->{err_code} = $self->{cfg}->val('DEFAULT', 'err_code') || 1;

   $self->init_augeas;

   for my $file (@files) {
      unless (-e $file) {
         $self->die_msg("No such file $file");
      }
      $self->info_msg("Parsing file $file");
      $self->set_aug_file($file);
      for my $rule (@{$self->{rules}}) {
         $self->info_msg("Applying rule $rule to $file");
         $self->play_rule($rule, $file);
      }
   }
}

sub filter_files {
   my ($files, $pattern, $exclude) = @_;

   my @filtered_files;
   foreach my $file (@$files) {
      if ($file =~ /^$pattern$/ && $file !~ /^$exclude$/) {
         push @filtered_files, $file;
      }
   }

   return \@filtered_files;
}

sub tick {
   my ($self) = @_;

   $self->{tick}++;
   my $tick = $self->{tick} % 4;

   my $hourglass; 
   print "\r";
    
   $hourglass = "|"  if ( $tick == 0 ); 
   $hourglass = "/"  if ( $tick == 1 ); 
   $hourglass = "-"  if ( $tick == 2 ); 
   $hourglass = "\\" if ( $tick == 3 ); 

   print "I: Recursively analyzing directories $hourglass\r";
}

sub play {
   my ($self, @infiles) = @_;

   my @files;
   if ($self->{recurse}) {
     find sub { push @files, $File::Find::name if -e; $self->tick if $self->{verbose} }, @infiles;
     print "\n" if $self->{verbose};
   } else {
      @files = @infiles;
   }
   
   if ($self->{conffile}) {
      $self->load_conf($self->{conffile});
      $self->play_one(@files);
   } else {
      my $rulesdir = $self->{rulesdir};
      opendir (RULESDIR, $rulesdir)
         or die "E: Could not open rules directory $rulesdir: $!\n";
      while (my $conffile = readdir(RULESDIR)) {
         next unless ($conffile =~ /.*\.ini$/);
         $self->{conffile} = "$rulesdir/$conffile";
         $self->load_conf($self->{conffile});
         next unless ($self->{cfg}->val('DEFAULT', 'pattern'));
         my $pattern = $self->{cfg}->val('DEFAULT', 'pattern');
         my $exclude = $self->{cfg}->val('DEFAULT', 'exclude');
         $exclude ||= '^$';
   
         my $filtered_files = filter_files(\@files, $pattern, $exclude);
         my $elems = @$filtered_files;
         next unless ($elems > 0);
   
         $self->play_one(@$filtered_files);
      }
      closedir(RULESDIR);
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

   my $err_lens_path = "/augeas/load/$lens/error";
   my $err_lens = $aug->get($err_lens_path);
   if ($err_lens) {
      $self->err_msg("Failed to load lens $lens");
      $self->err_msg($aug->print($err_lens_path));
   }

   my $err_path = "/augeas/files$absfile/error";
   my $err = $aug->get($err_path);
   if ($err) {
      my $err_line_path = "/augeas/files$absfile/error/line";
      my $err_line = $aug->get($err_line_path);
      my $err_char_path = "/augeas/files$absfile/error/char";
      my $err_char = $aug->get($err_char_path);

      $self->err_msg("Failed to parse file $file");
      my $err_msg = ($err eq "parse_failed") ?
         "Parsing failed on line $err_line, character $err_char."
         : $aug->print($err_path);
      $self->die_msg($err_msg);
   }
}

sub confname {
   my ($self) = @_;

   assert_notempty('conffile', $self->{conffile});
   my $confname = $self->{conffile};
   $confname =~ s|.*/||;
   return $confname;
}


sub print_msg {
   my ($self, $msg, $level) = @_;

   $level ||= "E";

   my $confname = $self->confname();
   print STDERR "$level:[$confname]: $msg\n";
}

sub err_msg {
   my ($self, $msg) = @_;

   $self->print_msg($msg, 'E');
}

sub die_msg {
   my ($self, $msg) = @_;

   $self->err_msg($msg);
   exit(1) unless $self->{nofail};
}

sub info_msg {
   my ($self, $msg) = @_;

   $self->print_msg($msg, 'I') if $self->{verbose};
}

sub debug_msg {
   my ($self, $msg) = @_;

   $self->print_msg($msg, 'D') if $self->{debug};
}


sub play_rule {
   my ($self, $rule, $file) = @_;

   unless ($self->{cfg}->SectionExists($rule)) {
      $self->die_msg("Section '$rule' does not exist");
   }
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
   my $level = $self->{cfg}->val($rule, 'level');
   $level ||= 'error';

   $self->assert($name, $type, $expr, $value, $file, $explanation, $level);
}


sub print_error {
   my ($self, $level, $file, $msg, $explanation) = @_;

   $self->print_msg("File $file", $level);
   $self->print_msg($msg, $level);
   print STDERR "   $explanation.\n";
}


sub assert {
   my ($self, $name, $type, $expr, $value, $file, $explanation, $level) = @_;

   if ($type eq 'count') {
      my $count = $self->{aug}->count_match("$expr");
      if ($count != $value) {
         my $msg = "Assertion '$name' of type $type returned $count for file $file, expected $value:";
         if ($level eq "error") {
            $self->print_error("E", $file, $msg, $explanation);
	    $self->{err} = $self->{err_code};
         } elsif ($level eq "warning") {
            $self->print_error("W", $file, $msg, $explanation);
         } else {
            $self->die_msg("Unknown level $level for assertion '$name'");
         }
      }
   } else {
      $self->die_msg("Unknown type '$type'");
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
   my $validator = Config::Augeas::Validator->new(rulesdir => $rulesdir);

   $validator->play(@files);
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

=item B<level>

The importance level of the test. Possible values are 'error' (default) and 'warning'.
When set to 'error', a failed test will interrupt the processing and set the return code.
When set to 'warning', a failed test will display a warning, continue, and have no effect on the return code.

C<level=warning>

=back


=head1 SEE ALSO

L<Config::Augeas>

=head1 FILES

F</etc/augeas-validator/rules.d>
    The default rules directory for B<Config::Augeas::Validator>.

=cut

