
# TODO: non expensively detect that X is running

# TODO: if we have tornado of notifications it looks like when script hits upper
#       threads amount limit, some notifications "slip away", and irssi became cpu hog :(

use strict;
# i do not use warnings pragma, because of irssi (perl) i-threads always generate warnings,
# maybe there is other way to make async jobs in irssi?
#use warnings "all";
use threads;
use threads::shared;
use MIME::Base64;
use Irssi qw (
	command_bind
	settings_get_bool settings_add_bool
	settings_get_str  settings_add_str
);
use vars qw($VERSION %IRSSI);

sub notify;
sub hookfn;
sub timeraction;
sub encodestr;
sub notify_set;
sub loadlist($);
sub savelist(@);
sub uniq(@);

$VERSION = '1.01';
%IRSSI = (
	authors     => 'Eleksir',
	contact     => 'eleksir@exs-elm.ru',
	name        => 'notify.pl',
	description => 'Desktop notifications.',
	license     => 'MIT',
	changed     => 'Sun Apr 16 21:15:25 MSK 2017',
);

my $help = 'Usage:
/notify enable nick|chan|net     - enables apropriate whitelist
/notify disable nick|chan|net    - disables apropriate whitelist
/notify status                   - shows statuses of whitelists
/notify show                     - shows whitelists and their statuses
/notify add this chan|net        - adds currently open channel|network to apropriate whitelist
/notify add nick|chan|net <name> - adds <name> to apropriate whitelist, <name> can be \'.\' for currently open chan or net
/notify del nick|chan|net <name> - removes <name> from apropriate whitelist, <name> can be \'.\' for currently open chan or net';

Irssi::command_bind( 'notify' => 'notify_set' );

Irssi::signal_add_last("message public", "hookfn");
Irssi::signal_add_last("message private", "hookfn");

# looks like 'notify' here is placeholder, all settings landing to section settings{"perl/core/scripts" = { ->IN_HERE<-} }
Irssi::settings_add_str('notify', 'nicklist', '');
Irssi::settings_add_str('notify', 'chanlist', '');
Irssi::settings_add_str('notify', 'netlist',  '');
Irssi::settings_add_bool('notify', 'nicklist_enable', 0);
Irssi::settings_add_bool('notify', 'chanlist_enable', 0);
Irssi::settings_add_bool('notify', 'netlist_enable',  0);
# irssi save settings (via /save) to it's config only if at least one parameter is not default!

Irssi::signal_emit('setup changed'); # a good practice. irssi actually reads config only if this signal emited,
                                     # so, if someone uses this script' settings, it will use renewed settings

my $active = 0; share($active);
my $threads = 0; share($threads);
my $THREADS_MAX = 30;
my $hook;

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

sub notify_set {
	my ($argstring, $serverhref, $channelhref) = @_;
	my $msg = undef;

	if ($argstring eq 'status') {
		my $nicklist = Irssi::settings_get_bool('nicklist');
		my $chanlist = Irssi::settings_get_bool('chanlist');
		my $netlist =  Irssi::settings_get_bool('netlist');

		if (($nicklist == 0) and ($chanlist == 0) and ($netlist == 0)) {
			$msg = sprint("All whitelists are disabled, notifications will not appear.");
		} else {
			$msg = '';

			if ($nicklist == 0) { $msg .= "Nicks whitelist:    disabled\n"; }
			else                { $msg .= "Nicks whitelist:    enabled\n";  }

			if ($chanlist == 0) { $msg .= "Channel whitelist:  disabled\n"; }
			else                { $msg .= "Channel whitelist:  enabled\n";  }

			if ($netlist == 0)  { $msg .= "Networks whitelist: disabled"; }
			else                { $msg .= "Networks whitelist: enabled";  }
		}
	} elsif ($argstring eq 'show') {
		$msg = '';

		if (Irssi::settings_get_bool('nicklist_enable') == 0) {
			$msg .= "Nick whitelist:    disabled\n";
		} else {
			$msg .= "Nick whitelist:    enabled\n";
		}

		$msg .= "Whitelisted nicks = " . join( ', ', loadlist('nicklist')) ."\n";

		if (Irssi::settings_get_bool('chanlist_enable') == 0) {
			$msg .= "Channel whitelist:  disabled\n";
		} else {
			$msg .= "Channel whitelist:  enabled\n";
		}

		$msg .= "Whitelisted channels = " . join( ', ', loadlist('chanlist')) . "\n";

		if (Irssi::settings_get_bool('netlist_enable') == 0) {
			$msg .= "Networks whitelist: disabled\n";
		} else {
			$msg .= "Networks whitelist: enabled\n";
		}

		$msg .= "Whitelisted networks = " . join( ', ', loadlist('netlist'));
	} elsif ($argstring =~ /^enable /) {
		if((split(/ +/, $argstring))[1] eq 'nick') {
			Irssi::settings_set_bool('nicklist_enable', '1');
			$msg = "Nick whitelist now enabled";
		} elsif ((split(/ +/, $argstring))[1] eq 'chan') {
			Irssi::settings_set_bool('chanlist_enable', '1');
			$msg = "Channel whitelist now enabled";
		} elsif ((split(/ +/, $argstring))[1] eq 'net') {
			Irssi::settings_set_bool('netlist_enable', '1');
			$msg = "Net whitelist now enabled";
		}

		Irssi::signal_emit('setup changed');
	} elsif ($argstring =~ /^disable /) {
		if((split(/ +/, $argstring))[1] eq 'nick') {
			Irssi::settings_set_bool('nicklist_enable', '0');
			$msg = "Nick whitelist now disabled";
		} elsif ((split(/ +/, $argstring))[1] eq 'chan') {
			Irssi::settings_set_bool('chanlist_enable', '0');
			$msg = "Channel whitelist now disabled";
		} elsif ((split(/ +/, $argstring))[1] eq 'net') {
			Irssi::settings_set_bool('netlist_enable', '0');
			$msg = "Net whitelist now disabled";
		}

		Irssi::signal_emit('setup changed');
	} elsif ($argstring =~ /^add /) {
		my (undef, $entity, $who) = split(/ +/, $argstring, 3);

		if($entity eq 'nick') {
			my @nicks = uniq(loadlist('nicklist'), $who);
			savelist('nicklist', @nicks);
			Irssi::signal_emit('setup changed');
			$msg = sprintf("Nick whitelist now: %s", join(', ', loadlist('nicklist')));
		} elsif ($entity eq 'chan') {
			my @chans = uniq(loadlist('chanlist'), $who);
			savelist('chanlist', @chans);
			Irssi::signal_emit('setup changed');
			$msg = sprintf("Chan whitelist now: %s", join(', ', loadlist('chanlist')));
		} elsif($entity eq 'net') {
			my @nets = uniq(loadlist('netlist'), $who);
			savelist('netlist', @nets);
			Irssi::signal_emit('setup changed');
			$msg = sprintf("Net whitelist now: %s", join(', ', loadlist('netlist')));
		} elsif ($entity eq 'this') {
			if ($who eq 'net') {
				if (defined($serverhref)) {
					my @nets = uniq(loadlist('netlist'), $serverhref->{'chatnet'});
					savelist('netlist', @nets);
					Irssi::signal_emit('setup changed');
					$msg = sprintf("Net whitelist now: %s", join(', ', loadlist('netlist')));
				} else {
					$msg = 'Run this command on server or channel window.';
				}
			} elsif ($who eq 'chan') {
				if (defined($channelhref)) {
					my @chans = uniq(loadlist('chanlist'), $channelhref->{'name'});
					savelist('chanlist', @chans);
					Irssi::signal_emit('setup changed');
					$msg = sprintf("Chan whitelist now: %s", join(', ', loadlist('chanlist')));
				} else {
					$msg = 'You\'re not in a channel window.';
				}
			} elsif ($who eq 'nick') {
				# looks like if you're chatting with person $channelhref->{'topic'} is not defined
				if ((defined($channelhref)) and (! defined($channelhref->{'topic'}))) {
					my @nicks = uniq(loadlist('nicklist'), $channelhref->{'name'});
					savelist('nicklist', @nicks);
					Irssi::signal_emit('setup changed');
					$msg = sprintf("Nick whitelist now: %s", join(', ', loadlist('nicklist')));
				} else {
					$msg = 'You\'re not chatting with person.';
				}
			}
		}
	} elsif ($argstring =~ /^del /) {
		my (undef, $entity, $who) = split(/ +/, $argstring, 3);

		if($entity eq 'nick') {
			savelist( 'nicklist', map { $_ eq $who ? () : $_ } loadlist('nicklist'));
			Irssi::signal_emit('setup changed');
			$msg = sprintf("Nick whitelist now: %s", join(', ', loadlist('nicklist')));
		} elsif ($entity eq 'chan') {
			savelist( 'chanlist', map { $_ eq $who ? () : $_; } loadlist('chanlist'));
			Irssi::signal_emit('setup changed');
			$msg = sprintf("Chan whitelist now: %s", join(', ', loadlist('chanlist')));
		} elsif ($entity eq 'net') {
			savelist( 'netlist', map { $_ eq $who ? () : $_; } loadlist('netlist'));
			Irssi::signal_emit('setup changed');
			$msg = sprintf("Net whitelist now: %s", join(', ', loadlist('netlist')));
		} elsif ($entity eq 'this') {
			if ($who eq 'net') {
				if (defined($serverhref)) {
					savelist( 'netlist', map { $_ eq $serverhref->{'chatnet'} ? () : $_; } loadlist('netlist'));
					Irssi::signal_emit('setup changed');
					$msg = sprintf("Net whitelist now: %s", join(', ', loadlist('netlist')));
				} else {
					$msg = 'Run this command on server or channel window.';
				}
			} elsif ($who eq 'chan') {
				if (defined($channelhref)) {
					savelist( 'chanlist', map { $_ eq $channelhref->{'name'} ? () : $_; } loadlist('chanlist'));
					Irssi::signal_emit('setup changed');
					$msg = sprintf("Chan whitelist now: %s", join(', ', loadlist('chanlist')));
				} else {
					$msg = 'You\'re not in a channel window.';
				}
			} elsif ($who eq 'nick') {
				if ((defined($channelhref)) and (! defined($channelhref->{'topic'}))) {
					savelist( 'nicklist', map { $_ eq $channelhref->{'name'} ? () : $_; } loadlist('nicklist'));
					Irssi::signal_emit('setup changed');
					$msg = sprintf("Nick whitelist now: %s", join(', ', loadlist('nicklist')));
				} else {
					$msg = 'You\'re not chatting with person.';
				}
			}
		}
	} else {
		$msg = $help;
	}

	Irssi::active_win()->print($msg);
}

sub hookfn {
	my ($server, $message, $nick, $nick_address, $chan) = @_;
	my $nicklist_enable = Irssi::settings_get_bool('nicklist_enable');
	my $chanlist_enable = Irssi::settings_get_bool('chanlist_enable');
	my $netlist_enable =  Irssi::settings_get_bool('netlist_enable');
	my $flag = 1; # show notification
	$flag = 0 if (($nicklist_enable != 1) or ($chanlist_enable != 1) or ($netlist_enable != 1));

	if (($nicklist_enable != 0) and ($flag == 0)) {
		my @nicklist = loadlist('nicklist');

		foreach (@nicklist) {
			next unless(defined($_));
			next if($_ eq '');

			if ($_ eq $nick) {
				$flag = 1;
				last;
			}
		}

		@nicklist = -1; undef @nicklist;
	}

	if (($chanlist_enable != 0) and ($flag == 0)) {
		my @chanlist = loadlist('chanlist');

		foreach (@chanlist) {
			next unless(defined($_));
			next if($_ eq '');

			if ($_ eq $chan) {
				$flag = 1;
				last;
			}
		}

		@chanlist = -1; undef @chanlist;
	}

	if (($netlist_enable != 0) and ($flag == 0)) {
		my @netlist = loadlist('netlist');

		foreach (@netlist) {
			next unless(defined($_));
			next if($_ eq '');

			if ($_ eq $server){
				$flag = 1;
				last;
			}
		}

		@netlist = -1; undef @netlist;
	}

	if ($flag == 1) {
		$active = 1;
		$message = Irssi::strip_codes($message);
		$message = encodestr($message);
		$nick = Irssi::strip_codes($nick);
		my $topic = sprintf("%s at %s says:\n", $nick, $chan);

		# perl can create limited amount of threads, so if there are a lot of notifications
		# we have to use infinite loop with sleep
		my $caught = 0;

		do {
			eval { threads->create(\&notify, $topic, $message) or die; };

			if ($@) {
				$caught = 1;
				sleep 1;
			} else {
				$caught = 0;
			}
		} while ( $caught == 1 );

		if ($active == 1) {
			# implement async action
			$hook = Irssi::timeout_add(250, "timeraction", '');
		}
	}

	undef $nicklist_enable; undef $chanlist_enable; undef $netlist_enable;
	undef $flag;
}

sub timeraction {
	if (($active == 0) and (defined($hook))) {
		Irssi::timeout_remove($hook);
	}
}

sub encodestr {
	my $str = shift;
	$str = join('', map {
		if ($_ eq '<') { $_ = '&lt;'; }
		elsif ($_ eq '>') { $_ = '&gt;'; }
		elsif ($_ eq '&') { $_ = '&amp;'; }
		elsif ($_ eq '"') { $_ = '&quot;'}
		else { $_ = $_; }
	} split(//, $str));

	return $str;
}

sub loadlist($){
	my $setting = shift;
	my @values;
	my $val = Irssi::settings_get_str($setting) or do {
		Irssi::settings_set_str($setting, '');
		undef $setting;
		return @values; # empty array :)
	};

	@values = map { decode_base64($_); } split(/ /, $val);
	undef $setting; undef $val;
	return @values;
}

sub savelist(@) {
	my $setting = shift;
	my @list = map { encode_base64($_, ''); } @_;
	my $value = join(' ', @list);
	Irssi::settings_set_str($setting, $value);
}

sub uniq(@) {
	my %hash = map { $_ => 1 } @_;
	return keys %hash;
};

# vim: set noai ts=4 sw=4:
