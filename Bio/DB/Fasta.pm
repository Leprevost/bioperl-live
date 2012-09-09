#
# BioPerl module for Bio::DB::Fasta
#
# You may distribute this module under the same terms as perl itself
#


=head1 NAME

Bio::DB::Fasta - Fast indexed access to fasta files

=head1 SYNOPSIS

  use Bio::DB::Fasta;

  # Create database from a directory of Fasta files
  my $db       = Bio::DB::Fasta->new('/path/to/fasta/files/');
  my @ids      = $db->ids;

  # Simple access
  my $seqstr   = $db->seq('CHROMOSOME_I', 4_000_000 => 4_100_000);
  my $revseq   = $db->seq('CHROMOSOME_I', 4_100_000 => 4_000_000);
  my $length   = $db->length('CHROMOSOME_I');
  my $header   = $db->header('CHROMOSOME_I');
  my $alphabet = $db->alphabet('CHROMOSOME_I');

  # Access to sequence objects. See Bio::PrimarySeqI.
  my $seq     = $db->get_Seq_by_id('CHROMOSOME_I');
  my $seqstr  = $seq->seq;
  my $subseq  = $seq->subseq(4_000_000 => 4_100_000);
  my $trunc   = $seq->trunc(4_000_000 => 4_100_000);
  my $length  = $seq->length;

  # Loop through sequence objects
  my $stream  = $db->get_PrimarySeq_stream;
  while (my $seq = $stream->next_seq) {
    # Bio::PrimarySeqI stuff
  }

  # Filehandle access
  my $fh = Bio::DB::Fasta->newFh('/path/to/fasta/files/');
  while (my $seq = <$fh>) {
    # Bio::PrimarySeqI stuff
  }

  # Tied hash access
  tie %sequences,'Bio::DB::Fasta','/path/to/fasta/files/';
  print $sequences{'CHROMOSOME_I:1,20000'};

=head1 DESCRIPTION

Bio::DB::Fasta provides indexed access to a single Fasta file, several files,
or a directory of files. It provides persistent random access to each sequence
entry (either as a Bio::PrimarySeqI-compliant object or a string), and to
subsequences within each entry, allowing you to retrieve portions of very large
sequences without bringing the entire sequence into memory. Bio::DB::Fasta is
based on Bio::DB::IndexedBase. See this module's documentation for details.

The Fasta files may contain any combination of nucleotide and protein sequences;
during indexing the module guesses the molecular type. Entries may have any line
length up to 65,536 characters, and different line lengths are allowed in the
same file.  However, within a sequence entry, all lines must be the same length
except for the last. An error will be thrown if this is not the case.

The module uses /^E<gt>(\S+)/ to extract the primary ID of each sequence
from the Fasta header. See -makeid in Bio::DB::IndexedBase to pass a callback
routine to reversibly modify this primary ID, e.g. if you wish to extract a
specific portion of the gi|gb|abc|xyz GenBank IDs.

=head1 DATABASE CREATION AND INDEXING

The object-oriented constructor is new(), the filehandle constructor is newFh()
and the tied hash constructor is tie(). They all allow to index a single Fasta
file, several files, or a directory of files. See Bio::DB::IndexedBase.

=head1 SEE ALSO

L<Bio::DB::IndexedBase>

L<Bio::DB::Qual>

L<Bio::PrimarySeqI>

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>.

Copyright (c) 2001 Cold Spring Harbor Laboratory.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=head1 APPENDIX

The rest of the documentation details each of the object
methods. Internal methods are usually preceded with a _

For BioPerl-style access, the following methods are provided:

=head2 get_Seq_by_id

 Title   : get_Seq_by_id, get_Seq_by_acc, get_Seq_by_primary_id
 Usage   : my $seq = $db->get_Seq_by_id($id);
 Function: Given an ID, fetch the corresponding sequence from the database.
 Returns : A Bio::PrimarySeq::Fasta object (Bio::PrimarySeqI compliant)
           Note that to save resource, Bio::PrimarySeq::Fasta sequence objects
           only load the sequence string into memory when requested using seq().
           See L<Bio::PrimarySeqI> for methods provided by the sequence objects
           returned from get_Seq_by_id() and get_PrimarySeq_stream().
 Args    : ID

=head2 get_Seq_stream

 Title   : get_Seq_stream
 Usage   : my $stream = $db->get_Seq_stream();
 Function: Get a stream of Bio::PrimarySeq::Fasta objects. The stream supports a
           single method, next_seq(). Each call to next_seq() returns a new
           Bio::PrimarySeq::Fasta sequence object, until no more sequences remain.
 Returns : A Bio::DB::Indexed::Stream object
 Args    : None

=head1

For simple access, the following methods are provided:

=cut


package Bio::DB::Fasta;

use strict;
use IO::File;
use File::Spec;
use File::Basename qw(basename dirname);

use base qw(Bio::DB::IndexedBase Bio::DB::SeqI);

my $termination_length;
our $obj_class = 'Bio::PrimarySeq::Fasta';
our $file_glob = '*.{fa,FA,fasta,FASTA,fast,FAST,dna,DNA,fna,FNA,faa,FAA,fsa,FSA}';


=head2 new

 Title   : new
 Usage   : my $db = Bio::DB::Fasta->new( $path, %options);
 Function: Initialize a new database object. When indexing a directory, files
           ending in .fa,fasta,fast,dna,fna,faa,fsa are indexed by default.
 Returns : A new Bio::DB::Fasta object.
 Args    : A single file, or path to dir, or arrayref of files
           Optional arguments: see Bio::DB::IndexedBase

=cut


sub _calculate_offsets {
    # Bio::DB::IndexedBase calls this to calculate offsets
    my ($self, $file, $offsets) = @_;
    my $fileno = $self->_path2fileno(basename($file));

    my $fh = IO::File->new($file) or $self->throw( "Could not open $file: $!");
    binmode $fh;
    warn "Indexing $file\n" if $self->{debug};
    my ($offset, $id, $linelen, $alphabet, $headerlen, $count, $seq_lines,
        $last_line, %offsets);
    my ($l3_len, $l2_len, $l_len, $blank_lines) = (0, 0, 0, 0);

    while (<$fh>) {
        # Account for crlf-terminated Windows files
        $termination_length ||= /\r\n$/ ? 2 : 1;
        if (index($_, '>') == 0) {
            if (/^>(\S+)/) {
                print STDERR "Indexed $count sequences...\n"
                    if $self->{debug} && (++$count%1000) == 0;

                $self->_check_linelength($linelen);
                my $pos = tell($fh);
                if (defined $id) {
                    my $strlen  = $pos - $offset - length($_);
                    $strlen    -= $termination_length * $seq_lines;
                    my $ppos = &{$self->{packmeth}}($offset, $strlen, $strlen,
                        $linelen, $headerlen, $alphabet, $fileno);
                    $alphabet = Bio::DB::IndexedBase::NA;
                    $offsets->{$id} = $ppos;
                }
                $id = ref($self->{makeid}) eq 'CODE' ? $self->{makeid}->($_) : $1;
                ($offset, $headerlen, $linelen, $seq_lines) = ($pos, length $_, 0, 0);
                ($l3_len, $l2_len, $l_len, $blank_lines) = (0, 0, 0, 0);
            } else {
                # Catch bad header lines, bug 3172
                $self->throw("FASTA header doesn't match '>(\\S+)': $_");
            }
        } elsif ($_ !~ /\S/) {
            # Skip blank line
            $blank_lines++;
            next;
        } else {
            # Need to check every line :(
            $l3_len = $l2_len;
            $l2_len = $l_len;
            $l_len  = length($_);
            if (Bio::DB::IndexedBase::DIE_ON_MISSMATCHED_LINES) {
                if ( ($l3_len > 0) && ($l2_len > 0) && ($l3_len != $l2_len) ) {
                    my $fap = substr($_, 0, 20)."..";
                    $self->throw("Each line of the fasta entry must be the same ".
                        "length except the last. Line above #$. '$fap' is $l2_len".
                        " != $l3_len chars.");
                }
                if ($blank_lines) {
                    # Blank lines not allowed in entry
                    $self->throw("Blank lines can only precede header lines, ".
                        "found preceding line #$.");
                }
            }
            $linelen  ||= length($_);
            $alphabet ||= $_ ? $self->_guess_alphabet($_) : '';
            $seq_lines++;
        }
        $last_line = $_;
    }

    # Process with entry
    $self->_check_linelength($linelen);
    my $pos = tell($fh);
    if (defined $id) {
        my $strlen   = $pos - $offset;
        if ($linelen == 0) { # yet another pesky empty chr_random.fa file
            $strlen = 0;
        } else {
            if ($last_line !~ /\s$/) {
                $seq_lines--;
            }
            $strlen -= $termination_length * $seq_lines;
        }
        my $ppos = &{$self->{packmeth}}($offset, $strlen, $linelen, $strlen,
            $headerlen, $alphabet, $fileno);
        $offsets->{$id} = $ppos;
    }

    return \%offsets;
}


=head2 seq

 Title   : seq, sequence, subseq
 Usage   : my $seqstr = $db->seq($id);
           my $seqstr = $db->seq($id, $start, $stop, $strand);
 Function: Get a subseq of a sequence from the database. In the case of DNA
           sequences, if $stop is less than $start, then the reverse complement
           of the sequence is returned. Note that this goes against Bio::Seq
           conventions. For your convenience, the sequence to extract can be
           specified with any of the following compound IDs:
              $db->seq("$id:$start,$stop")
              $db->seq("$id:$start..$stop")
              $db->seq("$id:$start-$stop")
 Returns : A string
 Args    : Compound ID of sequence to retrieve
             or
           ID, optional start (defaults to 1), optional end (defaults to length
           of sequence) and optional strand (defaults to 1).

=cut

sub subseq {
    my ($self, $id, $start, $stop, $strand) = @_;
    $self->throw('Need to provide a sequence ID') if not defined $id;
    ($id, $start, $stop, $strand) = $self->_parse_compound_id($id, $start, $stop, $strand);

    my $data;

    my $fh = $self->_fh($id) or return;
    my $filestart = $self->_caloffset($id, $start, $termination_length);
    my $filestop  = $self->_caloffset($id, $stop , $termination_length);

    seek($fh, $filestart,0);
    read($fh, $data, $filestop-$filestart+1);
    $data =~ s/\n//g;
    $data =~ s/\r//g;
    if ($strand == -1) {
        # Reverse-complement the sequence
        $data = reverse $data;
        $data =~ tr/gatcGATC/ctagCTAG/;
    }
    return $data;
}

*seq = *sequence = \&subseq;


=head2 length

 Title   : length
 Usage   : my $length = $qualdb->length($id);
 Function: Get the number of residies in the indicated sequence.
 Returns : Number
 Args    : ID of entry

=head2 header

 Title   : header
 Usage   : my $header = $db->header($id);
 Function: Get the header line (ID and description fields) of the specified
           sequence.
 Returns : String
 Args    : ID of sequence

=cut

sub header {
    my ($self, $id) = @_;
    $self->throw('Need to provide a sequence ID') if not defined $id;
    my ($offset, $headerlen) = (&{$self->{unpackmeth}}($self->{offsets}{$id}))[0,4];
    $offset -= $headerlen;
    my $data;
    my $fh = $self->_fh($id) or return;
    seek($fh, $offset, 0);
    read($fh, $data, $headerlen);
    chomp $data;
    substr($data, 0, 1) = '';
    return $data;
}


=head2 alphabet

 Title   : alphabet
 Usage   : my $alphabet = $db->alphabet($id);
 Function: Get the molecular type of the indicated sequence: dna, rna or protein
 Returns : String
 Args    : ID of sequence

=cut


#-------------------------------------------------------------
# Bio::PrimarySeqI compatibility
#
package Bio::PrimarySeq::Fasta;
use overload '""' => 'display_id';

use base qw(Bio::Root::Root Bio::PrimarySeqI);

sub new {
    my ($class, @args) = @_;
    my $self = $class->SUPER::new(@args);
    my ($db, $id, $start, $stop) = $self->_rearrange(
                                 [qw(DATABASE ID START STOP)],
                                 @args);
    $self->{db}    = $db;
    $self->{id}    = $id;
    $self->{start} = $start || 1;
    $self->{stop}  = $stop  || $db->length($id);
    return $self;
}

sub fetch_sequence {
    return shift->seq(@_);
}

sub seq {
    my $self = shift;
    return $self->{db}->seq($self->{id}, $self->{start}, $self->{stop});
}

sub subseq {
    my $self = shift;
    return $self->trunc(@_)->seq();
}

sub trunc {
    my ($self, $start, $stop) = @_;
    $self->throw("Stop cannot be smaller than start") if $stop < $start;
    return $self->{start} <= $self->{stop} ?
        $self->new( $self->{db},
                    $self->{id},
                    $self->{start}+$start-1,
                    $self->{start}+$stop-1,  ) :
        $self->new( $self->{db},
                    $self->{id},
                    $self->{start}-($start-1),
                    $self->{start}-($stop-1) );
}

sub is_circular {
    my $self = shift;
    return $self->{is_circular};
}

sub display_id {
    my $self = shift;
    return $self->{id};
}

sub accession_number {
    my $self = shift;
    return 'unknown';
}

sub primary_id {
    my $self = shift;
    return overload::StrVal($self);
}

sub can_call_new {
    return 0;
}

sub alphabet {
    my $self = shift;
    return $self->{db}->alphabet($self->{id});
}

sub revcom {
    my $self = shift;
    return $self->new(@{$self}{'db', 'id', 'stop', 'start'});
}

sub length {
    my $self = shift;
    #return $self->{db}->length($self->{id});
        # wrong because ignores sequence start and stop values
    return length($self->seq);

}

sub description  {
    my $self = shift;
    my $header = $self->{'db'}->header($self->{id});
    # remove the id from the header
    return (split(/\s+/, $header, 2))[1];
}
*desc = \&description;


1;
