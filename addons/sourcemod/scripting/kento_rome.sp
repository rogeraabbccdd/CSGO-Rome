#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <devzones>
#include <smlib>
#include <movement>
#include <clientprefs>
#include <kento_csgocolors>
#include <SteamWorks>

#define ZONE_NAME "Rome"

#define MAX_ANTHEM_COUNT 1000

#pragma newdecls required

int Roman1;
int Roman2;
int Wall1Model;
int Wall2Model;
int Wall1Ref = INVALID_ENT_REFERENCE;
int Wall2Ref = INVALID_ENT_REFERENCE;
float zone_pos[MAXPLAYERS+1][3];
bool canfight = false;
int score1 = 0;
int score2 = 0;

ConVar mp_death_drop_gun;
ConVar mp_teammates_are_enemies;
ConVar mp_ignore_round_win_conditions;

float wall_y1 = 180.0;
float wall_y2 = -180.0;

Handle TimerCloseWall = INVALID_HANDLE;
Handle TimerOpenWall = INVALID_HANDLE;
Handle TimerStart = INVALID_HANDLE;

int countdown = 4;

Handle Anthemcookie, Anthemcookie2;
int AnthemCount, AnthemSelected[MAXPLAYERS + 1];
char Configfile[1024],
  AnthemName[MAX_ANTHEM_COUNT + 1][1024],
  AnthemFile[MAX_ANTHEM_COUNT + 1][1024],
  AnthemSelectedName[MAXPLAYERS + 1][1024];
float AnthemVol[MAXPLAYERS + 1];

float Spawnpos[MAXPLAYERS + 1][3];

enum struct STATS
{
  int WINS;
  int LOSES;
  int DEATHS;
  int POINTS0;
  int POINTS1;
  int POINTS2;
  int POINTS3;
}
STATS Stats[MAXPLAYERS + 1];
Database ddb = null;
int iTotalPlayers;

float poster1[3] = {-1023.968750, 0.0, 310.0};
float poster2[3] = {1015.968750, 0.0, 310.0};
float poster3[3] = {0.0, 815.0, 310.0};
float poster4[3] = {0.0, -815.0, 310.0};
int decal1;
int decal2;

public Plugin myinfo =
{
  name = "Rome Arena",
  author = "Kento",
  description = "Rome Arena",
  version = "1.0",
  url = "http://steamcommunity.com/id/kentomatoryoshika/"
};

public void OnPluginStart()
{
  HookEvent("player_spawn", Event_PlayerSpawn);
  HookEvent("round_start", Event_RoundStart);
  HookEvent("player_death", Event_PlayerDeath);
  HookEvent("player_team", Event_PlayerTeam);

  mp_death_drop_gun = FindConVar("mp_death_drop_gun");
  mp_teammates_are_enemies = FindConVar("mp_teammates_are_enemies");
  mp_ignore_round_win_conditions = FindConVar("mp_ignore_round_win_conditions");

  mp_death_drop_gun.AddChangeHook(OnConVarChanged);
  mp_teammates_are_enemies.AddChangeHook(OnConVarChanged);
  mp_ignore_round_win_conditions.AddChangeHook(OnConVarChanged);

  RegConsoleCmd("sm_rome", Command_Rome, "Rome menu");

  Anthemcookie = RegClientCookie("rome_anthem", "Rome Victory Anthem", CookieAccess_Private);
  Anthemcookie2 = RegClientCookie("rome_anthemvol", "Rome Victory Anthem", CookieAccess_Private);
}

public void OnConfigsExecuted()
{
  LoadAnthemConfig();

  if (SQL_CheckConfig("rome"))
  {
    SQL_TConnect(OnSQLConnect, "rome");
  }
  else if (!SQL_CheckConfig("rome"))
  {
    SetFailState("Can't find an entry in your databases.cfg with the name \"rome\".");
    return;
  }
}

public void OnClientPutInServer(int client)
{
  if (IsValidClient(client) && !IsFakeClient(client))	OnClientCookiesCached(client);
}

public void OnClientCookiesCached(int client)
{
  if(!IsValidClient(client) && IsFakeClient(client))	return;

  char scookie[1024];
  GetClientCookie(client, Anthemcookie, scookie, sizeof(scookie));
  if(!StrEqual(scookie, ""))
  {
    AnthemSelected[client] = FindAnthemIDByName(scookie);
    if(AnthemSelected[client] > 0)	strcopy(AnthemSelectedName[client], sizeof(AnthemSelectedName[]), scookie);
    else
    {
      AnthemSelectedName[client] = "";
      SetClientCookie(client, Anthemcookie, "");
    }
  }
  else if(StrEqual(scookie,""))	AnthemSelectedName[client] = "";

  GetClientCookie(client, Anthemcookie2, scookie, sizeof(scookie));
  if(!StrEqual(scookie, ""))
  {
    AnthemVol[client] = StringToFloat(scookie);
  }
  else if(StrEqual(scookie,""))	AnthemVol[client] = 1.0;
}

int FindAnthemIDByName(char [] name)
{
  int id = 0;

  for(int i = 1; i <= AnthemCount; i++)
  {
    if(StrEqual(AnthemName[i], name))	id = i;
  }

  return id;
}

void LoadAnthemConfig()
{
  BuildPath(Path_SM, Configfile, 1024, "configs/kento_rome_anthem.cfg");

  if(!FileExists(Configfile))
    SetFailState("Can not find config file \"%s\"!", Configfile);


  KeyValues kv = CreateKeyValues("MVP");
  kv.ImportFromFile(Configfile);

  AnthemCount = 1;

  // Read Config
  if(kv.GotoFirstSubKey())
  {
    char name[1024];
    char file[1024];

    do
    {
      kv.GetSectionName(name, sizeof(name));
      kv.GetString("file", file, sizeof(file));

      strcopy(AnthemName[AnthemCount], sizeof(AnthemName[]), name);
      strcopy(AnthemFile[AnthemCount], sizeof(AnthemFile[]), file);

      char filepath[1024];
      Format(filepath, sizeof(filepath), "sound/%s", AnthemFile[AnthemCount])
      AddFileToDownloadsTable(filepath);

      char soundpath[1024];
      Format(soundpath, sizeof(soundpath), "*/%s", AnthemFile[AnthemCount]);
      FakePrecacheSound(soundpath);

      AnthemCount++;
    }
    while (kv.GotoNextKey());
  }

  kv.Rewind();
  delete kv;
}


public void OnMapStart() {
  PrecacheModel("models/props_urban/fence001_128.mdl", true);

  FakePrecacheSound("*/doors/door_metal_gate_move1.wav");

  FakePrecacheSound("*/rome/ready.mp3");
  FakePrecacheSound("*/rome/fight.mp3");
  AddFileToDownloadsTable("sound/rome/fight.mp3");
  AddFileToDownloadsTable("sound/rome/ready.mp3");

  int entity = -1;
  while((entity = FindEntityByClassname(entity, "trigger_multiple")) != INVALID_ENT_REFERENCE)
  {
    char targetname[64];

    if(!GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname)) || StrContains(targetname, "sm_devzone") == -1) {
      AcceptEntityInput(entity, "kill");
    }
  }

  mp_death_drop_gun.BoolValue = false;
  mp_teammates_are_enemies.BoolValue = true;
  mp_ignore_round_win_conditions.BoolValue = true;

  decal1 = PrecacheDecal("rome/fight", true);
  decal2 = PrecacheDecal("rome/fight2", true);
  AddFileToDownloadsTable("materials/rome/fight.vmt");
  AddFileToDownloadsTable("materials/rome/fight.vtf");
  AddFileToDownloadsTable("materials/rome/fight2.vmt");
  AddFileToDownloadsTable("materials/rome/fight2.vtf");
  
  TE_SetupBSPDecal(poster1, decal1);
  TE_SendToAll();
  TE_SetupBSPDecal(poster2, decal1);
  TE_SendToAll();
  TE_SetupBSPDecal(poster3, decal2);
  TE_SendToAll();
  TE_SetupBSPDecal(poster4, decal2);
  TE_SendToAll();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
  if (convar == mp_death_drop_gun)
  {
    mp_death_drop_gun.BoolValue = false;
  }
  else if (convar == mp_teammates_are_enemies) {
    mp_teammates_are_enemies.BoolValue = true;
  }
  else if (convar == mp_ignore_round_win_conditions) {
    mp_ignore_round_win_conditions.BoolValue = true;
  }
}

public void OnClientPostAdminCheck(int client) {
  SDKHook(client, SDKHook_TraceAttack, TraceAttack);
  SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);

  if(ddb != null)	LoadClientStats(client);

  TE_SetupBSPDecal(poster1, decal1);
  TE_SendToClient(client);
  TE_SetupBSPDecal(poster2, decal1);
  TE_SendToClient(client);
  TE_SetupBSPDecal(poster3, decal2);
  TE_SendToClient(client);
  TE_SetupBSPDecal(poster4, decal2);
  TE_SendToClient(client);
}

public void OnClientDisconnect(int client){
  SDKUnhook(client, SDKHook_TraceAttack, TraceAttack);
  SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);

  int num = NumRoman(client);
  if(num == 1) {
    Roman1 = 0;
    HandleWin(Roman2);
  }
  else if (num == 2) {
    Roman2 = 0;
    HandleWin(Roman1);
  }

  SaveClientStats(client);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
  Roman1 = 0;
  Roman2 = 0;

  wall_y1 = 180.0;
  wall_y2 = -180.0;

  for (int i = 1; i <= MaxClients; i++)
  {
    if(IsValidClient(i))  RemoveWeapons(i);
  }

  TE_SetupBSPDecal(poster1, decal1);
  TE_SendToAll();
  TE_SetupBSPDecal(poster2, decal1);
  TE_SendToAll();
  TE_SetupBSPDecal(poster3, decal2);
  TE_SendToAll();
  TE_SetupBSPDecal(poster4, decal2);
  TE_SendToAll();
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
  int client = GetClientOfUserId(event.GetInt("userid"));

  CreateTimer(0.5, GiveHealth, client);
  SetEntityHealth(client, 100);

  GetEntPropVector(client, Prop_Send, "m_vecOrigin", Spawnpos[client]);
}

public Action GiveHealth(Handle timer, int client)
{
  if(IsValidClient(client)) SetEntityHealth(client, 100);
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
  int client = GetClientOfUserId(event.GetInt("userid"));

  int num = NumRoman(client);
  if(num == 1) HandleWin(Roman2);
  else if(num == 2) HandleWin(Roman1);
  
  CreateTimer(7.0, RespawnTimer, client);
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
  int client = GetClientOfUserId(event.GetInt("userid"));
  int team = event.GetInt("team");
  int oldteam = GetEventInt(event, "oldteam");

  if(team > CS_TEAM_SPECTATOR && oldteam <= CS_TEAM_SPECTATOR) CreateTimer(3.0, RespawnTimer , client);
}

void HandleWin(int winner) {
  char message[128];

  canfight = false;

  int num = NumRoman(winner);

  if(num == 2) {
    Stats[Roman2].WINS++;
    Stats[Roman1].LOSES++;
    CPrintToChatAll("{GREEN}[ROME] {NORMAL} 對戰結果: {PINK} %N {LIGHTGREEN}勝利 {NORMAL}, {BLUE}10 : {RED}%d", Roman2, score1);
    SetEntityHealth(Roman2, 100);
    Format(message, sizeof(message), "%N  WIN!", Roman2);
    PrintHUD(message, 7.0);
    SaveClientStats(Roman2);
    SaveClientStats(Roman1);
    RemoveWeapons(Roman2);
    GiveWeapons(Roman2, false);
    Roman1 = 0;
  }
  else if (num == 1) {
    Stats[Roman1].WINS++;
    Stats[Roman2].LOSES++;
    CPrintToChatAll("{GREEN}[ROME] {NORMAL} 對戰結果: {PINK} %N {LIGHTGREEN}勝利 {NORMAL}, {BLUE}10 : {RED}%d", Roman1, score2);
    SetEntityHealth(Roman1, 100);
    Format(message, sizeof(message), "%N  WIN!", Roman1);
    PrintHUD(message, 7.0);
    SaveClientStats(Roman2);
    SaveClientStats(Roman1);
    RemoveWeapons(Roman1);
    GiveWeapons(Roman1, false);
    Roman2 = 0;
  }

  CreateTimer(7.0, OpenWallDelay);

  int id = AnthemSelected[winner];
  char sound[1024];
  Format(sound, sizeof(sound), "*/%s", AnthemFile[id]);

  if(StrEqual(AnthemSelectedName[winner], "") || AnthemSelected[winner] == 0)	return;

  for(int i = 1; i <= MaxClients; i++)
  {
    if (IsValidClient(i) && !IsFakeClient(i))
    {
      // Announce MVP
      PrintHintText(i, "播放 %N 的勝利歌曲: %s", winner, AnthemSelectedName[winner]);

      // Play MVP Anthem
      EmitSoundToClient(i, sound, SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NONE, _, AnthemVol[i]);
    }
  }
}

public Action OpenWallDelay (Handle timer) {
  for (int i = 1; i <= MaxClients; i++)
  {
    if(IsValidClient(i) && !IsFakeClient(i))  EmitSoundToClient(i, "*/doors/door_metal_gate_move1.wav", SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NONE, _, 1.0);
  }
  TimerOpenWall = CreateTimer(0.05, MoveOpenWall, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public Action MoveOpenWall (Handle timer) {
  float pos[3];
  wall_y1 += 9.0;
  wall_y2 -= 9.0;

  int entity  = EntRefToEntIndex(Wall1Ref);
  if(entity != INVALID_ENT_REFERENCE && IsValidEdict(entity) && entity != 0)
  {
    pos[0] = 210.0;
    pos[1] = wall_y1;
    pos[2] = 25.0;
    TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
  }

  entity  = EntRefToEntIndex(Wall2Ref);
  if(entity != INVALID_ENT_REFERENCE && IsValidEdict(entity) && entity != 0)
  {
    pos[0] = -210.0;
    pos[1] = wall_y2;
    pos[2] = 25.0;
    TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
  }

  if(wall_y1 >= 180.0) {
    if(TimerOpenWall != INVALID_HANDLE)
    {
      KillTimer(TimerOpenWall);
      TimerOpenWall = INVALID_HANDLE;
    }

    RemoveWall();
  }
}

public Action RespawnTimer(Handle timer, int client)
{
  if(IsValidClient(client))  CS_RespawnPlayer(client);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
  if(IsValidClient(client) && NumRoman(client) > 0) {
    if(buttons & IN_ATTACK2 == IN_ATTACK2)
    {
      int weaponIdx = GetPlayerWeaponSlot(client, 11);
      if(weaponIdx != -1)
      {
        Client_SetActiveWeapon(client, weaponIdx);
      }
    }
    else if(buttons & IN_ATTACK == IN_ATTACK)
    {
      Client_SetActiveWeapon(client, GetPlayerWeaponSlot(client, CS_SLOT_KNIFE));
    }
    int flags = GetEntityFlags(client);
    SetEntProp(client, Prop_Data, "m_fFlags", flags|IN_ATTACK);
  }

  return Plugin_Continue;
}


public void Zone_OnClientEntry(int client, const char [] zone)
{
  if(client < 1 || client > MaxClients || !IsClientInGame(client) ||!IsPlayerAlive(client)) return;

  if(StrContains(zone, ZONE_NAME, false) == -1) return;

  SetEntityHealth(client, 100);

  if(Roman1 == 0 && Roman2 == 0) {
    Roman1 = client;
    GiveWeapons(client);
  }
  else if (Roman1 == 0 && Roman2 != 0) {
    Roman1 = client;
    GiveWeapons(client);
    CreateTimer(1.5, SpawnWallDelay);
  }
  else if (Roman1 != 0 && Roman2 == 0) {
    Roman2 = client;
    GiveWeapons(client);
    CreateTimer(1.5, SpawnWallDelay);
  }
  else {
    float clientloc[3];
    GetClientAbsOrigin(client, clientloc);
    Zone_GetZonePosition(zone, false, zone_pos[client]);
    KnockbackSetVelocity(client, zone_pos[client], clientloc, 300.0);
  }
}

void PrintHUD(const char[] message, float displaytime = 200.0) {
  for(int i = 1; i <= MaxClients; i++)
  {
    if(IsValidClient(i) && !IsFakeClient(i))
    {
      SetHudTextParams(-1.0, 0.125, displaytime, 255, 255, 255, 255, 0, 0.25, 0.1, 0.2);
      ShowHudText(i, 1, message);
    }
  }
}

void GiveWeapons(int client, bool showhint = true) {
  if(!IsValidClient(client)) return;
  
  int weaponIdx = GetPlayerWeaponSlot(client, 11);
  if(weaponIdx == -1)
  {
    GivePlayerItem(client, "weapon_shield");
  }

  if(showhint) PrintHintText(client, "滑鼠左鍵換刀攻擊\n滑鼠右鍵換盾防禦");

  Client_SetActiveWeapon(client, GetPlayerWeaponSlot(client, CS_SLOT_KNIFE));
}

void RemoveWeapons(int client) {
  if(!IsValidClient(client)) return;

  int weaponIdx = GetPlayerWeaponSlot(client, 11);
  if(weaponIdx != -1)
  {
    RemovePlayerItem(client, weaponIdx);
    RemoveEdict(weaponIdx);
  }
}

public void Zone_OnClientLeave(int client, const char [] zone)
{
  if(client < 1 || client > MaxClients || !IsClientInGame(client) ||!IsPlayerAlive(client))
    return;

  if(StrContains(zone, ZONE_NAME, false) == -1) return;

  int num = NumRoman(client)
  if(num > 0 && (Roman1 == 0 || Roman2 == 0)) {
    RemoveWeapons(client);

    if(num == 1) Roman1 = 0;
    else if(num == 2) Roman2 = 0;
  }
  else if(num > 0 && Roman1 != 0 && Roman2 != 0) {
    float pos[3];
    pos[0] = 0.0;
    pos[1] = 0.0;
    pos[2] = 75.0;
    TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
  }
}

void RemoveWall() {
  int entity1  = EntRefToEntIndex(Wall1Ref);
  if(entity1 != INVALID_ENT_REFERENCE && IsValidEdict(entity1) && entity1 != 0)
  {
    AcceptEntityInput(Wall1Model, "kill");
    Wall1Ref = INVALID_ENT_REFERENCE;
  }

  int entity2  = EntRefToEntIndex(Wall2Ref);
  if(entity2 != INVALID_ENT_REFERENCE && IsValidEdict(entity2) && entity2 != 0)
  {
    AcceptEntityInput(Wall2Model, "kill");
    Wall2Ref = INVALID_ENT_REFERENCE;
  }
}

void SpawnWall () {
  Wall1Model = CreateEntityByName("prop_dynamic");

  SetEntityModel(Wall1Model, "models/props_urban/fence001_128.mdl");
  SetEntPropString(Wall1Model, Prop_Data, "m_iName", "Wall1");
  SetEntProp(Wall1Model, Prop_Data, "m_nSolidType", 6);

  DispatchSpawn(Wall1Model);

  Wall1Ref = EntIndexToEntRef(Wall1Model);

  float pos[3];
  pos[0] = 210.0;
  pos[1] = 180.0;
  pos[2] = 25.0;

  TeleportEntity(Wall1Model, pos, NULL_VECTOR, NULL_VECTOR);

  /***/

  Wall2Model = CreateEntityByName("prop_dynamic");

  SetEntityModel(Wall2Model, "models/props_urban/fence001_128.mdl");
  SetEntPropString(Wall2Model, Prop_Data, "m_iName", "Wall2");
  SetEntProp(Wall2Model, Prop_Data, "m_nSolidType", 6);

  DispatchSpawn(Wall2Model);

  Wall2Ref = EntIndexToEntRef(Wall2Model);

  pos[0] = -210.0;
  pos[1] = 180.0;
  pos[2] = 25.0;

  TeleportEntity(Wall2Model, pos, NULL_VECTOR, NULL_VECTOR);

  TimerCloseWall = CreateTimer(0.05, MoveCloseWall, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

  for (int i = 1; i <= MaxClients; i++)
  {
    if(IsValidClient(i) && !IsFakeClient(i))  EmitSoundToClient(i, "*/doors/door_metal_gate_move1.wav", SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NONE, _, 1.0);
  }
}

public Action SpawnWallDelay (Handle timer) {
  SpawnWall();
  Movement_SetVelocityModifier(Roman1, 1.0);
  Movement_SetVelocity(Roman1, view_as<float>( { 0.0, 0.0, 0.0 } ));
  Movement_SetVelocityModifier(Roman2, 1.0);
  Movement_SetVelocity(Roman2, view_as<float>( { 0.0, 0.0, 0.0 } ));
  SetEntityMoveType(Roman1, MOVETYPE_NONE);
  SetEntityMoveType(Roman2, MOVETYPE_NONE);

  score1 = 0;
  score2 = 0;

  float pos[3];
  pos[0] = -447.88;
  pos[1] = 260.0;
  pos[2] = 64.0;
  for (int i = 1; i <= MaxClients; i++)
  {
    if(IsValidClient(i) && NumRoman(i) == 0 && Zone_IsClientInZone(i, ZONE_NAME))
    {
      TeleportEntity(i, Spawnpos[i], NULL_VECTOR, NULL_VECTOR); 
    }
  }
}

public Action MoveCloseWall (Handle timer) {
  float pos[3];
  wall_y1 -= 9.0;
  wall_y2 += 9.0;
  
  int entity  = EntRefToEntIndex(Wall1Ref);
  if(entity != INVALID_ENT_REFERENCE && IsValidEdict(entity) && entity != 0)
  {
    pos[0] = 210.0;
    pos[1] = wall_y1;
    pos[2] = 25.0;
    TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
  }

  if(entity != INVALID_ENT_REFERENCE && IsValidEdict(entity) && entity != 0)
  {
    entity  = EntRefToEntIndex(Wall2Ref);
    pos[0] = -210.0;
    pos[1] = wall_y2;
    pos[2] = 25.0;
    TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
  }

  if(wall_y1 <= 0.0) {
    char message[128];
    Format(message, sizeof(message), "0 - %N   VS   %N - 0", Roman1, Roman2);
    CPrintToChatAll("{GREEN}[ROME] {NORMAL}對戰開始: {PINK}%N {NORMAL}VS {PINK}%N", Roman1, Roman2);
    PrintHUD(message);
    StartCountDown();

    if(TimerCloseWall != INVALID_HANDLE)
    {
      KillTimer(TimerCloseWall);
      TimerCloseWall = INVALID_HANDLE;
    }
  }
}

void StartCountDown() {
  float pos1[3];
  float pos2[3];
  float ang1[3];
  float ang2[3];

  pos1[0] = 140.0;
  pos1[1] = 0.0;
  pos1[2] = 75.0;

  ang1[0] = 0.0;
  ang1[1] = -180.0;
  ang1[2] = 0.0;

  pos2[0] = -140.0;
  pos2[1] = 0.0;
  pos2[2] = 75.0;

  ang2[0] = 0.0;
  ang2[1] = 0.0;
  ang2[2] = 0.0;

  TeleportEntity(Roman1, pos1, ang1, NULL_VECTOR);
  TeleportEntity(Roman2, pos2, ang2, NULL_VECTOR);
  TimerStart = CreateTimer(1.0, Start, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public Action Start(Handle timer) {
  countdown--;

  if(countdown <= 0) {
    canfight = true;
    PrintHintTextToAll("Fight!");
    SetEntityMoveType(Roman1, MOVETYPE_WALK);
    SetEntityMoveType(Roman2, MOVETYPE_WALK);

    if(TimerStart != INVALID_HANDLE)
    {
      KillTimer(TimerStart);
      TimerStart = INVALID_HANDLE;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
      if(IsValidClient(i) && !IsFakeClient(i))  EmitSoundToClient(i, "*/rome/fight.mp3", SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NONE, _, 1.0);
    }

    countdown = 4;
  } else {
    PrintHintTextToAll("%d", countdown);

    if(countdown == 3) {
      for (int i = 1; i <= MaxClients; i++)
      {
        if(IsValidClient(i) && !IsFakeClient(i))  EmitSoundToClient(i, "*/rome/ready.mp3", SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NONE, _, 1.0);
      }
    }
  }
}

int NumRoman (int client) {
  return client == Roman1 ? 1 : client == Roman2 ? 2 : 0;
}

stock bool IsValidClient(int client)
{
  if (client <= 0) return false;
  if (client > MaxClients) return false;
  if (!IsClientConnected(client)) return false;
  return IsClientInGame(client);
}

void KnockbackSetVelocity(int client, const float startpoint[3], const float endpoint[3], float magnitude)
{
    // Create vector from the given starting and ending points.
    float vector[3];
    MakeVectorFromPoints(startpoint, endpoint, vector);

    // Normalize the vector (equal magnitude at varying distances).
    NormalizeVector(vector, vector);

    // Apply the magnitude by scaling the vector (multiplying each of its components).
    ScaleVector(vector, magnitude);

    TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vector);
}

// block shield damage
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3]){
  if(weapon == -1) {
    damage = 0.0;
    return Plugin_Changed;
  }
  else return Plugin_Continue;
}

bool Trace_HitVictimOnly(int entity, int contentsMask, int victim)
{
  return entity == victim;
}

bool Trace_HitSelf(int entity, int contentsMask, any data)
{
  if (entity == data)	return false;
  return true;
}

bool IsKnifeClass(const char [] classname)
{
  if(StrContains(classname, "knife") != -1 || StrContains(classname, "bayonet") > -1)
    return true;

  return false;
}

public Action TraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup){

  if (!IsValidEntity(victim) || !IsValidClient(attacker)) return Plugin_Continue;

  float positions[3], angles[3], dmgpos[3];
  GetClientEyePosition(attacker, positions);
  GetClientEyeAngles(attacker, angles);

  TR_TraceRayFilter(positions, angles, MASK_SHOT, RayType_Infinite, Trace_HitVictimOnly, victim);

  int HitGroup = TR_GetHitGroup();

  TR_TraceRayFilter(positions, angles, MASK_SOLID, RayType_Infinite, Trace_HitSelf, attacker);
  if(TR_DidHit(INVALID_HANDLE))	TR_GetEndPosition(dmgpos);

  float dmg = 0.0;

  int weapon = GetEntPropEnt(attacker, Prop_Data, "m_hActiveWeapon");
  char Classname[13];
  GetEdictClassname(weapon, Classname, sizeof(Classname));

  if(!canfight || (NumRoman(attacker) == 0 && NumRoman(victim) == 0)) {
    dmg = 0.0;
  }
  else {
    if(IsKnifeClass(Classname)) {
      if(HitGroup == 1) {
        PrintHintText(attacker, "打頭不得分");
        CPrintToChatAll("{GREEN}[ROME] {PINK}%N {RED}打頭不得分", attacker);
        Stats[attacker].POINTS0++;
      }
      // else if(HitGroup == 4) {
      //   PrintHintText(attacker, "打左手得一分");
      //   CPrintToChatAll("{GREEN}[ROME] {PINK}%N {LIGHTGREEN}打左手得一分", attacker);
      //   Stats[attacker].POINTS1++;
      //   dmg = 10.0;
      // }
      else if(HitGroup == 5) {
        PrintHintText(attacker, "打右手得一分");
        CPrintToChatAll("{GREEN}[ROME] {PINK}%N {LIGHTGREEN}打右手得一分", attacker);
        Stats[attacker].POINTS1++;
        dmg = 10.0;
      }
      else if (damage > 65.0) {
        PrintHintText(attacker, "打背部得三分");
        CPrintToChatAll("{GREEN}[ROME] {PINK}%N {LIGHTGREEN}打背部得三分", attacker);
        Stats[attacker].POINTS3++;
        dmg = 30.0;
      }
      else {
        PrintHintText(attacker, "打正面得兩分");
        CPrintToChatAll("{GREEN}[ROME] {PINK}%N {LIGHTGREEN}打正面得兩分", attacker);
        Stats[attacker].POINTS2++;
        dmg = 20.0;
      }
    }

    ShowDamageText(dmgpos, angles, dmg);

    int victimRoman = NumRoman(victim);
    if(victimRoman == 1) {
      score2 = 10 - ((GetClientHealth(victim) - RoundToZero(dmg)) / 10);
      score1 = 10 - (GetClientHealth(attacker) / 10);
    }
    else if(victimRoman == 2) {
      score1 = 10 - ((GetClientHealth(victim) - RoundToZero(dmg)) / 10);
      score2 = 10 - (GetClientHealth(attacker) / 10);
    }
    char message[128];
    Format(message, sizeof(message), "%d - %N   VS   %N - %d", score1, Roman1, Roman2, score2);
    PrintHUD(message);
  }

  damage = dmg;

  return Plugin_Changed;
}

stock int ShowDamageText(float fPos[3], float fAngles[3], float fdmg)
{
  int entity = CreateEntityByName("point_worldtext");

  if(entity == -1)	return entity;

  char sdmg[10];
  Format(sdmg, sizeof(sdmg), "+%d", RoundToZero(fdmg) / 10);
  DispatchKeyValue(entity, "message", sdmg);

  DispatchKeyValue(entity, "textsize", "25");
  DispatchKeyValue(entity, "color", "255 255 255");

  TeleportEntity(entity, fPos, fAngles, NULL_VECTOR);

  CreateTimer(1.0, KillText, EntIndexToEntRef(entity));

  return entity;
}

public Action KillText(Handle timer, int ref)
{
  int entity = EntRefToEntIndex(ref);
  if(entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity))	return;
  AcceptEntityInput(entity, "kill");
}

stock void FakePrecacheSound(const char[] szPath)
{
  AddToStringTable(FindStringTable("soundprecache"), szPath);
}

public Action Command_Rome(int client, int args) {
  if(!IsValidClient(client)) return;
  ShowMainMenu(client);
}

void ShowMainMenu(int client) {
  Menu mainmenu = new Menu(MainMenu_Handler);
  mainmenu.SetTitle("羅馬競技生死鬥 by Kento");
  mainmenu.AddItem("anthem", "選擇勝利音樂");
  mainmenu.AddItem("anthem_vol", "勝利音樂音量");
  mainmenu.AddItem("stats", "查看統計資料");
  mainmenu.AddItem("top", "查看排名");
  mainmenu.Display(client, MENU_TIME_FOREVER);
}

public int MainMenu_Handler(Menu menu, MenuAction action, int client,int param)
{
  switch(action)
  {
    case MenuAction_Select:
    {
      char menuitem[20];
      menu.GetItem(param, menuitem, sizeof(menuitem));

      if(StrEqual(menuitem, "anthem")) ShowAnthemMenu(client);
      else if(StrEqual(menuitem, "anthem_vol")) ShowAnthemVolMenu(client);
      else if(StrEqual(menuitem, "stats")) {
        char RankQuery[512];
        Format(RankQuery, sizeof(RankQuery), "SELECT *, (wins / (loses + wins)) as wlr FROM rome ORDER BY wins DESC");
        ddb.Query(SQL_StatsCallback, RankQuery, GetClientUserId(client));
      }
      else if(StrEqual(menuitem, "top")) {
        char RankQuery[512];
        Format(RankQuery, sizeof(RankQuery), "SELECT *, (wins / (loses + wins)) as wlr FROM rome ORDER BY wins DESC LIMIT 10");
        ddb.Query(SQL_TopCallback, RankQuery, GetClientUserId(client));
      }
    }
  }
}

void ShowAnthemMenu (int client) {
  if(!IsValidClient(client)) return;

  Menu anthem_menu = new Menu(AnthemMenuHandler);

  char name[1024];
  if(StrEqual(AnthemSelectedName[client], ""))	Format(name, sizeof(name), "無音樂", client);
  else Format(name, sizeof(name), AnthemSelectedName[client]);

  char mvpmenutitle[1024];
  Format(mvpmenutitle, sizeof(mvpmenutitle), "選擇勝利音樂\n目前選擇: %s", name);
  anthem_menu.SetTitle(mvpmenutitle);

  anthem_menu.AddItem("", "無");

  for(int i = 1; i < AnthemCount; i++)
  {
    anthem_menu.AddItem(AnthemName[i], AnthemName[i]);
  }

  anthem_menu.ExitBackButton = true;
  anthem_menu.Display(client, MENU_TIME_FOREVER);
}

public int AnthemMenuHandler(Menu menu, MenuAction action, int client,int param)
{
  if(action == MenuAction_Select)
  {
    char name[1024];
    GetMenuItem(menu, param, name, sizeof(name));

    if(StrEqual(name, ""))
    {
      CPrintToChat(client, "{GREEN}[ROME] {NORMAL}取消勝利音樂", client);
      AnthemSelected[client] = 0;
    }
    else
    {
      CPrintToChat(client, "{GREEN}[ROME] {NORMAL}選擇勝利音樂為: {LIGHTGREEN}%s", name);
      AnthemSelected[client] = FindAnthemIDByName(name);
    }

    strcopy(AnthemSelectedName[client], sizeof(AnthemSelectedName[]), name);
    SetClientCookie(client, Anthemcookie, name);
  }
  else if (action == MenuAction_Cancel && param == MenuCancel_ExitBack ) {
    ShowMainMenu(client);
  }
}

void ShowAnthemVolMenu (int client) {
  if(!IsValidClient(client)) return;

  Menu vol_menu = new Menu(VolMenuHandler);

  char vol[1024];
  if(AnthemVol[client] > 0.00)	Format(vol, sizeof(vol), "%.2f", AnthemVol[client]);
  else Format(vol, sizeof(vol), "靜音");

  char menutitle[1024];
  Format(menutitle, sizeof(menutitle), "勝利音樂音量\n目前音量: %s", vol);
  vol_menu.SetTitle(menutitle);

  vol_menu.AddItem("0", "靜音");
  vol_menu.AddItem("0.2", "20%");
  vol_menu.AddItem("0.4", "40%");
  vol_menu.AddItem("0.6", "60%");
  vol_menu.AddItem("0.8", "80%");
  vol_menu.AddItem("1.0", "100%");
  vol_menu.ExitBackButton = true;
  vol_menu.Display(client, MENU_TIME_FOREVER);
}

public int VolMenuHandler(Menu menu, MenuAction action, int client,int param)
{
  if(action == MenuAction_Select)
  {
    char vol[1024];
    GetMenuItem(menu, param, vol, sizeof(vol));

    AnthemVol[client] = StringToFloat(vol);
    CPrintToChat(client, "{GREEN}[ROME] {NORMAL}勝利音樂音量已設定為: %.2f", AnthemVol[client]);

    SetClientCookie(client, Anthemcookie2, vol);
  }
  else if (action == MenuAction_Cancel && param == MenuCancel_ExitBack ) {
    ShowMainMenu(client);
  }
}

public void SQL_StatsCallback(Database db, DBResultSet results, const char[] error, any data)
{
  if (db == null || strlen(error) > 0)
  {
    SetFailState("(SQL_StatsCallback) Fail at Query: %s", error);
    return;
  }

  int client = GetClientOfUserId(data);
  int i;
  char Auth_receive[32];
  float win;

  iTotalPlayers = SQL_GetRowCount(results);

  char sCommunityID[32];
  SteamWorks_GetClientSteamID(client, sCommunityID, sizeof(sCommunityID));
  if(StrEqual("STEAM_ID_STOP_IGNORING_RETVALS", sCommunityID))
  {
    LogError("Auth failed for client index %d", client);
    return;
  }

  // get player's rank
  while(results.HasResults && results.FetchRow())
  {
    i++;
    results.FetchString(1, Auth_receive, sizeof(Auth_receive));

    if(StrEqual(Auth_receive, sCommunityID))  {
      win = results.FetchFloat(9);
      break;
    }
  }

  // Create Menu
  char temp[255];
  char text[512];

  Menu statsmenu = new Menu(StatsMenu_Handler);
  SetMenuPagination(statsmenu, 3);

  char title[64];
  Format(title, sizeof(title), "%N 的統計資料", client);
  statsmenu.SetTitle(title);

  Format(temp, sizeof(temp), "基本資料\n");
  StrCat(text, sizeof(text), temp);
  Format(temp, sizeof(temp), "勝場:%d\n敗場:%d\n勝率:%.2f%\n排名:%d/%d", Stats[client].WINS, Stats[client].LOSES, win, i, iTotalPlayers);
  StrCat(text, sizeof(text), temp);
  statsmenu.AddItem("", text);
  text="";

  Format(temp, sizeof(temp), "部位資料\n");
  StrCat(text, sizeof(text), temp);
  Format(temp, sizeof(temp), "零分區:%d\n一分區:%d\n兩分區:%d\n三分區:%d", Stats[client].POINTS0, Stats[client].POINTS1, Stats[client].POINTS2, Stats[client].POINTS3);
  StrCat(text, sizeof(text), temp);
  statsmenu.AddItem("", text);
  text="";

  statsmenu.ExitBackButton = true;
  statsmenu.Display(client, MENU_TIME_FOREVER);
}

public int StatsMenu_Handler(Menu menu, MenuAction action, int client,int param)
{
  if (action == MenuAction_Cancel && param == MenuCancel_ExitBack ) {
    ShowMainMenu(client);
  }
}

public void SQL_TopCallback(Database db, DBResultSet results, const char[] error, any data)
{
  if (db == null || strlen(error) > 0)
  {
    SetFailState("(SQL_TopDropballCallback) Fail at Query: %s", error);
    return;
  }
  
  int i;
  int client = GetClientOfUserId(data);
  char name[255], temp[255], text[512];
  
  Menu TopMenu = new Menu(TopMenu_MenuHandler);
  TopMenu.SetTitle("");
  
  Format(temp, sizeof(temp), "勝率排行榜 \n \n", client);
  StrCat(text, sizeof(text), temp);
  
  while(results.HasResults && results.FetchRow())
  {
    i++;
    results.FetchString(2, name, sizeof(name));

    Format(temp, sizeof(temp), "#%d. %s - %d勝 %d敗 (%f%)\n", i, name, results.FetchInt(3), results.FetchInt(4), results.FetchFloat(9));
    StrCat(text, sizeof(text), temp);
  }
  
  TopMenu.AddItem("", text);
  TopMenu.ExitBackButton = true;
  TopMenu.DisplayAt(client, 0, MENU_TIME_FOREVER);
}

public int TopMenu_MenuHandler(Menu menu, MenuAction action, int client,int param)
{	
  if (action == MenuAction_Cancel && param == MenuCancel_ExitBack ) {
    ShowMainMenu(client);
  }
}

public void OnSQLConnect(Handle owner, Handle hndl, const char[] error, any data)
{
  if (hndl == null)
  {
    SetFailState("(OnSQLConnect) Can't connect to mysql");
    return;
  }

  if (ddb != null)
  {
    delete hndl;
    return;
  }

  ddb = view_as<Database>(CloneHandle(hndl));

  CreateTable();
}

void CreateTable()
{
  char sQuery[1024];
  Format(sQuery, sizeof(sQuery),
  "CREATE TABLE IF NOT EXISTS `rome`  \
  ( id INT NOT NULL AUTO_INCREMENT ,  \
  steamid VARCHAR(32) NOT NULL ,  \
  name VARCHAR(64) NOT NULL ,  \
  wins INT NOT NULL ,  \
  loses INT NOT NULL ,  \
  points0 INT NOT NULL ,  \
  points1 INT NOT NULL ,  \
  points2 INT NOT NULL ,  \
  points3 INT NOT NULL ,  \
  PRIMARY KEY (id))  \
  ENGINE = InnoDB;");

  ddb.Query(SQL_CreateTable, sQuery);
}

public void SQL_CreateTable(Database db, DBResultSet results, const char[] error, any data)
{
  if (db == null || strlen(error) > 0)
  {
    SetFailState("(SQL_CreateTable) Fail at Query: %s", error);
    return;
  }
  delete results;

  for (int i = 1; i <= MaxClients; i++)
  {
    if (IsValidClient(i) && !IsFakeClient(i))
    {
      LoadClientStats(i);
    }
  }
}

void LoadClientStats(int client)
{
  if (!IsValidClient(client) || IsFakeClient(client))
    return;

  char sCommunityID[32];
  SteamWorks_GetClientSteamID(client, sCommunityID, sizeof(sCommunityID));
  if(StrEqual("STEAM_ID_STOP_IGNORING_RETVALS", sCommunityID))
  {
    LogError("Auth failed for client index %d", client);
    return;
  }

  char LoadQuery[512];
  Format(LoadQuery, sizeof(LoadQuery), "SELECT * FROM `rome` WHERE steamid = '%s'", sCommunityID);

  ddb.Query(SQL_LoadClientStats, LoadQuery, GetClientUserId(client));
}

public void SQL_LoadClientStats(Database db, DBResultSet results, const char[] error, any data)
{
  int client = GetClientOfUserId(data);

  if (!IsValidClient(client) || IsFakeClient(client))
    return;

  if (db == null || strlen(error) > 0)
  {
    SetFailState("(SQL_LoadClientStats) Fail at Query: %s", error);
    return;
  }
  else
  {
    // New player
    if(!results.HasResults || !results.FetchRow())
    {
      char sCommunityID[32];
      SteamWorks_GetClientSteamID(client, sCommunityID, sizeof(sCommunityID));
      if(StrEqual("STEAM_ID_STOP_IGNORING_RETVALS", sCommunityID))
      {
        LogError("Auth failed for client index %d", client);
        return;
      }

      char InsertQuery[512];
      Format(InsertQuery, sizeof(InsertQuery), "INSERT INTO `rome` VALUES(NULL,'%s','%N','0','0','0','0','0','0');", sCommunityID, client);
      ddb.Query(SQL_InsertCallback, InsertQuery, GetClientUserId(client));
    }

    else
    {
      Stats[client].WINS = results.FetchInt(3);
      Stats[client].LOSES = results.FetchInt(4);
      Stats[client].POINTS0 = results.FetchInt(5);
      Stats[client].POINTS1 = results.FetchInt(6);
      Stats[client].POINTS2 = results.FetchInt(7);
      Stats[client].POINTS3 = results.FetchInt(8);
    }
  }
}

public void SQL_InsertCallback(Database db, DBResultSet results, const char[] error, any data)
{
  if (db == null || strlen(error) > 0)
  {
    SetFailState("SQL_InsertCallback) Fail at Query: %s", error);
    return;
  }
}

void SaveClientStats(int client)
{
  if (!IsValidClient(client) || IsFakeClient(client))
    return;

  char sCommunityID[32];
  SteamWorks_GetClientSteamID(client, sCommunityID, sizeof(sCommunityID));
  if(StrEqual("STEAM_ID_STOP_IGNORING_RETVALS", sCommunityID))
  {
    LogError("Auth failed for client index %d", client);
    return;
  }

  char SaveQuery[512];
  Format(SaveQuery, sizeof(SaveQuery),
  "UPDATE `rome` SET name = '%N', wins = '%i', loses = '%i', points0='%i', points1='%i', points2='%i', points3='%i' WHERE steamid = '%s';",
  client,
  Stats[client].WINS,
  Stats[client].LOSES,
  Stats[client].POINTS0,
  Stats[client].POINTS1,
  Stats[client].POINTS2,
  Stats[client].POINTS3,
  sCommunityID);

  ddb.Query(SQL_SaveCallback, SaveQuery, GetClientUserId(client))
}

public void SQL_SaveCallback(Database db, DBResultSet results, const char[] error, any data)
{
  if (db == null || strlen(error) > 0)
  {
    SetFailState("(SQL_SaveClientStats) Fail at Query: %s", error);
    return;
  }
}

public void OnPluginEnd()
{
  for (int i = 1; i <= MaxClients; i++)
  {
    if (IsValidClient(i) && !IsFakeClient(i))
    {
      SaveClientStats(i);
    }
  }
}

void TE_SetupBSPDecal(const float vecOrigin[3], int index) {
  TE_Start("World Decal");
  TE_WriteVector("m_vecOrigin", vecOrigin);
  TE_WriteNum("m_nIndex", index);
}
