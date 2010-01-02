# The Synchronizer.pm by Eric Koldinger (kolding@yahoo.com) October, 2004
#
# This code is derived from code with the following copyright message:
#
# SlimServer Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
use strict;

###########################################
### Section 1. Change these as required ###
###########################################

package Plugins::Synchronizer::Plugin;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Strings qw (string);
use Slim::Utils::Misc;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Player::Player;
use Slim::Player::Client;
use Slim::Player::Sync;

use Plugins::Synchronizer::Settings;

my %positions;

my $log = Slim::Utils::Log->addLogCategory({
	'category' => 'plugin.synchronizer',
	'defaultLevel' => 'ERROR',
	'description' => 'PLUGIN_SYNCHRONIZER_NAME'
});

sub getDisplayName() {
	return 'PLUGIN_SYNCHRONIZER_NAME';
}

my @syncGroups;
my @unsyncPlayers;

##################################################
### Section 2. Your variables and code go here ###
##################################################

my $prefs = preferences('plugin.synchronizer');

sub setMode {
	my $class = shift;
	my $client = shift;
	$positions{$client} = 0 if (!defined $positions{$client});
	$log->debug("Setting mode for " . $client->name());
	$client->lines(\&lines);
}

sub enabled { 
	return 1;
}

my %functions = (
	'up' => sub { 
		my $client = shift;
		$positions{$client} = Slim::Buttons::Common::scroll ($client, -1, numSets() + 2, $positions{$client});
		$client->update();
	},
	'down' => sub  {
		my $client = shift;
		$positions{$client} = Slim::Buttons::Common::scroll ($client, +1, numSets() + 2, $positions{$client});
		$client->update();
	},
	'left' => sub {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub {
		my $client = shift;
		doSynchronize($client);
	},
);


sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$log->info(string('PLUGIN_SYNCHRONIZER_STARTING'));
	if (!defined($prefs->get('groups')))
	{
		my %groups;
		$prefs->set('groups', \%groups);
	}
	Plugins::Synchronizer::Settings->new();

	initCLI();
	initJive();
}

sub initCLI {
	$log->debug("Initializing CLI");
	Slim::Control::Request::addDispatch(['syncTop'],[1, 1, 0, \&syncTop]);
	Slim::Control::Request::addDispatch(['syncUnsync'],[1, 1, 0, \&syncUnsync]);
	Slim::Control::Request::addDispatch(['syncSyncToMe'],[1, 1, 0, \&syncSyncToMe]);
	Slim::Control::Request::addDispatch(['syncSyncToSet'],[1, 1, 1, \&syncSyncToSet]);
}

sub webPages {
	$log->debug("webPages called");

	my $index = 'plugins/Synchronizer/index.html';

	Slim::Web::HTTP::CSRF->protectURI($index);

	Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_SYNCHRONIZER_NAME' => $index } );
	Slim::Web::Pages->addPageFunction($index, \&webHandleIndex);
}

####
### Other Functions
####

sub webHandleIndex {
	my ($client, $params) = @_;
	$log->debug("Synchronizer->webHandleIndex() called.");
	my @playerList = ();
	#foreach my $key (keys %{$params})
	#{
	#	$log->debug("$key :: " . $params->{$key});
	#	}
	foreach my $client (Slim::Player::Client::clients()) {
	my $player = { "name" => $client->name(), "id" => $client->id() };
		push @playerList, $player;
	}

	if (defined $params->{'selectGroup'})
	{
		selectGroup($params->{'selectGroup'}, $params->{'master'});
	}

	$params->{'groups'} = $prefs->get('groups');
	$params->{'players'} = \@playerList;
	$params->{'nogroups'} = 1 if ($params->{'groups'} == 0);

    makeSyncList();
    $params->{'syncGroups'} = \@syncGroups;
	makeUnsyncList();
	$params->{'unsyncedPlayers'} = \@unsyncPlayers;

	return Slim::Web::HTTP::filltemplatefile('plugins/Synchronizer/index.html', $params);
}

sub selectGroup {
	my $group = shift;
	my $masterId = shift;
	$log->debug("Selecting synchronization group: " . $group . ", " . $masterId);
	if ($group eq "all")
	{
		my $master = Slim::Player::Client::getClient($masterId);
		$log->debug("Syncing to master: " . $masterId . " " . $master->name());
		syncToMe($master);
	} elsif ($group eq "none")
	{
		unsyncAll();
	}
	else
	{
		synchronizeGroup($group);
	}
}

####
###  Funtions for JIVE
####

sub initJive {
	$log->debug("Initializing JIVE");
	my @menu = ({
		text   => string('PLUGIN_SYNCHRONIZER_NAME'),
		id     => 'pluginSynchronizer',
		weight => 15,
		actions => {
			go => {
				player => 0,
				cmd      => [ 'syncTop' ],
			}
		},
	});
	Slim::Control::Jive::registerPluginMenu(\@menu, 'extras');
}

sub syncTop {
	my $request = shift;
	my $client = $request->client();

	my @menu = ();


    push @menu, {
        text => string('PLUGIN_SYNCHRONIZER_ALLTONAME', $client->name()),
        window => { menuStyle => 'album' },
        actions  => {
          do  => {
              player => 0,
              cmd    => [ 'syncSyncToMe' ],
              params => {
                menu => 'syncSyncToMe',
              },
          },
        },
    };

	my $numSets = numSets();
	for my $i (0 .. $numSets - 1) {
		push @menu, {
			text => syncSetName($i),
			window => { menuStyle => 'album' },
			actions  => {
			  do  => {
				  player => 0,
				  cmd    => [ 'syncSyncToSet' ],
				  params => {
					menu => 'syncSyncToSet',
					set  => $i,
				  },
			  },
			},
		};
	}

    push @menu, {
        text => string('PLUGIN_SYNCHRONIZER_NOSYNC'),
        window => { menuStyle => 'album' },
        actions  => {
          do  => {
              player => 0,
              cmd    => [ 'syncUnsync' ],
              params => {
                menu => 'syncUnsync',
              },
          },
        },
    };

	my $numitems = scalar(@menu);

	$request->addResult("count", $numitems);
	$request->addResult("offset", 0);
	my $cnt = 0;
	for my $eachPreset (@menu[0..$#menu])
	{
		$request->setResultLoopHash('item_loop', $cnt, $eachPreset);
		$cnt++;
	}

	$request->setStatusDone();
}

sub syncUnsync {
	my $request = shift;
	$log->debug("CLI/JIVE called Unsync");
	unsyncAll();
	$request->setStatusDone();
}

sub syncSyncToMe {
	my $request = shift;
	my $client = $request->client();
	$log->debug("CLI/JIVE called SyncToMe " . $client->name());
	
	syncToMe($client);
	$request->setStatusDone();
}

sub syncSyncToSet {
	my $request = shift;
	my $client = $request->client();
	my $set = $request->getParam('set');
	if ((!defined $set) || ($set < 0) || ($set >= numSets()))
	{
		$log->warn("Invalid set: $set");
		$request->setStatusBadParams();
		return;
	}
	#Data::Dump::dump($request);
	$log->debug("CLI/JIVE called SyncToSet " . $set . " " . syncSetName($set));
	synchronizeSet($set);
	$request->setStatusDone();
}

####
###  Functions that do the actual processing
###$

sub syncSetName {
	my $setNum = shift;
	my $numSets = numSets();
	if ($setNum < $numSets)
	{
		my $groups = $prefs->get('groups');
		my @keys = sort {$a <=> $b} keys % {$groups};
		return $groups->{$keys[$setNum]};
	}
	return string('PLUGIN_SYNCHRONIZER_NOSYNC') if ($setNum == $numSets);
	return string('PLUGIN_SYNCHRONIZER_ALLTOME') if ($setNum == $numSets + 1);
}

sub doSynchronize {
	my $client = shift;
	my $setNum = $positions{$client};
	$log->debug("doSynchronize: $setNum ::" . syncSetName($setNum));

	my $line1 = string('PLUGIN_SYNCHRONIZER_NAME');
	my $line2;
	my $numSets = numSets();
	if ($setNum < $numSets)
	{
		$line2 = string('PLUGIN_SYNCHRONIZER_SYNCING', syncSetName($setNum));
		$client->showBriefly({'line1' => $line1, 'line2' => $line2});
		synchronizeSet($setNum);
	} elsif ($setNum == $numSets) {
		$line2 = string('PLUGIN_SYNCHRONIZER_UNSYNCING');
		$client->showBriefly({'line1' => $line1, 'line2' => $line2});
		unsyncAll();
	} elsif ($setNum == ($numSets + 1)) {
		$line2 = string('PLUGIN_SYNCHRONIZER_SYNCINGTOME');
		$client->showBriefly({'line1' => $line1, 'line2' => $line2});
		syncToMe($client)
	}
}

sub synchronizeSet {
	my $set = shift;
	$log->debug("Synchronizing to set $set: " . syncSetName($set));
	my %groups = % {$prefs->get('groups')};
	my @keys = sort {$a <=> $b} keys %groups;
	my $setID = $keys[$set];
	synchronizeGroup($setID);
}

sub synchronizeGroup {
	my $group = shift;
	## Clear all the synchronization.
	unsyncAll();

	my $powerOn = $prefs->get('powerup');
	$log->debug("Synchronizing to group " . $group . " powerOn " . $powerOn);

	foreach my $client (Slim::Player::Client::clients())
	{
		$client->power(1) if ($powerOn);
		my $masterId = $prefs->client($client)->get($group) || 0;;
		$log->debug("Synchronizing " . $client->name() . " SetID " . $group . " to MasterID " .  $masterId);
		if (defined $masterId) {
			my $master = Slim::Player::Client::getClient($masterId);
			if (defined $master) {
				$log->debug("Synchronizing " . $client->name() . " to " . $master->name());
				#Slim::Player::Sync::sync($client, $master);
				$master->execute( [ 'sync', $client->id ] );
			}
		}
	}

}

sub unsyncAll {
	$log->debug("Unsynchronizing everything");
	foreach my $client (Slim::Player::Client::clients())
	{
		$log->debug("Unsynchronizing " . $client->name());
		#Slim::Player::Sync::unsync($client);
		$client->execute( [ 'sync', '-' ] );
	}
}

sub syncToMe {
	my $client = shift;
	my $powerOn = $prefs->get('powerup');
	$log->debug("Syncing everyone to " . $client->name());
	# unsyncAll();
	$client->power(1) if ($powerOn);
	foreach my $buddy (Slim::Player::Client::clients())
	{
		if ($client ne $buddy) {
			$log->debug("Synchronizing " . $buddy->name() . " to " .  $client->name() . " PowerON: " . $powerOn);
			$buddy->power(1) if ($powerOn);
			#Slim::Player::Sync::sync($buddy, $client);
			$client->execute( [ 'sync', $buddy->id ] );
		}
	}
}

sub lines {
	my $client = shift;
	my ($line1, $line2);
	$log->debug("Generating lines for " . $client->name() . ": $positions{$client}");
	$line1 = string('PLUGIN_SYNCHRONIZER_SELECT_SYNCSET');
	$line2 = syncSetName($positions{$client});
	return { 'line1' => $line1, 'line2' => $line2 };
}


sub numSets {
	my $sets = keys(% {$prefs->get('groups')});
	return ($sets);
}

sub makeSyncList {
    @syncGroups = ();
    foreach my $client (Slim::Player::Client::clients()) {
        if (Slim::Player::Sync::isMaster($client)) {
            my $groupName = Slim::Player::Sync::syncname($client);
            $log->debug($client->name() . "Group: $groupName");
            push @syncGroups, $groupName;
        }
    }
}

sub makeUnsyncList {
    @unsyncPlayers = ();
    foreach my $client (Slim::Player::Client::clients()) {
        if (!$client->isSynced()) {
            $log->debug("Unysnced: " . $client->name());
            push @unsyncPlayers, $client->name();
        }
    }
}

#sub shutdownPlugin {
	#$log->info(string('PLUGIN_SYNCHRONIZER_STOPPING') . ");
#}
	
################################################
### End of Section 2.						###
################################################

sub getFunctions() {
	return \%functions;
}

1;
