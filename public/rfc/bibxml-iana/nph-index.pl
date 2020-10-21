#!/usr/bin/perl 

# auto-generate IANA references in bibxml format.
# e.g. http://xml2rfc.ietf.org/public/rfc/bibxml-iana/reference.IANA.service-names-port-numbers.xml

# http://xml2rfc.ietf.org/public/rfc/bibxml-iana/reference.IANA.$iana.xml
# http://xml2rfc.ietf.org/public/rfc/bibxml-iana/reference.IANA.$iana.kramdown

use strict vars;
use CGI qw(taint);
use LWP::Simple;

$CGI::DISABLE_UPLOADS = 1;          # Disable uploads
$CGI::POST_MAX        = 512 * 1024; # limit posts to 512K max

my $cgi = CGI->new();

# for testing
# $cgi->param("anchor", "test");  
my $ignoreCache = undef;

my $replacementAnchor = mungeAnchor($cgi->param("anchor"));

my @refs = ();
my $nph = $0 =~ m(/nph-index.cgi);

# print STDERR "0=$0, nph=$nph\n";
if ($#ARGV >= 0) {
    # look at $ARGV for testing purposes to determine format (xml vs kramdown) and references
    @refs = @ARGV;
    # print "ARGV=" . join("|", @ARGV) . "\n";
} else {
    # if no $ARGV, look at $PATH_INFO to determine format (xml vs kramdown) and reference
    @refs = $ENV{PATH_INFO};
}

# for each reference:
for my $ref (@refs) {
    #    if cache has file already and < 24 hours old
    #        cat cached copy
    #    else
    #        grab dx.doi.org/$ref
    #        convert to appropriate format
    #        save in cache
    # print STDERR "ref=$ref\n";
    if ($ref =~ m(^/?reference.IANA[.]([^/]+)[.](xml|kramdown)$)) {
	my $refnumber = $1;
	my $type = $2;
	# print STDERR "refnumber=$refnumber type=$3\n";
	# my $CACHEDIR = "/var/tmp/iana-cache";
	my $CACHEDIR = "/var/cache/bibxml-iana";

	my $TMP = "$CACHEDIR/reference.IANA.${refnumber}.${type}";
	# print STDERR "-s $TMP=" . (-s $TMP) . ", -M $TMP=" . (-M _);
	my $printed = undef;
	if ((-s $TMP) && (-M _ < 1) && !$ignoreCache) {
	    print STDERR "Using cached file $TMP\n";
	    if (!open(TMP, "<", $TMP)) {
		print STDERR "Cannot read $TMP: $!\n";
	    } else {
		local $/ = undef;
		my $ret = <TMP>;
		close TMP;
		$ret = replaceAnchor($ret, $type, $replacementAnchor);
		print "HTTP/1.0 200 OK\n" if $nph;
		print "Content-Type: text/$type\n\n";
		print $ret;
		$printed = 1
	    }
	}

	if (!$printed) {
	    umask(0);
	    if ((!-d $CACHEDIR) && !mkdir($CACHEDIR)) {
		print STDERR "Cannot create $CACHEDIR: $!\n";
	    }

	    print STDERR "GET http://www.iana.org/assignments/$refnumber/";
	    my $a = get("http://www.iana.org/assignments/$refnumber/");

	    if (!defined($a)) {
	       printNotFound();
	    } else {
	       # print STDERR "a=====\n$a\n====\n";
	       # print STDERR "====\n";
	       $a =~ m(<title>([^<]*)</title>)m;
	       my $title = $1;

	       # print STDERR "title=$title\n";
	       if ($title =~ /page not found/i) {
		   printNotFound();
	       } else {
		   my $anchor = mungeAnchor($refnumber);

		   my $ret = "<reference anchor='$anchor' target='http://www.iana.org/assignments/$refnumber'>\n" .
		       "<front>\n" .
		       "<title>$title</title>\n" .
		       "<author><organization>IANA</organization></author>\n" .
		       "<date/>\n" .
		       "</front>\n" .
		       "</reference>\n";
		   
		   if (!open(TMP, ">", $TMP)) {
		       print STDERR "Cannot create $TMP: $!\n";
		   } else {
		       print TMP $ret;
		   }

		   $ret = replaceAnchor($refnumber, $type, $replacementAnchor);
		   print "HTTP/1.0 200 OK\n" if $nph;
		   print "Content-Type: text/$type\n\n";
		   print $ret;
	       }
	   }
	}
    } else {
	printNotFound();
    }
}

sub printNotFound {
    print "HTTP/1.0 404 NOT FOUND\n" if $nph;
    print "Content-type: text/plain\n\n";
    print "invalid IANA name or type\n";
}

sub mungeAnchor {
    my $anchor = shift;
    $anchor =~ tr/a-z/A-Z/;
    $anchor =~ s/[^A-Z0-9_-]//g;
    return $anchor;
}

sub replaceAnchor {
    my ($ref, $type, $replacementAnchor) = @_;
    if ($replacementAnchor ne "") {
	if ($type eq 'xml') {
	    $ref =~ s/anchor='[^']*'/anchor='$replacementAnchor'/;
	    $ref =~ s/anchor="[^"]*"/anchor='$replacementAnchor'/;
	} else {
	    $ref =~ s/^  [^:]*:/  $replacementAnchor:/;
	}
    }
    return $ref;    
}
