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
$VERSION = "1.0";

my %positions;

my $log = Slim::Utils::Log->addLogCategory({
    'category' => 'plugin.synchronizer',
    'defaultLevel' => 'DEBUG',
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
    my @clients = otherClients($client);
    $log->debug("Setting mode for " . $client->name());
    $client->lines(\&lines);
}

sub enabled { 
    return 1;
}

my %functions = (
	'up' => sub { 
		my $client = shift;
                my $newPos = Slim::Buttons::Common::scroll
				($client, -1, $prefs->get('syncSets'),
				$positions{$client});
                $positions{$client} = $newPos;
		$client->update();
	},
        'down' => sub  {
                my $client = shift;
                my $newPos = Slim::Buttons::Common::scroll
				($client, +1, $prefs->get('syncSets'),
				$positions{$client});
                $positions{$client} = $newPos;
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

sub syncSet {
    my $setNum = shift;
    my $numSets = $prefs->get("syncSets");
    if ($setNum < $numSets)
    {
	return $prefs->get("name_$setNum");
    }
    return string('PLUGIN_SYNCHRONIZER_NOSYNC') if ($setNum == $numSets);
    return string('PLUGIN_SYNCHRONIZER_ALLTOME') if ($setNum == $numSets + 1);
}

sub doSynchronize {
    my $client = shift;
    my $setNum = $positions{$client};
    $log->debug("doSynchronize: $setNum ::" . syncSet($setNum));

    my $numSets = $prefs->get("syncSets");
    return syncronizeSet($setNum) if ($setNum < $numSets);
    return unsyncAll() if ($setNum == $numSets);
    return syncToMe($client) if ($setNum == $numSets + 1);
}

sub synchronizeSet {
    my $set = shift;
    $log->debug("Synchronizing to set $set: " . syncSet($set));
    foreach my $client (Slim::Player::Client::clients())
    {
	my $masterId = $prefs->client($client)->get("master_$set");
	next unless defined $masterId;
	my $master = Slim::Player::Client::getClient($masterId);
	$log->debug("Synchronizing " . $client->name() . " to " . $master->name());
	Slim::Player::Sync($master, $client) if defined $master;
    }
}

sub unsyncAll {
    $log->debug("Unsynchronizing everything");
    foreach my $client (Slim::Player::Client::clients())
    {
	Slim::Player::Sync::unsync($client);
    }
}

sub syncToMe {
    my $client = shift;
    $log->debug("Syncing everyone to " . $client->name());
    foreach my $buddy (Slim::Player::Client::clients())
    {
	Slim::Player::Sync::sync($client, $buddy) if ($client != $buddy);
    }
}

sub lines {
	my $client = shift;
	my ($line1, $line2);
	$log->debug("Generating lines for " . $client->name() . ": $positions{$client}");
	$line1 = string('PLUGIN_SYNCHRONIZER_SELECT_SYNCSET');
	$line2 = Slim::Player::Client::name(syncSet($positions{$client}));
	return { 'line1' => $line1, 'line2' => $line2 };
}

sub initPlugin {
    my $class = shift;
    $class->SUPER::initPlugin(@_);
    $log->info(string('PLUGIN_SYNCHRONIZER_STARTING') . " -- $VERSION");
    Plugins::Synchronizer::Settings->new();
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
