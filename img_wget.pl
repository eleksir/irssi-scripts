#use strict;
#use warnings "all";
use threads;
use threads::shared;
use URI::URL;

my $IMAGEMAGICK = undef; # use on demand
if ($^O ne 'cygwin') { # cygwin 2.882 64-bit hag broken Image::Magick
	$IMAGEMAGICK = eval {
		require Image::Magick;
		import Image::Magick qw(ping);
		return 1;
	}
}

use Irssi qw (command_bind
    settings_get_bool settings_add_bool
    settings_get_str  settings_add_str);
use vars qw($VERSION %IRSSI);

sub info_cmd;
sub notify_cmd;
sub event_msg;

sub dlfunc(@);
sub cdlfunc($);    # thread, that checks and downloads stuff
sub is_picture($);
sub urlencode($);


$VERSION = '1.00';
%IRSSI = (
    authors     => 'Eleksir',
    contact     => 'eleksir@exs-elm.ru',
    name        => 'Image downloader',
    description => 'Sample script to test irssi api.',
    license     => 'Public Domain',
    changed     => 'Sun Oct 02 12:21 CET 2016',
);

my $wgetpath;

if (-f "/bin/wget") {
	$wgetpath = '/bin/wget';
} elsif (-f "/usr/bin/wget") {
	$wgetpath = '/usr/bin/wget';
} elsif (-f "/usr/local/bin/wget") {
	$wgetpath = '/usr/local/bin/wget';
}

Irssi::signal_add_last("message public", "hookfn");

my $active = 0;
share($active);
my $hook;

sub hookfn {
	my ($a, $text, $b, $c) = @_;
	my @words = split(/\s+/, $text);

	foreach (@words) {
		if ($_ =~ m{:?https?://([a-zA-Z0-9.-]+\.[a-zA-Z]+)/(?:.*)}) {
			$active = 1;
			my $t = undef;

			do {
				$t = threads->create('cdlfunc', $_);
				sleep 1 unless(defined($t));
			} unless (defined($t));

			$t->detach();
			undef $t;

			if ($active == 1) {
				$hook = Irssi::timeout_add(500, "timeraction", '');
			}
# catch only first link
			last;
		}
	}

	return;
}


sub cdlfunc($) {
	my $url = shift;
	my $extension = is_picture($url);

	if (defined($extension)) {
		my $savepath = sprintf("%s/imgsave", $ENV{'HOME'});
		mkdir ($savepath) unless (-d $savepath);
		$savepath = $savepath . "/" . s/[^\w!., -#]/_/gr . ".$extension";

		if ( (lc($url) =~ /\.(gif|jpeg|png|webm|mp4)$/) and ($1 eq $extension) ){
				$savepath = $ENV{'HOME'} . "/imgsave/" . s/[^\w!., -#]/_/gr;
		}

		dlfunc($url, $savepath);
	}

	$active = 0;
	return;
}

sub dlfunc(@) {
	my $url = shift;
	my $file = shift;

	$url = urlencode($url);
	system($wgetpath, '--no-check-certificate', '-q', '-T', '20', '-O', $file, '-o', '/dev/null', $url);

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

	$r = `$wgetpath --no-check-certificate -q --method=HEAD -S --timeout=5 "$url" 2>&1`;

	foreach (split(/\n/, $r)) {
		next unless($_ =~ /Content\-Type: (.+)/);
		$r = ($1); chomp($r);
		last;
	}

	if (defined($r)) {
		if ($r =~ /^image\/gif/)  {return 'gif';};
		if ($r =~ /^image\/jpe?g/){return 'jpeg';};
		if ($r =~ /^image\/png/)  {return 'png';};
		if ($r =~ /^video\/webm/) {return 'webm';};
		if ($r =~ /^video\/mp4/)  {return 'mp4';};
	}

	return undef;
}

sub urlencode($) {
	my $url = shift;
	my $urlobj = url $url;
	$url = $urlobj->as_string;
	undef $urlobj;
	return $url;
}

sub timeraction {
	if (($active == 0) and (defined($hook))) {
		Irssi::timeout_remove($hook);
	}

	return;
}
