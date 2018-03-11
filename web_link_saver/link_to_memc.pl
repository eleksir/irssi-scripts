#use strict;
#use warnings "all";
use Cache::Memcached;
use Digest::MD5 qw(md5_base64);

use Irssi qw (command_bind
    settings_get_bool settings_add_bool
    settings_get_str  settings_add_str);
use vars qw($VERSION %IRSSI);

sub hookfn;

$VERSION = '1.00a';
%IRSSI = (
    authors     => 'Eleksir',
    contact     => 'eleksir@exs-elm.ru',
    name        => 'Image link saver',
    description => 'Saves image link to memcache',
    license     => 'BSD',
    changed     => 'Sun Mar 11 15:39 CET 2018',
);


Irssi::signal_add_last("message public", "hookfn");

sub hookfn {
	my ($a, $text, $b, $c) = @_;
	my @words = split(/\s+/, $text);

	foreach (@words) {
		if ($_ =~ m{:?https?://([a-zA-Z0-9.-]+\.[a-zA-Z]+)/(?:.*)}) {
			my $memd = new Cache::Memcached { 'servers' => [ "127.0.0.1:11211" ] };
			$memd->set('irssi_' . md5_base64($str), $str);
			$memd->disconnect_all;
			last;
		}
	}

	return;
}

