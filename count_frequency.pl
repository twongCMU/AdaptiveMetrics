#!/usr/bin/perl -w
use DBI;
use strict;
use Getopt::Long;

my $DATABASE_USERNAME = "root";
my $DATABASE_PASSWORD = "";
my $DATABASE_NAME = "adaptivemetrics";

my $dbh = DBI->connect("dbi:mysql:" . $DATABASE_NAME, $DATABASE_USERNAME, $DATABASE_PASSWORD,  {zeroDateTimeBehavior => "convertToNull", RaiseError => 1, PrintError => 1, mysql_enable_utf8 => 1})
    or die "Connection Error: $DBI::errstr\n";

my @raw_datas = `cat CodingSheet.txt`;
my $where_clause = "";
my $display_string = "";
my $current_group = 1;
my %papers_included = ();
foreach my $raw_data (@raw_datas) {
  chomp $raw_data;
  (my $this_group, my $this_technique, my $phrase) = split(/,/,$raw_data);
  if ($this_group != $current_group) {

    print "result for group $current_group: " . (scalar keys %papers_included) . "\n";
    print "------------------\n";

    $current_group = $this_group;
    %papers_included = ();
  }

  if ($this_technique eq "exact") {
    &exact_phrase_per_doc_search($phrase);
  }
  elsif ($this_technique eq "any") {
    &any_order_per_page_search($phrase);
  }
}
print "result for group $current_group: " . (scalar keys %papers_included) . "\n";
print "------------------\n";

sub any_order_per_page_search($) {
  (my $phrase) = @_;

  my $where_clause = "";
  my $first = 0;
  foreach my $oneword (split(/ /, $phrase)) {
    $where_clause .= " text LIKE " . $dbh->quote("%".$oneword."%") . " AND ";
  }
  $where_clause =~ s/AND $//;

  my $sql = "SELECT paper_id FROM pages WHERE preferred=1 AND $where_clause GROUP BY paper_id";
  my $sth = $dbh->prepare($sql);
  $sth->execute
    or die "SQL Error: $DBI::errstr\n";
  while (my $row = $sth->fetchrow_hashref) {
    $papers_included{$row->{'paper_id'}} = 1;
  }

  $sth->finish();
}

sub exact_phrase_per_doc_search($) {
  (my $phrase) = @_;

  my $sql = "SELECT paper_id FROM papers_fulltext WHERE entiretext LIKE " . $dbh->quote("%".$phrase."%");
  my $sth = $dbh->prepare($sql);
  $sth->execute
    or die "SQL Error: $DBI::errstr\n";
  while (my $row = $sth->fetchrow_hashref) {
    $papers_included{$row->{'paper_id'}} = 1;
  }

  $sth->finish();
}
