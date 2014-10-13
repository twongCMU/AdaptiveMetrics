#!/usr/bin/perl -w
use DBI;
use strict;
use Getopt::Long;

my $DATABASE_NAME = "adaptivemetrics";
my $HOST_NAME = "127.0.0.1";
GetOptions ("hostname:s" => \$HOST_NAME,
            "database:s" => \$DATABASE_NAME)
  or die ("Error in command line arguments\n");

my $dbh = DBI->connect("dbi:mysql:" . $DATABASE_NAME . ":$HOST_NAME", "root", "",  {RaiseError => 1, PrintError => 1, mysql_enable_utf8 => 1})
    or die "Connection Error: $DBI::errstr\n";

$dbh->do("DROP TABLE IF EXISTS papers_fulltext");
$dbh->do("CREATE TABLE papers_fulltext (paper_id int(11), entiretext longtext CHARACTER SET utf8 NOT NULL, PRIMARY KEY(paper_id)) ENGINE=InnoDB ;");

my $sql;
my $sth;
my %paper_stats = ();

$sql = "SELECT id FROM papers";
$sth = $dbh->prepare($sql);
$sth->execute
    or die "SQL Error: $DBI::errstr\n";
while (my $row = $sth->fetchrow_hashref) {
    &onePaper($row->{'id'});
}
$sth->finish();
foreach my $pect (sort keys %paper_stats) {
    print $paper_stats{$pect} . " : $pect \n";
}


sub onePaper($) {
    (my $paper_id) = @_;

    my $sql;
    my $sth;

    $sql = "SELECT * FROM pages WHERE paper_id=$paper_id AND preferred=1 ORDER BY page_number";
    $sth = $dbh->prepare($sql);
    $sth->execute
	or die "SQL Error: $DBI::errstr\n";

    my $pages = 0;
    my $pages_ocr = 0;
    my $pages_text = 0;
    my $fulltext = "";
    my $expected_page_num = 1;
    while (my $row = $sth->fetchrow_hashref) {
	$fulltext .= $row->{'text'};

	if ($row->{'source'} eq "ocr") {
	    $pages_ocr++;
	}
	if ($row->{'source'} eq "textdump") {
	    $pages_text++;
	}
	if ($row->{'page_number'} != $expected_page_num) {
	    print "ERROR expected $expected_page_num got $row->{'page_number'}\n";
	}
	$expected_page_num++;
	$pages++;

    }
    $sth->finish();

    $dbh->do("INSERT INTO papers_fulltext VALUES($paper_id, " . $dbh->quote($fulltext) . ")");
    $paper_stats{$pages_ocr/$pages} = $paper_id;
    print "paper $paper_id: ocr $pages_ocr/$pages length " . (length $fulltext) . "\n";
}

