#!/usr/bin/perl -w
use strict;
use DBI;
use Getopt::Long;

my $DATABASE_NAME = "adaptivemetrics";
my $HOST_NAME = "127.0.0.1";
GetOptions ("hostname:s" => \$HOST_NAME,
            "database:s" => \$DATABASE_NAME)
  or die ("Error in command line arguments\n");

my $dbh = DBI->connect("dbi:mysql:" . $DATABASE_NAME . ":$HOST_NAME", "root", "",  {RaiseError => 1, PrintError => 1, mysql_enable_utf8 => 1})
    or die "Connection Error: $DBI::errstr\n";

my $pid = $$;
my @files = `/usr/bin/find`;
foreach my $file (@files) {
    chomp $file;
    if (!($file =~ /\.pdf$/)) {
	next;
    }

    my $file_nopath = substr($file, rindex($file, "/") + 1);
  
    #  check if this pdf has already been taken
    my $paper_id = &seen_paper($file_nopath);
    if ($paper_id == -1) {
	next;
    }

    # split the pdf into per-page .pgm grayscale files of the form $file-page#.pgm
    # we could do this per-page as we needed but to save overhead we'll do it all at once
    # The drawback is that we use a lot of space for pdfs with lots of pages
    system("/usr/bin/pdftoppm",  "-gray", $file,  $file_nopath);

    `/bin/echo "pg, ocr size, dump size, choice" >> "/home/tw/results/${file_nopath}.log"`;

    my @result_files = `ls "${file_nopath}-"*`;
    foreach my $result_file (sort @result_files) {
	chomp $result_file;
	my $page_num = "";
	if ($result_file =~ /-(\d+)\.pgm/) {
	    $page_num = $1;
	}
	else {
	    die "Failed to get page_num fro $result_file";
	}
	print $page_num . "/" . (scalar @result_files) . " ";

	my $ocr_text_filename = $pid . "_temp_ocr";
	my $dump_text_filename = $pid . "_temp_dump";

	# get the OCR'd text 
	system("/usr/bin/tesseract", "-l", "eng", $result_file, $ocr_text_filename);
	$ocr_text_filename .= ".txt"; #tesseract munges the file name so we need this line

	# cuneiform crashes so we don't use it
	#system("/usr/bin/cuneiform", "-l", "eng", "-f", "text", "-o", $ocr_text_filename, $result_file);


	# get the regular text
	system("/usr/bin/pdftotext", "-f", $page_num, "-l", $page_num, $file, $dump_text_filename);

	my $ocr_text_size = -s $ocr_text_filename;
	my $dump_text_size = -s $dump_text_filename;

	my $prefer_ocr = 0;
	my $prefer_dump = 0;

	my $ocr_text = `/bin/cat $ocr_text_filename`;
	my $dump_text = `/bin/cat $dump_text_filename`;

	# OCR doesn't do a good job, so only accept an ocr'd page if it produces 10x the number of chars as the raw dump
	# This usually means that there were very few real text words on the page and it was mostly a scanned
        # image. If we go with too low a multiplier we include things like images of graphs that generally
	# produce gibberish when OCR'd
	if ($ocr_text_size > $dump_text_size * 10) {
	    $prefer_ocr = 1;
	}
	else {
	    $prefer_dump = 1;
	}

	$dbh->do("INSERT INTO pages VALUES($paper_id, $page_num, 'ocr', " . $dbh->quote($ocr_text) . ", $prefer_ocr, NOW())");
	$dbh->do("INSERT INTO pages VALUES($paper_id, $page_num, 'textdump', " . $dbh->quote($dump_text) . ", $prefer_dump, NOW())");


	system("/bin/rm", $result_file);
	system("/bin/rm", $ocr_text_filename);
	system("/bin/rm", $dump_text_filename);
    }
    print "\n";
#    my $file2 = $file_nopath;
#    $file2 =~ s/pdf$/txt/;
#    system("/usr/bin/pdftotext", $file, "/home/tw/results/$file2");
}


# return -1 if paper already processed, new paper_id if not
sub seen_paper($$) {
    my ($paper_name) = @_;

    my $rc = undef;

    $dbh->do("LOCK TABLES papers LOW_PRIORITY WRITE");

    my %paper_info = &get_paper_info($paper_name);
  
    if (!(defined $paper_info{'id'})) {
	print "Paper not yet processed: $paper_name";
	$dbh->do("INSERT INTO papers VALUES('null' ," . $dbh->quote($paper_name) . ", NOW())");
	%paper_info = &get_paper_info($paper_name);
	if (!(defined $paper_info{'id'})) {
	    die "Error paper not found after insert for $paper_name";
	}
	$rc = $paper_info{'id'};
    }
    else {
	print "Already processed paper " . $paper_info{'id'} . ":" . $paper_info{'process_date'} . ": $paper_name\n";
	$rc = -1;
    }

    $dbh->do("UNLOCK TABLES");

    if (! defined $rc) {
	die "failed to decide if paper was seen: $paper_name";
    }
    return $rc;
}

	
sub get_paper_info($) {
    (my $paper_name) = @_;

    my %res = ();

    my $sql;
    my $sth;

    $sql = "SELECT * FROM papers WHERE name=" . $dbh->quote($paper_name);
    $sth = $dbh->prepare($sql);
    my $paper_count = $sth->execute
	or die "SQL Error: $DBI::errstr\n";
    if ($paper_count eq "0E0") {
	;
    }
    elsif ($paper_count == 1) {
	my $row = $sth->fetchrow_hashref;
	$res{'id'} = $row->{'id'};
	$res{'process_date'} = $row->{'process_date'};
    }
    else {
	die "unexpected number of results $paper_count for paper $paper_name";
    }
    $sth->finish();

    return %res;
}
