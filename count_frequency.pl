#!/usr/bin/perl -w
use DBI;
use strict;
use Getopt::Long;

my $DATABASE_USERNAME = "root";
my $DATABASE_PASSWORD = "";
my $DATABASE_NAME = "adaptivemetrics";

my $dbh = DBI->connect("dbi:mysql:" . $DATABASE_NAME, $DATABASE_USERNAME, $DATABASE_PASSWORD,  {zeroDateTimeBehavior => "convertToNull", RaiseError => 1, PrintError => 1, mysql_enable_utf8 => 1})
    or die "Connection Error: $DBI::errstr\n";

my @raw_datas = `cat CodingSheet2.txt`;
my $where_clause = "";
my $display_string = "";
my $current_group = 1;
my %papers_included = ();
my $raw_data_global = "";
my %grid_data = ();
my $phrase_global;
foreach my $raw_data (@raw_datas) {
  chomp $raw_data;

  (my $this_group, my $this_technique, my $phrase) = split(/,/,$raw_data);
  if ($this_group != $current_group) {
    #&print_result($raw_data_global, \%papers_included);
    $grid_data{$phrase_global} = &cloneHash();
    $current_group = $this_group;
    %papers_included = ();
  }

  $raw_data_global = $raw_data;
  $phrase_global = $phrase;

  if ($this_technique =~ /exact(\d+)/) {
    my $count_at_least = $1;
    &exact_phrase_per_page_search($phrase, $count_at_least);
  }
  elsif ($this_technique eq "exact") {
    &exact_phrase_per_doc_search($phrase, 1);
  }
  elsif ($this_technique eq "any") {
    &any_order_per_page_search($phrase);
  }
}
#&print_result($raw_data_global, \%papers_included);
$grid_data{$phrase_global} = &cloneHash();

print "X;";
my $one_grid_column;
foreach my $grid_column (sort keys %grid_data) {
  print $grid_column . ";";
  $one_grid_column = $grid_column;
}
print "\n";

my %foo = &getListOfPapers();
# list of papers
foreach my $grid_row (sort keys %foo) {
  print $grid_row . "; ";
  foreach my $grid_column (sort keys %grid_data) {# list of states
#    print STDERR $grid_data{$grid_column}{$grid_row}{"times"} . ", $grid_column, $grid_row\n";
    if (!(defined $grid_data{$grid_column}{$grid_row}{"times"})) {
      print "0;";
    }
    else {
      print $grid_data{$grid_column}{$grid_row}{"times"} . ";";
    }
  }
  print "\n";
}
	
#get metrics doc title, #words in doc, # pages in doc
# list of papers
print "==== START PAGE METRICS ===\n";
foreach my $grid_row (sort keys %foo) {	    
  &paper_stats($foo{$grid_row}, $grid_row);
}

sub paper_stats($$) {
  (my $paper_id, my $paper_name) = @_;

  my $sql = "SELECT COUNT(*) as page_count FROM pages WHERE paper_id=$paper_id AND preferred=1";
  my $sth = $dbh->prepare($sql);
  $sth->execute
    or die "SQL Error: $DBI::errstr\n";
  my $row = $sth->fetchrow_hashref;
  my $pages = $row->{"page_count"};
  $sth->finish();

  $sql = "SELECT entiretext FROM papers_fulltext WHERE paper_id=$paper_id";
  $sth = $dbh->prepare($sql);
  $sth->execute
    or die "SQL Error: $DBI::errstr\n";
   $row = $sth->fetchrow_hashref;
  my @words = split(/\s+/, $row->{"entiretext"});
  print "$paper_name ; $pages ; " . (scalar @words) . "\n";
  $sth->finish();
}

sub print_result($$) {
  (my $raw_data_global, my $papers_included_ref) = @_;
  my %papers_included = %{$papers_included_ref};

  print "result for group $current_group ($raw_data_global): " . (scalar (keys %papers_included)) . " docs: \n";
  foreach my $paper_name (sort keys %papers_included) {
    print $papers_included{$paper_name}{"times"} . " times : " . $paper_name;
    if (defined $papers_included{$paper_name}{"pages"}) {
      print " (pages: ";
      foreach my $page_num (@{$papers_included{$paper_name}{"pages"}}) {
	print $page_num . " ";
      }
      print ")";
    }
    print "\n";
  }
  print "------------------\n";
}

sub any_order_per_page_search($) {
  (my $phrase) = @_;

  my $where_clause = "";
  my $first = 0;
  foreach my $oneword (split(/ /, $phrase)) {
    $where_clause .= " text LIKE " . $dbh->quote("%".$oneword."%") . " AND ";
  }
  $where_clause =~ s/AND $//;

  my $sql = "SELECT paper_id, name FROM pages, papers WHERE papers.id = pages.paper_id AND preferred=1 AND $where_clause GROUP BY paper_id";
  my $sth = $dbh->prepare($sql);
  $sth->execute
    or die "SQL Error: $DBI::errstr\n";
  while (my $row = $sth->fetchrow_hashref) {
    if (defined $papers_included{$row->{'name'}}) {
      $papers_included{$row->{'name'}}{"times"}++;
	}
    else {
      $papers_included{$row->{'name'}}{"times"} = 1;
    }
  }

  $sth->finish();
}

#
# @in count The number of times this phrase must appear in the full document before it is included 
sub exact_phrase_per_doc_search($$) {
  (my $phrase, my $count_at_least) = @_;

  my $sql = "SELECT paper_id, name, entiretext FROM papers_fulltext, papers WHERE papers.id = papers_fulltext.paper_id AND entiretext LIKE " . $dbh->quote("%".$phrase."%");
  my $sth = $dbh->prepare($sql);
  $sth->execute
    or die "SQL Error: $DBI::errstr\n";
  while (my $row = $sth->fetchrow_hashref) {
    my $times_seen = () = $row->{'entiretext'} =~ /$phrase/g;
    # yes, if $count_at_least is 1 we're duplicating work but it makes the code simpler
    #if ($times_seen >= $count_at_least) {
      $papers_included{$row->{'name'}}{"times"} = $times_seen;
    #}
  }

  $sth->finish();
}

sub getListOfPapers() {
  my %foo = ();
  
  my $sql = "SELECT id, name FROM papers";
  my $sth = $dbh->prepare($sql);
  $sth->execute
    or die "SQL Error: $DBI::errstr\n";
  while (my $row = $sth->fetchrow_hashref) {
    $foo{$row->{"name"}} = $row->{"id"};
  }
  $sth->finish();
  return %foo;
}

#
# @in count The number of times this phrase must appear in the full document before it is included 
sub exact_phrase_per_page_search($) {
  (my $phrase, my $count_at_least) = @_;

  my $sql = "SELECT id, name FROM papers";
  my $sth = $dbh->prepare($sql);
  $sth->execute
    or die "SQL Error: $DBI::errstr\n";
  while (my $row = $sth->fetchrow_hashref) {
    my $sql2 = "SELECT page_number, text FROM pages WHERE paper_id = " . $row->{'id'} . " AND preferred=1 AND text LIKE ". $dbh->quote("%".$phrase."%");
    my $sth2 = $dbh->prepare($sql2);
    $sth2->execute
      or die "SQL Error: $DBI::errstr\n";
    my $times_seen = 0;
    my @page_list = ();
    while (my $row2 = $sth2->fetchrow_hashref) {
      my $times_this_page = () = $row2->{'text'} =~ /$phrase/g;
      $times_seen += $times_this_page;
      if ($times_this_page > 0) {
	push @page_list, $row2->{'page_number'};
      }
    }
    $sth2->finish();
    # if ($times_seen >= $count_at_least) {
    #print STDERR "saving times_seen $times_seen for $phrase, $row->{'name'}\n";
    $papers_included{$row->{'name'}}{"times"} = $times_seen;
    $papers_included{$row->{'name'}}{"pages"} = \@page_list;
    # }
  }
  $sth->finish();
}

sub cloneHash() {
  my %new_hash = ();
  foreach my $key (keys %papers_included) {
    $new_hash{$key}{"times"} = $papers_included{$key}{"times"};
    $new_hash{$key}{"pages"} = $papers_included{$key}{"pages"};
  }
  return \%new_hash;
}
