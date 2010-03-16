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
    return Slim::Web::HTTP::CSRF->protectName('PLUGIN_SYNCHRONIZER_NAME');
}

sub page {
    return Slim::Web::HTTP::CSRF->protectURI('plugins/Synchronizer/settings/basic.html');
}

sub prefs {
    return ($prefs, qw(powerup));
}

sub handler {
    my ($class, $client, $params) = @_;
    $log->debug("Synchronizer::Settings->handler() called.");
    if ($params->{'saveSettings'})
    {
        $log->debug("Synchronizer::Settings->handler() save settings");
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
					$log->debug("Setting: Group: " . $group . " Client: " . $client->name . " Value: " . $params->{$tag});
                    $prefs->client($client)->set($group, $params->{$tag});
                }
            }
        }
        if ((defined $params->{'newGroupName'}) && ($params->{'newGroupName'} ne ''))
        {
            addGroup($params->{'newGroupName'});
        }
        if ((defined $params->{'cloneGroupName'}) && ($params->{'cloneGroupName'} ne ''))
        {
            my $newGroup = addGroup($params->{'cloneGroupName'});
			cloneSettings($newGroup);
        }
    }
    $params->{'newGroupName'} = undef;
    $params->{'cloneGroupName'} = undef;
    $params->{'groups'} = $prefs->get('groups');
    makePlayerList();
    $params->{'players'} = \@playerList;
    
    return $class->SUPER::handler( $client, $params );
}

sub addGroup {
	my $name   = shift;
    my %groups;

    ## Compute the ID of the new group
    my $lastID = ($prefs->get('lastID') || 0) + 1;
    $prefs->set('lastID', $lastID);

    %groups = % { $prefs->get('groups') };

    $groups{$lastID} = $name;

    $log->debug("Adding group " . $name . "  Code: " . $lastID);
    $prefs->set('groups', \%groups);
	return $lastID;
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

sub cloneSettings {
    my $group = shift;
    foreach my $client (Slim::Player::Client::clients()) {
        my $master = 0;
        $master = $client->master()->id() if ($client->isSynced());
        $log->debug("Setting Group " . $group . " Master for " . $client->name() . " to " . $master);
        $prefs->client($client)->set($group, $master);
		# $prefs->client($client)->set($group, $params->{$tag});
    }
}

1;
