#!/usr/bin/perl -w
use ExtUtils::MakeMaker;
use Config;
use strict;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Win32API::Registry',
    'VERSION_FROM'	=> 'Registry.pm',	# finds $VERSION
    'LICENSE'           => 'perl',
    (  $Config{archname} =~ /-object\b/i  ?  ( 'CAPI' => 'TRUE' )  :  ()  ),
    (  $] < 5.005  ?  ()  :
	( 'AUTHOR'		=> 'Tye McQueen <tye@metronet.com>',
	  'ABSTRACT_FROM'	=> 'Registry.pm' )
    ),
    (	# 5.008 <= $]  ?  'CONST2PERL'  :	# Will this ever work? /:
        'postamble'
    )		=> { IMPORT_LIST => [qw(/._/ !/[a-z]/)],
		     IFDEF => q{ /^SE_/ ? '__cplusplus' : /REG_/ },
		     CPLUSPLUS => 1,
		     WRITE_PERL => 1,
		     VALUES => {
			KEY_DELETE => 'DELETE',
			KEY_READ_CONTROL => 'READ_CONTROL',
			KEY_WRITE_DAC => 'WRITE_DAC',
			KEY_WRITE_OWNER => 'WRITE_OWNER',
			KEY_SYNCHRONIZE => 'SYNCHRONIZE', # (not used)
		     },
		     # Comment out next line to rebuild constants defs:
		     NO_REBUILD => 1,
		   },
    (  ! $Config{libperl}  ?  ()  :  ( LIBPERL_A => $Config{libperl} )  ),
);

# Replacement for MakeMaker's "const2perl section" for versions
# of MakeMaker prior to the addition of this functionality:
sub MY::postamble
{
    my( $self, %attribs )= @_;

    # Don't do anything if MakeMaker has const2perl
    # that already took care of all of this:
    return   unless  %attribs;

    # Don't require these here if we just C<return> above:
    eval "use ExtUtils::Myconst2perl qw(ParseAttribs); 1"   or  die "$@";
    eval "use ExtUtils::MakeMaker qw(neatvalue); 1"   or  die "$@";

    # If only one module, can skip one level of indirection:
    my $hvAttr= \%attribs;
    if(  $attribs{IMPORT_LIST}  ) {
	$hvAttr= { $self->{NAME} => \%attribs };
    }

    my( $module, @m, $_final, @clean, @realclean );
    foreach $module (  keys %$hvAttr  ) {
	my( $outfile, @perlfiles, @cfiles, $bin, $obj, $final, $noreb );

	# Translate user-friendly options into coder-friendly specifics:
	ParseAttribs( $module, $hvAttr->{$module}, { OUTFILE => \$outfile,
	  C_FILE_LIST => \@perlfiles, PERL_FILE_LIST => \@cfiles,
	  OBJECT => \$obj, BINARY => \$bin, FINAL_PERL => \$final,
	  NO_REBUILD => \$noreb } );
	die "IFDEF option in Makefile.PL must be string, not code ref.\n"
	  if  ref $hvAttr->{$module}->{IFDEF};
	die qq{IFDEF option in Makefile.PL must not contain quotes (").\n}
	  if  ref $hvAttr->{$module}->{IFDEF};

	# How to create F<$outfile> via ExtUtils::Myconst2perl::Myconst2perl:
	push @m, "
$outfile:	@perlfiles  @cfiles  Makefile" . '
	$(PERL) "-I$(PERL_ARCHLIB)" "-I$(PERL_LIB)" -MExtUtils::Myconst2perl \\
	  -e "my %attribs;" \\
	  ';
	$m[-1] =~ s/^/##/gm   if  $noreb;
	my( $key, $value );
	while(  ( $key, $value )= each %{$hvAttr->{$module}}  ) {
	    push @m, '-e "$$attribs{' . $key . '}= '
	      . neatvalue($value) . qq[;" \\\n\t  ];
	    $m[-1] =~ s/^/##/gm   if  $noreb;
	}
	push @m, '-e "Myconst2perl(' . neatvalue($module) . ",%attribs)\"\n";

	# If requested extra work to generate Perl instead of XS code:
	if(  $bin  ) {
	    my @path= split /::/, $module;
	    my $_final= $final;
	    $_final =~ s/\W/_/g;

	    # How to compile F<$outfile> and then run it to produce F<$final>:
	    push @m, "
$bin:	$outfile" . '
	$(CC) $(INC) $(CCFLAGS) $(OPTIMIZE) $(PERLTYPE) $(LARGE) \\
	  $(SPLIT) $(DEFINE_VERSION) $(XS_DEFINE_VERSION) -I$(PERL_INC) \\
	  $(DEFINE)' . $outfile . " "
	  .  $self->catfile(qw[ $(PERL_INC) $(LIBPERL_A) ]) . " -o $bin

$final: $bin
	" .  $self->catfile(".",$bin) . " >$final\n";
	    $m[-1] =~ s/^/##/gm   if  $noreb;

	    # Make sure the rarely-used $(INST_ARCHLIB) directory exists:
	    push @m, $self->dir_target('$(INST_ARCHLIB)');

	    ##warn qq{$path[-1].pm should C<require "},
	    ##  join("/",@path,$final), qq{">.\n};
	    # Install F<$final> whenever regular pm_to_blib target is built:
	    push @m, "
pm_to_blib: ${_final}_to_blib

${_final}_to_blib: $final
	" . '@$(PERL) "-I$(INST_ARCHLIB)" "-I$(INST_LIB)" \\
	"-I$(PERL_ARCHLIB)" "-I$(PERL_LIB)" -MExtUtils::Install \\
        -e "pm_to_blib({ ',neatvalue($final),',',
	neatvalue($self->catfile('$(INST_ARCHLIB)',@path,$final)), ' },',
	neatvalue($self->catfile(qw[$(INST_LIB) auto])), ')"
	@$(TOUCH) ', $_final, "_to_blib\n";

	    push( @clean, $outfile, $bin, $obj, $_final . "_to_blib" );
	    push( @realclean, $final )   unless  $noreb;
	} else {

	    ##my $name= ( split /::/, $module )[-1];
	    ##warn qq{$name.xs should C<#include "$final"> },
	    ##  qq{in the C<BOOT:> section\n};
	    push( @realclean, $outfile )   unless  $noreb;
	}
    }

    push @m, "
clean ::
	$self->{RM_F} @clean\n"   if  @clean;
	push @m, "
realclean ::
	$self->{RM_F} @realclean\n"   if  @realclean;
	return join('',@m);
}
