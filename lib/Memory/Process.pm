use strict;
use warnings;
package Memory::Process;

# ABSTRACT: Peek/Poke other processes' address spaces
# VERSION

use Carp;
use Sentinel;
use Scalar::Util 'looks_like_number';
use Inline  'C' => 'DATA' =>
            enable => autowrap =>
            LIBS => '-lvas';

=pod

=encoding utf8

=head1 NAME

Memory::Process - Peek/Poke other processes' address spaces


=head1 SYNOPSIS

    use Memory::Process;

    my $mem = Memory::Process->new(pid => 123);

    my $byte = $mem->peek(0x1000);
    my $u32  = $mem->read(0x1000, 4);
    $mem->poke(0x1000, 'L') = 12;


=head1 DESCRIPTION

PEEK/POKE are a BASIC programming language extension for reading/writing the contents of a memory cell at a specified address. This module brings similiar semantics to Perl.

Eventually, Memory searching capability will also be added.

=head1 IMPLEMENTATION

The module leverages L<libvas|http://github.com/a3f/libvas> for accessing the other virtual address spaces.

=head1 METHODS AND ARGUMENTS

=over 4

=item new(pid)

Constructs a new Memory::Process instance.

=cut

sub new {
	my $class = shift;
    my @opts = @_;
    unshift @opts, 'pid' if @_ % 2 == 1;
    
    my $self = {
        @opts
    };

    looks_like_number $self->{pid}
        or croak q/Pid isn't numeric/;

    $self->{vas} = xs_vas_open($self->{pid}, 0)
        or do {
            if (kill 0, $self->{pid}) {
                croak "PID doesn't exist"
            } else {
                croak "Process access permission denied"
            }
        };

	bless $self, $class;
	return $self;
}

=item peek(addr [, 'pack-string'])

Peeks at the given memory address. If no pack-string is specified, a single byte is read.

=cut

sub peek {
    my $self = shift;
    my $addr = shift;
    my $fmt = shift // 'C';
    $fmt eq 'C'
        or croak 'Pack strings not supported yet';

    my $buf = xs_vas_read($self->{vas}, $addr, 1);
    return $buf;
}

=item read(addr, size)

Reads size bytes from given memory address.

=cut

#SV *xs_vas_read(void* vas, unsigned long src, size_t size) {
sub read {
    my $self = shift;
    my $addr = shift;
    my $size = shift;

    my $buf = xs_vas_read($self->{vas}, $addr, $size);
    return $buf;
}


=item poke(addr [, 'pack-string']) = $value # or = ($a, $b)

Pokes a given memory address. If no pack-string is given, the rvalue is written as is

=cut

sub get_poke {
    carp 'Useless use of poke';
    undef;
}
sub set_poke {
    my @args = @{+shift};
    my $self   = shift @args;
    my $buf = shift;
    my $addr  = shift @args or croak 'Address must be specified';
    if (my $fmt = shift @args) {
        $buf = &CORE::pack($fmt, ref($buf) eq 'ARRAY' ? @{$buf} : $buf);
    }

    my $nbytes = xs_vas_write($self->{vas}, $addr, $buf, length $buf);
    return $nbytes >= 0 ? $nbytes : undef;
}

sub poke :lvalue {
    defined wantarray or croak 'Useless use of poke';
    sentinel obj => [@_], get => \&get_poke, set => \&set_poke
}

=item write(addr, buf [, count])

Writes C<buf> to C<addr>

=cut

#ssize_t xs_vas_write(void* vas, unsigned long dst, SV *sv) {
sub write {
    my $self = shift;
    my $addr = shift;
    my $buf  = shift;
    my $bytes  = shift || length $buf;

    my $nbytes = xs_vas_write($self->{vas}, $addr, $buf, $bytes);
    return $nbytes >= 0 ? $nbytes : undef;
}

=item tie(addr, 'pack-string')

Returns a tied variable which can be used like any other variable.
To be implemented

=cut

=item search('pack-string')

To be implemented when libvas provides it

=cut

Inline->init();
1;

=back

=head1 GIT REPOSITORY

L<http://github.com/athreef/Memory-Process>

=head1 SEE ALSO

L<libvas|http://github.com/a3f/libvas>

=head1 AUTHOR

Ahmad Fatoum C<< <athreef@cpan.org> >>, L<http://a3f.at>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 Ahmad Fatoum

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__DATA__
__C__

#include <vas.h>

void *xs_vas_open(int pid, int flags) {
    return vas_open(pid, flags);
}

SV *xs_vas_read(void* vas, unsigned long src, size_t size) {
    char *dst;
    ssize_t nbytes;

    SV *sv = newSV(0);
    Newx(dst, size, char);

    nbytes = vas_read(vas, src, dst, size);
    sv_usepvn_flags(sv, dst, nbytes, SV_SMAGIC | SV_HAS_TRAILING_NUL);

    if (nbytes < 0) {
        SvREFCNT_dec(sv);
        return newSVsv(&PL_sv_undef);
    } else
        return sv;
}

ssize_t xs_vas_write(void* vas, unsigned long dst, SV *sv, size_t size) {
    ssize_t nbytes;

    nbytes = vas_write(vas, dst, SvPV_nolen(sv), size);
    return nbytes;
}

