/*
 * =============================================================================
 * MOTDgd In-Game Advertisements
 * Displays MOTDgd Related In-Game Advertisements
 *
 * Copyright (C)2013-2014 MOTDgd Ltd. All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
*/

// ====[ INCLUDES | DEFINES ]============================================================

#pragma semicolon 1
#include <sourcemod>

#define PLUGIN_VERSION "2.1.0"


// ====[ HANDLES | CVARS | VARIABLES ]===================================================

new Handle:g_motdID;
new Handle:g_OnConnect;
new Handle:g_immunity;
new Handle:g_OnOther;
new Handle:g_Review;
new Handle:g_ForceTime;

new const String:g_GamesSupported[][] = {
	"tf",
	"csgo",
	"cstrike",
	"dod",
	"nucleardawn",
	"hl2mp",
	"left4dead",
	"left4dead2"
};
new String:gameDir[255];
new String:g_serverIP[255];

new g_serverPort;
new g_timepending[MAXPLAYERS+1];
new Float:g_reviewtime;

new bool:VGUICaught[MAXPLAYERS+1];
new bool:CanView[MAXPLAYERS+1];
new bool:CanContinue[MAXPLAYERS+1];


// ====[ PLUGIN | FORWARDS ]========================================================================

public Plugin:myinfo =
{
	name = "MOTDgd Adverts",
	author = "Blackglade",
	description = "Displays MOTDgd In-Game Advertisements",
	version = PLUGIN_VERSION,
	url = "http://motdgd.com"
}

public OnPluginStart()
{

	// Global Server Variables //
	new bool:exists = false;
	GetGameFolderName(gameDir, sizeof(gameDir));
	for (new i = 0; i < sizeof(g_GamesSupported); i++){
		if(StrEqual(g_GamesSupported[i], gameDir))
			exists = true;
	}
	if(!exists)
		SetFailState("This game is currently not supported by MOTDgd!");

	new Handle:serverIP = FindConVar("hostip");
	new Handle:serverPort = FindConVar("hostport");
	if(serverIP == INVALID_HANDLE || serverPort == INVALID_HANDLE)
		SetFailState("Could not determine server ip and port.");

	new IP = GetConVarInt(serverIP);
	g_serverPort = GetConVarInt(serverPort);
	Format(g_serverIP, sizeof(g_serverIP), "%d.%d.%d.%d", IP >>> 24 & 255, IP >>> 16 & 255, IP >>> 8 & 255, IP & 255);
	// Global Server Variables //


	// Plugin ConVars // 
	CreateConVar("sm_motdgd_version", PLUGIN_VERSION, "[SM] MOTDgd Plugin Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);

	g_motdID = CreateConVar("sm_motdgd_userid", "0", "MOTDgd User ID. This number can be found at: http://motdgd.com/portal/");
	g_immunity = CreateConVar("sm_motdgd_immunity", "1", "Enable/Disable MOTDgd advert immunity");
	g_OnConnect = CreateConVar("sm_motdgd_onconnect", "1", "Enable/Disable MOTDgd advert on connect");
	g_ForceTime = CreateConVar("sm_motdgd_force", "10.0", "Max time (in seconds) to force MOTDgd advert", _, true, 5.0, true, 30.0);

	if(!StrEqual(gameDir, "left4dead2") && !StrEqual(gameDir, "left4dead")){
		g_OnOther = CreateConVar("sm_motdgd_onother", "0", "Set 0 to disable, 1 to show on round end, 2 to show on player death, 3 to show on both");
		g_Review = CreateConVar("sm_motdgd_review", "30.0", "Set time (in minutes) to re-display the ad. ConVar sm_motdgd_onother must be configured", _, true, 15.0);
		if(GetConVarInt(g_OnOther) != 0)
			g_reviewtime = GetConVarFloat(g_Review) * 60;
	}
	AutoExecConfig(true);
	// Plugin ConVars //


	// MOTDgd MOTD Stuff //
	new UserMsg:datVGUIMenu = GetUserMessageId("VGUIMenu");
	if(datVGUIMenu == INVALID_MESSAGE_ID)
		SetFailState("This game doesn't support VGUI menus.");
	HookUserMessage(datVGUIMenu, OnVGUIMenu, true);
	AddCommandListener(ClosedMOTD, "closed_htmlpage");

	HookEventEx("player_transitioned", Event_PlayerTransitioned);
	HookEventEx("player_death", Event_Death);
	HookEventEx("cs_win_panel_round", Event_End);
	HookEventEx("round_win", Event_End);
	HookEventEx("dod_round_win", Event_End);
	HookEventEx("teamplay_win_panel", Event_End);
	HookEventEx("arena_win_panel", Event_End);
	// MOTDgd MOTD Stuff //
}

public bool:OnClientConnect(client, String:rejectmsg[], maxlen)
{
	VGUICaught[client] = false;
	if(!StrEqual(gameDir, "left4dead2") && !StrEqual(gameDir, "left4dead"))
		CanView[client] = true;

	return true;
}

public OnClientDisconnect(client)
{
	VGUICaught[client] = false;
	if(!StrEqual(gameDir, "left4dead2") && !StrEqual(gameDir, "left4dead"))
		CanView[client] = true;
}


// ====[ FUNCTIONS ]=====================================================================

public Action:Event_End(Handle:event, const String:name[], bool:dontBroadcast)
{
	new userId = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userId);

	if(GetConVarFloat(g_Review) > 15.0 || !GetConVarInt(g_OnOther) || GetConVarInt(g_OnOther) != 2)
		return Plugin_Continue;

	if(IsValidClient(client) && CanView[client]){
		CreateTimer(0.1, PreMotdTimer, client);
		CanView[client] = false;
		CreateTimer(g_reviewtime, ReviewMotdTimer, client);
	}

	return Plugin_Continue;
}

public Action:Event_Death(Handle:event, const String:name[], bool:dontBroadcast)
{
	new userId = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userId);

	if(GetConVarFloat(g_Review) > 15.0 || !GetConVarInt(g_OnOther) || GetConVarInt(g_OnOther) != 1)
		return Plugin_Continue;

	if(StrEqual(gameDir, "left4dead2") || StrEqual(gameDir, "left4dead"))
		return Plugin_Continue;

	if(IsValidClient(client) && CanView[client]){
		CreateTimer(0.1, PreMotdTimer, client);
		CanView[client] = false;
		CreateTimer(g_reviewtime, ReviewMotdTimer, client);
	}

	return Plugin_Continue;
}

public Action:Event_PlayerTransitioned(Handle:event, const String:name[], bool:dontBroadcast)
{
	new userId = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userId);

	if(IsValidClient(client) && GetConVarBool(g_OnConnect))
		CreateTimer(0.1, PreMotdTimer, client);

	return Plugin_Continue;
}

public Action:OnVGUIMenu(UserMsg:msg_id, Handle:bf, const players[], playersNum, bool:reliable, bool:init)
{
	new client = players[0];

	if(playersNum > 1 || !IsValidClient(client) || VGUICaught[client] || !GetConVarBool(g_OnConnect))
		return Plugin_Continue;

	VGUICaught[client] = true;
	CreateTimer(0.1, PreMotdTimer, client);

	if(!StrEqual(gameDir, "left4dead2") && !StrEqual(gameDir, "left4dead")){
		CanView[client] = false;
		CreateTimer(g_reviewtime, ReviewMotdTimer, client);
	}
	return Plugin_Handled;
}

public Action:ClosedMOTD(client, const String:command[], argc)
{
	if(!IsValidClient(client))
		return Plugin_Handled;

	if(CanContinue[client]){
		if(StrEqual(gameDir, "cstrike") || StrEqual(gameDir, "csgo"))
			FakeClientCommand(client, "joingame");
		else if(StrEqual(gameDir, "nucleardawn") || StrEqual(gameDir, "dod"))
			ClientCommand(client, "changeteam");
	} else {
		ShowMOTDScreen(client);
	}
	return Plugin_Handled;
}

public Action:ContinueMotdTimer(Handle:timer, any:client)
{
	CanContinue[client] = true;
}

public Action:ReviewMotdTimer(Handle:timer, any:client)
{
	CanView[client] = true;
}

public Action:UpdateMotdTime(Handle:timer, any:client)
{
	if(!g_timepending[client])
		return Plugin_Stop;
	else {
		g_timepending[client]--;
		PrintCenterText(client, "Please wait %d seconds or until the ad has finished", g_timepending[client]);
	}
	return Plugin_Continue;
}

public Action:PreMotdTimer(Handle:timer, any:client)
{
	ShowMOTDScreen(client);
	CanContinue[client] = false;
	CreateTimer(GetConVarFloat(g_ForceTime), ContinueMotdTimer, client);
	g_timepending[client] = GetConVarInt(g_ForceTime);
	CreateTimer(1.0, UpdateMotdTime, client, TIMER_REPEAT);
}


stock ShowMOTDScreen(client)
{
	new Handle:kv = CreateKeyValues("data");

	if(StrEqual(gameDir, "left4dead") || StrEqual(gameDir, "left4dead2"))
		KvSetString(kv, "cmd", "closed_htmlpage");
	else    
		KvSetNum(kv, "cmd", 5);

	decl String:steamid[255], String:url[255];
	if(GetClientAuthString(client, steamid, sizeof(steamid)))
		Format(url, sizeof(url), "http://motdgd.com/motd/?user=%d&ip=%s&pt=%d&v=%s&st=%s&gm=%s", GetConVarInt(g_motdID), g_serverIP, g_serverPort, PLUGIN_VERSION, steamid, gameDir);
	else
		Format(url, sizeof(url), "http://motdgd.com/motd/?user=%d&ip=%s&pt=%d&v=%s&st=NULL&gm=%s", GetConVarInt(g_motdID), g_serverIP, g_serverPort, PLUGIN_VERSION, gameDir);
	
	
	KvSetString(kv, "msg", url);
	KvSetString(kv, "title", "MOTDgd AD");
	KvSetNum(kv, "type", MOTDPANEL_TYPE_URL);
	ShowVGUIPanel(client, "info", kv, true);
	CloseHandle(kv);
}

stock bool:IsValidClient(i){
	if(!IsClientInGame(i) || IsClientSourceTV(i) || IsClientReplay(i) || IsFakeClient(i) || !i || !IsClientConnected(i)) 
		return false;
	if(!GetConVarBool(g_immunity)) 
		return true;
	if(CheckCommandAccess(i, "MOTDGD_Immunity", ADMFLAG_RESERVATION)) 
		return false;

	return true;
}
