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

my $prefs = preferences('plugin.synchronizer');
my $log   = logger('plugin.synchronizer');
my @playerList;

sub name {
    $log->debug("Synchronizer::Settings->name() called");
    return Slim::Web::HTTP::protectName('PLUGIN_SYNCHRONIZER_NAME');
}

sub page {
    $log->debug("Synchronizer::Settings->page() called");
    return Slim::Web::HTTP::protectURI('plugins/Synchronizer/settings/basic.html');
}

sub handler {
    my ($class, $client, $params) = @_;
    $log->debug("Synchronizer::Settings->handler() called. " . + $params->{'saveSettings'});
    ###### DEBUG
    foreach my $key (keys %$params)
    {
	$log->debug("Synchronizer::Settings->handler(): Key: " . $key . " :: " . $params->{$key});
    }
    ###### DEBUG
    if ($params->{'saveSettings'})
    {
	$log->debug("Synchronizer::Settings->handler() save settings");
	$log->debug("NewGroupName: " . $params->{'newGroupName'});
	if ((defined $params->{'newGroupName'}) && ($params->{'newGroupName'} ne ''))
	{
	    addGroup($params);
	}
	$log->debug("Groups: " . $params->{'groups'});
	foreach my $group (@{ $prefs->get('groups') })
	{
	    $log->debug("Checking group " . $group->{'name'} . "::" . $group->{'id'});
	    my $id = $group->{'id'};
	    my $dKey = "delete.$id";
	    $log->debug("DeleteKey $dKey");
	    if ($params->{"delete.$id"})
	    {
		deleteGroup($id);
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

    my @groups = ( );

    ## Compute the ID of the new group
    my $lastID = $prefs->get('lastID') + 1;
    $prefs->set('lastID', $lastID);

    @groups = @ { $prefs->get('groups') } if (defined $prefs->get('groups'));

    my $group = { 'id' => $lastID, 'name' => $params->{'newGroupName'} };

    push @groups, \$group;

    $log->debug("Adding group " . $params->{'newGroupName'} . "  Now " . $#groups . " groups");
    $prefs->set('groups', \@groups);
}

sub makePlayerList {
    @playerList = ();
    foreach my $client (Slim::Player::Client::clients()) {
	$log->debug("Adding " . $client->name() . "::" . $client->id());
	my $player = { "name" => $client->name(), "id" => $client->id() };
	push @playerList, $player;
    }
}

sub deleteGroup {
    my $del = shift;
    $log->debug("DeleteGroup: " . $del);
    my @groups = @ { $prefs->get('groups') } if (defined $prefs->get('groups'));
    for (my $i = 0; $i < $#groups; $i++)
    {
	delete @groups[$i] if ($groups[$i]->{'id'} == $del);
    }
    $prefs->set('groups', \@groups);
}
1;
