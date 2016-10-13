#use strict;
#use warnings "all";
use threads;
use threads::shared;
use URI::URL;
use Image::Magick;
use Irssi qw (command_bind
    settings_get_bool settings_add_bool
    settings_get_str  settings_add_str);
use vars qw($VERSION %IRSSI);

sub notify_cmd;
sub notify;
sub hookfn;
sub timeraction;

$VERSION = '1.00';
%IRSSI = (
    authors     => 'Eleksir',
    contact     => 'eleksir@exs-elm.ru',
    name        => 'Test command script',
    description => 'Sample script to test irssi api.',
    license     => 'Public Domain',
    changed     => 'Sun Oct 02 12:21 CET 2016',
);

Irssi::command_bind( 'test' => 'notify_cmd' );
Irssi::signal_add_last("message public", "hookfn");
Irssi::signal_add_last("message private", "hookfn");

my $active = 0;
share($active);

my $hook;

sub notify_cmd {
	my ($argstring, $serverhref, $channelhref) = @_;
	sleep 300;
	my %SERVER = %{$serverhref};
	my %CHANNEL = %{$channelhref};
	foreach (keys(%SERVER)){
		Irssi::active_win()->print("SERVER $_ = $SERVER{$_}");
	}
	foreach (keys(%CHANNEL)){
		Irssi::active_win()->print("CHANNEL $_ = $CHANNEL{$_}");
	}
	Irssi::active_win()->print("$argstring");
	Irssi::active_win()->print("With limited HP you either die fast or live long enough to become suka blya");
}

sub notify {
	my ($topic, $message) = @_;
	threads->detach();
	$topic =~ s/\\/\\\\/g;
	$topic =~ s/\'/\\'/g;
	$message =~ s/\\/\\\\/g;
	$message =~ s/\'/\\'/g;
	system("notify-send", "-u", "normal", "-t", "12000", "-a", "hexchat", $topic, "-i", "hexchat", $message);
	$active = 0;
}

sub hookfn {
	my ($server, $message, $nick, $nick_address, $chan) = @_;

	$active = 1;
	$message = Irssi::strip_codes($message);
	$nick = Irssi::strip_codes($nick);
	my $topic = sprintf("%s at %s says:\n", $nick, $chan);

#Irssi::active_win()->print(sprintf("%s at %s says: %s", $nick, $chan, $message));

	my $t = undef;

	do {
		$t = threads->create(\&notify, $topic, $message);
		sleep 1 unless(defined($t));
	} unless (defined($t));

	undef $t;

	if ($active == 1) {
		$hook = Irssi::timeout_add(250, "timeraction", '');
	}
}

sub timeraction {
	if (($active == 0) and (defined($hook))) {
		Irssi::timeout_remove($hook);
	}

	return;
}

