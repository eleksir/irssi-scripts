#use strict;
#use warnings "all";
use Cache::Memcached;
use Digest::MD5 qw(md5_base64);

use Irssi qw (command_bind
    settings_get_bool settings_add_bool
    settings_get_str  settings_add_str);
use vars qw($VERSION %IRSSI);

sub hookfn;

$VERSION = '1.01';
%IRSSI = (
    authors     => 'Eleksir',
    contact     => 'eleksir@exs-elm.ru',
    name        => 'Image link saver',
    description => 'Saves image link to memcache',
    license     => 'BSD',
    changed     => 'Sat Apr 28 15:25 CET 2018',
);


Irssi::signal_add_last("message public", "hookfn");

my $mc = '127.0.0.1:11211';

sub hookfn {
	my ($a, $text, $b, $c) = @_;
	my @words = split(/\s+/, $text);

	foreach my $word (@words) {
		if ($word =~ m{:?https?://([a-zA-Z0-9.-]+\.[a-zA-Z]+)/(?:.*)}) {
			my $memd = new Cache::Memcached { 'servers' => [ $mc ] };
			$memd->set(sprintf("irssi_%s", md5_base64($word)), $word);
			$memd->disconnect_all;
		}
	}

	return;
}
