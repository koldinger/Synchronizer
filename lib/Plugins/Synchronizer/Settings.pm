package Plugins::Synchronizer::Settings;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Player::Client;
use Plugins::Synchronizer::Plugin;

my $prefs = preferences('plugin.synchronizer');
my $log   = logger('plugin.synchronizer');
my @playerList;

sub name {
    return Slim::Web::HTTP::protectName('PLUGIN_SYNCHRONIZER_NAME');
}

sub page {
    return Slim::Web::HTTP::protectURI('plugins/Synchronizer/settings/basic.html');
}

sub handler {
    my ($class, $client, $params) = @_;
    $log->debug("Synchronizer::Settings->handler() called.");
    if ($params->{'saveSettings'})
    {
	$log->debug("Synchronizer::Settings->handler() save settings");
	if ((defined $params->{'newGroupName'}) && ($params->{'newGroupName'} ne ''))
	{
	    addGroup($params);
	}
	my %groups = % { $prefs->get('groups') } if (defined $prefs->get('groups'));
	foreach my $group (keys %groups) 
	{
	    $log->debug("Checking group " . $groups{$group} . "::" . $group);
	    my $dKey = "delete.$group";
	    if ($params->{"delete.$group"})
	    {
		deleteGroup($group);
	    } else {
		foreach my $client (Slim::Player::Client::clients()) {
		    my $tag = "sync.$group." . $client->id();
		    $prefs->client($client)->set($group, $params->{$tag});
		}
	    }
	}
    }
    $params->{'newGroupName'} = undef;
    $params->{'groups'} = $prefs->get('groups');
    makePlayerList();
    $params->{'players'} = \@playerList;
    
    return $class->SUPER::handler( $client, $params );
}

sub addGroup {
    my $params = shift;

    my %groups;

    ## Compute the ID of the new group
    my $lastID = ($prefs->get('lastID') || 0) + 1;
    $prefs->set('lastID', $lastID);

    %groups = % { $prefs->get('groups') };

    $groups{$lastID} = $params->{'newGroupName'};

    $log->debug("Adding group " . $params->{'newGroupName'} . "  Code: " . $lastID);
    $prefs->set('groups', \%groups);
}

sub makePlayerList {
    @playerList = ();
    foreach my $client (Slim::Player::Client::clients()) {
	my $clientPrefs = $prefs->client($client);
	my $player = { "name" => $client->name(), "id" => $client->id() };
	my %groups = % { $prefs->get('groups') };
	foreach my $group (keys %groups)  {
	    $player->{ $group } = ($clientPrefs->get($group) || 0);
	}
	push @playerList, $player;
    }
}

sub deleteGroup {
    my $del = shift;

    return unless defined $prefs->get('groups');

    my %groups = % { $prefs->get('groups') };
    $log->debug("Deleting " . $groups{$del});
    delete $groups{$del};
    $prefs->set('groups', \%groups);
    foreach my $client (Slim::Player::Client::clients()) {
	$prefs->client($client)->remove($del);
    }
}
1;
