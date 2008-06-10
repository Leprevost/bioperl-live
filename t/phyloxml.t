# -*-Perl-*- Test Harness script for Bioperl

use strict;
use warnings;

BEGIN {
  use lib 't/lib';
  use BioperlTest;

  test_begin(-tests => 36,
             -requires_modules => [qw(XML::LibXML)],
            );
  if (1000*$] < 5008) {
     plan skip_all => "Reader interface only supported in Perl >= 5.8";
     exit;
  } elsif (XML::LibXML::LIBXML_VERSION() <= 20620) {
     plan skip_all => "Reader not supported for libxml2 <= 2.6.20";
     exit;
  } 
	use_ok('Bio::TreeIO');
	use_ok('Bio::TreeIO::phyloxml');
}

my $verbose = test_debug();

ok my $treeio = Bio::TreeIO->new(
           -verbose => $verbose,
			     -format => 'phyloxml',
			     -file   => test_input_file('phyloxml_examples.xml'));

my $tree;

# tree1: clade and attribute
# <phylogeny> <clade> <name>
$tree = $treeio->next_tree;
isa_ok($tree, 'Bio::Tree::TreeI');
my @nodes = $tree->get_nodes;
is(@nodes, 5);
my ($A) = $tree->find_node('A');
ok($A);
is($A->branch_length, '0.102');
is($A->ancestor->id, '');
is($A->ancestor->branch_length, '0.06');
my $leaves_string = $tree->simplify_to_leaves_string();
if ($verbose > 0) {
  diag($leaves_string);
}
is($leaves_string, '((A,B),C)');
undef $tree;

# tree2: branch_length
# <branch_length>
$tree = $treeio->next_tree;
isa_ok($tree, 'Bio::Tree::TreeI');
@nodes = $tree->get_nodes;
is(@nodes, 5);
$leaves_string = $tree->simplify_to_leaves_string();
if ($verbose > 0) {
  diag($leaves_string);
}
is($leaves_string, '((A,B),C)');
undef $tree;

# tree3: bootstrap
# <confidence>
$tree = $treeio->next_tree;
isa_ok($tree, 'Bio::Tree::TreeI');
$leaves_string = $tree->simplify_to_leaves_string();
if ($verbose > 0) {
  diag($leaves_string);
}
is($leaves_string, '((A,B),C)');
undef $tree;

# tree4: species and sequence
# <taxonomy> <scientific_name> <sequence> <annotation>
$tree = $treeio->next_tree;
isa_ok($tree, 'Bio::Tree::TreeI');
$leaves_string = $tree->simplify_to_leaves_string();
if ($verbose > 0) {
  diag($leaves_string);
}
is($leaves_string, '((A,B),C)');
undef $tree;

# tree5: homolog relationship and sequence relationship
# <events> <speciations> <duplications> <symbol> <accession> 
# <sequence_relation> 
$tree = $treeio->next_tree;
isa_ok($tree, 'Bio::Tree::TreeI');
$leaves_string = $tree->simplify_to_leaves_string();
if ($verbose > 0) {
  diag($leaves_string);
}
is($leaves_string, '');
undef $tree;

# tree6: detailed sequence data
# <mol_seq> <annotation> <code>
$tree = $treeio->next_tree;
isa_ok($tree, 'Bio::Tree::TreeI');
$leaves_string = $tree->simplify_to_leaves_string();
if ($verbose > 0) {
  diag($leaves_string);
}
is($leaves_string, '');
undef $tree;

# tree7: network
# <clade_relation> @id_source & @id_ref
$tree = $treeio->next_tree;
isa_ok($tree, 'Bio::Tree::TreeI');
$leaves_string = $tree->simplify_to_leaves_string();
if ($verbose > 0) {
  diag($leaves_string);
}
is($leaves_string, '((A,B),C)');
undef $tree;

# tree8: property elements
# <property>
$tree = $treeio->next_tree;
isa_ok($tree, 'Bio::Tree::TreeI');
$leaves_string = $tree->simplify_to_leaves_string();
if ($verbose > 0) {
  diag($leaves_string);
}
is($leaves_string, '((A,B),C)');
undef $tree;

# tree9: property outside tree topology using id refs
# <property> @id_source @id_ref
$tree = $treeio->next_tree;
isa_ok($tree, 'Bio::Tree::TreeI');
$leaves_string = $tree->simplify_to_leaves_string();
if ($verbose > 0) {
  diag($leaves_string);
}
is($leaves_string, '((A,B),C)');
undef $tree;

# tree10: detailed taxonomy and distribution
# <id> <rank> <uri> <common_name> <distribution>
$tree = $treeio->next_tree;
isa_ok($tree, 'Bio::Tree::TreeI');
$leaves_string = $tree->simplify_to_leaves_string();
if ($verbose > 0) {
  diag($leaves_string);
}
is($leaves_string, '');
undef $tree;

# tree11: phylogeographic information
# <distribution> <point> <lat> <long> <alt>
$tree = $treeio->next_tree;
isa_ok($tree, 'Bio::Tree::TreeI');
$leaves_string = $tree->simplify_to_leaves_string();
if ($verbose > 0) {
  diag($leaves_string);
}
is($leaves_string, '(((A,B),C),D)');
undef $tree;

# tree12: date information
# <date> <desc> <value>
$tree = $treeio->next_tree;
isa_ok($tree, 'Bio::Tree::TreeI');
$leaves_string = $tree->simplify_to_leaves_string();
if ($verbose > 0) {
  diag($leaves_string);
}
is($leaves_string, '((A,B),C)');
undef $tree;

# tree13: alignment outside <phylogeny>
# <align:alignment> <seq> 
$tree = $treeio->next_tree;
isa_ok($tree, 'Bio::Tree::TreeI');
$leaves_string = $tree->simplify_to_leaves_string();
if ($verbose > 0) {
  diag($leaves_string);
}
is($leaves_string, '((A,B),C)');
undef $tree;


TODO: {
  local $TODO = 'write_tree not implemented yet';
  my $FILE1 = test_output_file();
  $treeio = Bio::TreeIO->new(-verbose => $verbose,
          -format => 'phyloxml',
          -file   => ">$FILE1");
  $treeio->write_tree($tree);
  undef $treeio;
  ok( -s $FILE1 );
}

