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

# Export the version to the server
use vars qw($VERSION);
$VERSION = "0.4";

my %positions;

my $log = Slim::Utils::Log->addLogCategory({
    'category' => 'plugin.synchronizer',
    'defaultLevel' => 'ERROR',
    'description' => 'PLUGIN_SYNCHRONIZER_NAME'
});

sub getDisplayName() {
	return 'PLUGIN_SYNCHRONIZER_NAME';
}

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
	#$client->bumpRight();
	doSynchronize($client);
    },
);


sub initPlugin {
    my $class = shift;
    $class->SUPER::initPlugin(@_);
    $log->info(string('PLUGIN_SYNCHRONIZER_STARTING') . " -- $VERSION");
    if (!defined($prefs->get('groups')))
    {
	my %groups;
	$prefs->set('groups', \%groups);
    }
    Plugins::Synchronizer::Settings->new();
}

sub webPages {
    $log->debug("webPages called");

    my $index = 'plugins/Synchronizer/index.html';

    # Slim::Web::HTTP::protectURI($index);

    Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_SYNCHRONIZER_NAME' => $index } );
    Slim::Web::HTTP::addPageFunction($index, \&webHandleIndex);
}

####
### Other Functions
####

sub webHandleIndex {
    my ($client, $params) = @_;
    $log->debug("Synchronizer->webHandleIndex() called.");
    my @playerList = ();
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

    foreach my $client (Slim::Player::Client::clients())
    {
	my $masterId = $prefs->client($client)->get($group) || 0;;
	$log->debug("Synchronizing " . $client->name() . " SetID " . $group . " to MasterID " .  $masterId);
	if (defined $masterId) {
	    my $master = Slim::Player::Client::getClient($masterId);
	    if (defined $master) {
		$log->debug("Synchronizing " . $client->name() . " to " . $master->name());
		Slim::Player::Sync::sync($client, $master);
	    }
	}
    }
}

sub unsyncAll {
    $log->debug("Unsynchronizing everything");
    foreach my $client (Slim::Player::Client::clients())
    {
	$log->debug("Unsynchronizing " . $client->name());
	Slim::Player::Sync::unsync($client);
    }
}

sub syncToMe {
    my $client = shift;
    $log->debug("Syncing everyone to " . $client->name());
    # unsyncAll();
    foreach my $buddy (Slim::Player::Client::clients())
    {
	if ($client ne $buddy) {
	    $log->debug("Synchronizing " . $buddy->name() . " to " .  $client->name());
	    Slim::Player::Sync::sync($buddy, $client);
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

#sub shutdownPlugin {
    #$log->info(string('PLUGIN_SYNCHRONIZER_STOPPING') . " -- $VERSION");
#}
	
################################################
### End of Section 2.                        ###
################################################

sub getFunctions() {
    return \%functions;
}

1;
