#!/usr/bin/perl
#
use warnings "all";
use strict;
use Cache::Memcached;
use URI::URL;
use Data::Dumper;

my $HTINY = undef;
my $HTINYS = undef;

eval {
	require HTTP::Tiny;            # stock perl module, but some assholes from debian rip perl into modules,
	import HTTP::Tiny;             # so there is non-zero possibility that we have no this module
};

if ($@ eq '') {
	$HTINY = 1;

	eval {
		require Net::SSLeay;
		import Net::SSLeay;
	};

	if ($@ eq '') {
		eval {
			require IO::Socket::SSL;
			import IO::Socket::SSL;
		};

		if ($@ eq '') {
			$HTINYS = 1; # to operate ssl stuff, we need Net::SSLeay, but sometimes
			             # installed perl environment lacks it, so use Tiny with care
		}
	}
}

my $IMAGEMAGICK = undef; # use on demand

if ($^O ne 'cygwin') {   # cygwin 2.882 64-bit has broken Image::Magick
	eval {
		require Image::Magick;
		import Image::Magick;
	};

	if ($@ eq '') {
		$IMAGEMAGICK = 1;
	}
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

	if (defined($itemref->{'hosts'}->{'127.0.0.1:11211'}->{'items'})
	        and (length($itemref->{'hosts'}->{'127.0.0.1:11211'}->{'items'}) > 2)) {

		foreach my $stat (split("\n", $itemref->{'hosts'}->{'127.0.0.1:11211'}->{'items'})) {
			my $slab;
			my $itemsamount;

			if ($stat =~ /^STAT items\:(\d+)\:number (\d+)/) {
				$slab = $1;
				$itemsamount = $2;
			} else {
				undef $slab;
				undef $itemsamount;
				next;
			}

			my $cachedump = $memd->stats(["cachedump $slab $itemsamount"]);
			my @keys = map {
				(split(/ /))[1];
			} split(/\n/, $cachedump->{'hosts'}->{'127.0.0.1:11211'}->{"cachedump $slab $itemsamount"});

			foreach my $key (@keys) {
				if (($key =~ /^irssi_/) or ($key =~ /^xchtlink_/)) {
					my $url = $memd->get($key);
					cdlfunc($url);
					undef $url;
					$memd->delete($key);
				}
			}

			undef $slab;
			undef $itemsamount;
			undef $cachedump;
			@keys = -1;
			undef @keys;
		}
	}

	undef $itemref;
	$memd->disconnect_all;
	undef $memd;

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
		$savepath = sprintf("%s/%s.%s", $savepath, $fname, $extension);

		if ( (lc($url) =~ /\.(gif|jpe?g|png|webm|mp4)$/) and ($1 eq $extension) ) {
			$savepath = $ENV{'HOME'} . "/imgsave/" . $fname;
		}

		dlfunc($url, $savepath);
		undef $savepath;
		undef $fname;
	}

	undef $url;
	undef $extension;

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
			if ($file =~ /(png|jpe?g|gif)$/i) {
				my $im = Image::Magick->new();
				my $rename = 1;
				my (undef, undef, undef, $format) = $im->Ping($file);

				if (defined($format)) {
					$rename = 0 if (($format eq 'JPEG') and ($file =~ /jpe?g$/i));
					$rename = 0 if (($format eq 'GIF') and ($file =~ /gif$/i));
					$rename = 0 if (($format =~ /^PNG/) and ($file =~ /png$/i));
					rename $file, sprintf("%s.%s", $file, lc($format)) if ($rename == 1);
				}

				undef $im;
				undef $rename;
				undef $format;
			}
		}
	}

	undef $url;
	undef $file;
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
			undef $http;
		};
	} elsif (defined($HTINY)) {
		eval {
			my $http = HTTP::Tiny->new();
			$r = $http->request('HEAD', $url);
			undef $http;
		};
	} else {
		$r = `$wgetpath --no-check-certificate -q --method=HEAD -S --timeout=5 "$url" 2>&1`;
		if ($? == 0) {
			foreach (split(/\n/, $r)) {
				next unless($_ =~ /Content\-Type: (.+)/);
				my $h = ($1); chomp($h);
				$r = undef;
				$r->{'success'} = 1;
				$r->{'headers'}->{'content-type'} = $h;
				undef $h;
				last;
			}
		} else {
			$r = undef;
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

	undef $url;
	return $r;
}

sub urlencode($) {
	my $url = shift;
	my $urlobj = url $url;
	$url = $urlobj->as_string;
	undef $urlobj;
	return $url;
}

