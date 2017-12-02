#!/usr/bin/perl
#
use warnings "all";
use strict;
use Cache::Memcached;
use URI::URL;
my $HTINY = undef;
my $HTINYS = undef;
$HTINY = eval {
	require HTTP::Tiny;            # stock perl module, but some assholes from debian rip perl into modules,
	import HTTP::Tiny;             # so there is non-zero possibility that we have no this module
	$HTINYS = HTTP::Tiny->can_ssl; # to operate ssl stuff, we need Net::SSLeay, but sometimes
	return 1;                      # installed perl environment lacks it, so use Tiny with care
};

my $IMAGEMAGICK = undef; # use on demand
if ($^O ne 'cygwin') { # cygwin 2.882 64-bit has broken Image::Magick
	$IMAGEMAGICK = eval {
		require Image::Magick;
		import Image::Magick qw(ping);
		return 1;
	};
}

sub dlfunc(@);
sub cdlfunc($);    # thread, that checks and downloads stuff
sub is_picture($);
sub urlencode($);

my $wgetpath = '';

if (-f "/bin/wget") {
	$wgetpath = '/bin/wget';
} elsif (-f "/usr/bin/wget") {
	$wgetpath = '/usr/bin/wget';
} elsif (-f "/usr/local/bin/wget") {
	$wgetpath = '/usr/local/bin/wget';
}

while ( 1 ) {
	my $memd = new Cache::Memcached { 'servers' => [ "127.0.0.1:11211" ] };
	my $itemref = $memd->stats(['items']);

	if (length($itemref->{'hosts'}->{'127.0.0.1:11211'}->{'items'}) > 2) {
		my $slabinfo = (split("\n", $itemref->{'hosts'}->{'127.0.0.1:11211'}->{'items'}))[0];
		my $slab = (split(/\:/, $slabinfo))[1];
		my $itemsamount = (split(/ /, $slabinfo))[2];
		my $cachedump = $memd->stats(["cachedump $slab $itemsamount"]);
		my @keys = map { (split(/ /))[1] } split(/\n/, $cachedump->{'hosts'}->{'127.0.0.1:11211'}->{"cachedump $slab $itemsamount"});

		foreach my $key (@keys) {
			my $url = $memd->get($key);
			cdlfunc($url);
			$memd->delete($key);
		}
	}

	$memd->disconnect_all;
	sleep(30);
}


sub cdlfunc($) {
	my $url = shift;
	my $extension = is_picture($url);

	if (defined($extension)) {
		my $savepath = sprintf("%s/imgsave", $ENV{'HOME'});
		mkdir ($savepath) unless (-d $savepath);
		my $fname = $url;
		$fname =~ s/[^\w!., -#]/_/g;
		$savepath = $savepath . "/" . $fname . ".$extension";

		if ( (lc($url) =~ /\.(gif|jpeg|png|webm|mp4)$/) and ($1 eq $extension) ){
			$savepath = $ENV{'HOME'} . "/imgsave/" . $fname;
		}

		dlfunc($url, $savepath);
	}

	return;
}

sub dlfunc(@) {
	my $url = shift;
	my $file = shift;
	$url = urlencode($url);

	if (($url =~ /^https/) and defined($HTINY) and ($HTINYS)) {
		eval {
			my $http1 = HTTP::Tiny->new();
			$http1->mirror($url, $file);
			undef $http1;
		};
	} elsif (defined($HTINY)) {
		eval { 
			my $http2 = HTTP::Tiny->new();
			$http2->mirror($url, $file);
			undef $http2;
		};
	} else {
		system($wgetpath, '--no-check-certificate', '-q', '-T', '20', '-O', $file, '-o', '/dev/null', $url);
	}

	if (($^O ne 'cygwin') and defined($IMAGEMAGICK)) {
		eval {
			if ($file =~ /(png|jpe?g|gif)$/i){
				my $im = Image::Magick->new();
				my $rename = 1;
				my (undef, undef, undef, $format) = $im->Ping($file);

				if (defined($format)) {
					$rename = 0 if (($format eq 'JPEG') and ($file =~ /jpe?g$/i));
					$rename = 0 if (($format eq 'GIF') and ($file =~ /gif$/i));
					$rename = 0 if (($format =~ /^PNG/) and ($file =~ /png$/i));
					rename $file, sprintf("%s.%s", $file, lc($format)) if ($rename == 1);
				}
			}
		}
	}

	return;
}

sub is_picture($) {
	my $url = shift;
	$url = urlencode($url);
	my $r = undef;

	if (($url =~ /^https/) and defined($HTINY) and ($HTINYS)) {
		eval {
			my $http = HTTP::Tiny->new();
			$r = $http->request('HEAD', $url);
			undef $url;
			undef $http;
		};
	} elsif (defined($HTINY)) {
		eval {
			my $http = HTTP::Tiny->new();
			$r = $http->request('HEAD', $url);
			undef $url;
			undef $http;
		};
	} else {
		$r = `$wgetpath --no-check-certificate -q --method=HEAD -S --timeout=5 "$url" 2>&1`;
		if ($? == 0) {
			foreach (split(/\n/, $r)) {
				next unless($_ =~ /Content\-Type: (.+)/);
				my $h = ($1); chomp($h);
				$r->{'success'} = 1;
				$r->{'headers'}->{'content-type'} = $h;
				last;
			}
		} else {
			$r->{'success'} = 0;
		}
	}

	if ($r->{'success'} and defined($r->{'headers'}->{'content-type'})) {
		if    ($r->{'headers'}->{'content-type'} =~ /^image\/gif/)  { $r = 'gif'; }
		elsif ($r->{'headers'}->{'content-type'} =~ /^image\/jpe?g/){ $r = 'jpeg';}
		elsif ($r->{'headers'}->{'content-type'} =~ /^image\/png/)  { $r = 'png'; }
		elsif ($r->{'headers'}->{'content-type'} =~ /^video\/webm/) { $r = 'webm';}
		elsif ($r->{'headers'}->{'content-type'} =~ /^video\/mp4/)  { $r = 'mp4'; }
		else  { $r = undef; }
	} else {
		$r = undef;
	}

	return $r;
}

sub urlencode($) {
	my $url = shift;
	my $urlobj = url $url;
	$url = $urlobj->as_string;
	undef $urlobj;
	return $url;
}