package Compiler::Closure;
use strict;
use warnings;

use LWP::UserAgent;
use HTTP::Request::Common;
use FileHandle;

# warning level
use constant DEFAULT => 'DEFAULT';
use constant QUIET   => 'QUIET';
use constant VERBOSE => 'VERBOSE';

# compliation level
use constant SIMPLE     => 'SIMPLE_OPTIMIZATIONS';
use constant WHITESPACE => 'WHITESPACE_ONLY';
use constant ADVANCED   => 'ADVANCED_OPTIMIZATIONS';

sub new {
    my $class = shift;
    bless {
        js_code => undef,
        ua => undef,
        level => undef,
        info => undef,
        output => {},
        sources => [],
        signatures => [],
        @_
    }, $class;
}

sub base_dir {
    shift->{base_dir}||''
}

sub compiled_path {
    my $self = shift;
    my $r = $self->{output}->{compiled};
    return '' unless $r;
    $self->base_dir.$r;
}

sub raw_path {
    my $self = shift;
    my $r = $self->{output}->{raw};
    return '' unless $r;
    $self->base_dir.$r;
}
        
sub level { shift->{level} || SIMPLE }
sub info  { shift->{info}  || 'compiled_code' }
sub warning_level { shift->{warning_level} || DEFAULT }

sub compile {
    my $self = shift;
    $self->{js_code} = shift if @_;
    
    my $jscode = $self->{js_code};
    
    $jscode .= $self->_concat_files($self->{sources} ,1);

    $self->_write_to_file(
        $self->raw_path,
        $self->signature.$jscode
    );
    my $out = $self->{jar} ?
        $self->compile_with_jar($jscode) :
        $self->compile_with_request($jscode);

    $self->_write_to_file($self->compiled_path,$self->signature.";$out");
    
}

sub signature {
    my $self = shift;
    $self->{_signature} ||= $self->_concat_files($self->{signatures});
}

sub compile_with_jar {
    my ($self,$jscode) = @_;
    my $jar   = $self->{jar};
    $jar = $self->base_dir.$jar unless $jar =~ /^€/.+/;
    my $level = $self->level;
    my $wlv   = $self->warning_level;
    
    my $rpath = ".closure.raw.js";
    my $cpath = ".closure.compliled.js";
    
    $self->_write_to_file($rpath,$jscode);
    
    my $cmd = qq{java -jar $jar --js=$rpath --js_output_file=$cpath}
        .qq{ --compilation_level=$level}
        .qq{ --warning_level=$wlv};
    
    system($cmd);
    my $out = $self->_concat_files([$cpath]);
    unlink $rpath,$cpath;
    $out;
}

sub compile_with_request {
    my ($self,$jscode) = @_;
    $self->{ua} ||= LWP::UserAgent->new;
    my $data = {
        js_code => $jscode,
        compilation_level => $self->level,
        output_format => 'text',
        output_info => $self->info,
    };
    my $req = POST(
        'http://closure-compiler.appspot.com/compile',
        [%$data],
    );
    my $res = $self->{ua}->request($req);
    my $out = $res->content;
    die qq{[Closure returned] $out€n} if $out =~ /^Error/;
    $out;
}

sub _concat_files {
    my $self = shift;
    my $src = shift;
    my $add_comment = shift;
    return '' unless $src;
    my @sources = @{ $src };
    my $ret = '';
    foreach my $file(@sources) {
        $file = $self->base_dir.$file;
        my $fh = FileHandle->new("< $file");
        die "Couldn't open JavaScript source $file" unless $fh;
        my @lines = <$fh>;
        $ret .= ";/* $file */€n" if $add_comment;
        foreach(@lines) {
            $ret .= $_;
        }
        $ret .= "€n";
    }
    $ret;
}

sub _write_to_file {
    my ($self,$file,$content) = @_;
    return unless $file&&$content;
    my $fh = FileHandle->new("> $file");
    return unless $fh;
    print $fh $content;
    $fh->close;
}


1;