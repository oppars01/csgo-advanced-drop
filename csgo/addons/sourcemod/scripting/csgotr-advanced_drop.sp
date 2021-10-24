#include <sourcemod>
#include <SteamWorks>
#include <ripext>
#include <sdktools>
#include <dhooks>
#include <discord>

#pragma semicolon 1

public Plugin myinfo = 
{
	name = "Advanced Drop", 
	author = "oppa & (DropsSummoner: Phoenix)", 
	description = "Attempts to drop drops for the duration of the map. It sends the falling drops to the discord server in an advanced way.", 
	version = "1.0", 
	url = "csgo-turkiye.com"
};

char s_drop_items[ PLATFORM_MAX_PATH ],s_log_file[ PLATFORM_MAX_PATH ], s_tag_plugin[ 64 ], s_webhook_URL[ 256 ];
ConVar g_webhook = null, g_tag = null, g_price = null, g_wait_timer = null, g_chat_info = null, g_play_sound_status = null;
Handle h_match_end_drops = null, h_wait_timer = null;
int i_OS = -1;
Address a_drop_for_all_players_patch = Address_Null;
KeyValues kv;

public void OnPluginStart()
{   
    g_webhook = CreateConVar( "sm_webhook_advanced_drop", "https://discord.com/api/webhooks/xxxxx/xxxxxxx", "Advanced Drop Webhook URL" );
    g_tag = CreateConVar( "sm_tag_advanced_drop", "[ csgo-turkiye.com Advanced Drop ]", "Advanced Drop Plugin Tag" );
    g_price = CreateConVar( "sm_price_advanced_drop", "1", "Advanced Drop Item Price" );
    g_wait_timer = CreateConVar("sm_wait_timer_advanced_drop", "182", "How many seconds should a drop attempt be made? (Do not do less than 3 minutes, ideal is 10 minutes)", _, true, 60.0);
    g_chat_info = CreateConVar("sm_chat_info_advanced_drop", "1", "Show drop attempts in chat?", _, true, 0.0, true, 1.0);
    g_play_sound_status = CreateConVar("sm_sound_status_advanced_drop", "2", "Play a sound when the drop drops? [0 - no | 1 - just drop it | 2 - to everyone]", _, true, 0.0, true, 2.0);
    AutoExecConfig(true, "advanced_drop","CSGO_Turkiye");
    RegAdminCmd("sm_updatedropitems", CommandDropItemUpdate, ADMFLAG_ROOT);
    GameData h_game_data = LoadGameConfigFile("advanced_drop.games");
    if (!h_game_data)
	{
		SetFailState("Failed to load drop game data.");
		return;
	}
    i_OS = h_game_data.GetOffset("OS");
    if(i_OS == -1)
    {
        SetFailState("Failed to get OS offset.");
        return;
    }
    if(i_OS == 1)
    {
        StartPrepSDKCall(SDKCall_Raw);
    }else
	{
		StartPrepSDKCall(SDKCall_Static);
	}
    PrepSDKCall_SetFromConf(h_game_data, SDKConf_Signature, "CCSGameRules::RewardMatchEndDrops");
    PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
    if (!(h_match_end_drops = EndPrepSDKCall()))
    {
		SetFailState("Failed to create SDKCall for CCSGameRules::RewardMatchEndDrops");
		return;
	}
    DynamicDetour dd_record_player_item_drop = DynamicDetour.FromConf(h_game_data, "CCSGameRules::RecordPlayerItemDrop");
    if (!dd_record_player_item_drop)
	{
		SetFailState("Could not set service path for CCSGameRules::RecordPlayerItemDrop");	
		return;
	}
    if(!dd_record_player_item_drop.Enable(Hook_Post, Detour_RecordPlayerItemDrop))
	{
		SetFailState("Deviation for CCSGameRules::RecordPlayerItemDrop failed.");
		return;
	}
    a_drop_for_all_players_patch = h_game_data.GetAddress("DropForAllPlayersPatch");
    if(a_drop_for_all_players_patch != Address_Null)
	{
		if((LoadFromAddress(a_drop_for_all_players_patch, NumberType_Int32) & 0xFFFFFF) == 0x1F883)
		{
			a_drop_for_all_players_patch += view_as<Address>(2);
			StoreToAddress(a_drop_for_all_players_patch, 0xFF, NumberType_Int8);
		}else
		{
			a_drop_for_all_players_patch = Address_Null;
			LogError(" Not as we expected at DropForAllPlayersPatch, drop will not be available for all players.");
		}
	}
	else
	{
		LogError("Failed to get DropForAllPlayersPatch address, drop will not be available for all players.");
	}
    delete h_game_data;
    BuildPath(Path_SM, s_log_file, sizeof( s_log_file ), "logs/advanced_drop.log");
}

public void OnPluginEnd()
{
	if(a_drop_for_all_players_patch != Address_Null)StoreToAddress(a_drop_for_all_players_patch, 0x01, NumberType_Int8);
	
}

public void OnMapStart()
{
    GetConVarString(g_webhook, s_webhook_URL, sizeof(s_webhook_URL));
    GetConVarString(g_tag, s_tag_plugin, sizeof(s_tag_plugin));
    if(!DirExists("addons/sourcemod/configs/CSGO-Turkiye_com"))CreateDirectory("/addons/sourcemod/configs/CSGO-Turkiye_com", 511);
    BuildPath( Path_SM, s_drop_items, sizeof( s_drop_items ), "configs/CSGO-Turkiye_com/dropitems.cfg" );
    if (kv != null)kv.Close();
    kv = CreateKeyValues( "DropItems" );
    FileToKeyValues( kv, s_drop_items );
    UpdateDropItemList(0);
    PrecacheSound("ui/panorama/case_awarded_1_uncommon_01.wav");
    CreateTimer(g_wait_timer.FloatValue, TryDropping, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
    char s_map_name[256],s_hostname[256],s_content[512];
    GetConVarString(FindConVar("hostname"), s_hostname,sizeof(s_hostname));
    GetCurrentMap(s_map_name, sizeof(s_map_name));
    Format(s_content,sizeof(s_content),"**%s** Drop Active.\n> **Hostname >>** `%s`\n> **Map Name >>** `%s`", s_tag_plugin,s_hostname, s_map_name);
    DiscordWebHook dw_hook = new DiscordWebHook(s_webhook_URL);
    dw_hook.SetContent(s_content);
    dw_hook.Send();
    delete dw_hook;
}

public Action CommandDropItemUpdate(int client, int args)
{
    SentDropWebhook(client, "deneme","https://panel.oyunhost.net/themes/pterodactyl/images/logo.png", "31313131", "31");
    UpdateDropItemList(client);
    return Plugin_Handled;
}

MRESReturn Detour_RecordPlayerItemDrop(DHookParam hParams)
{
	if(h_wait_timer)
	{
		delete h_wait_timer;
	}
	int i_account_ID = hParams.GetObjectVar(1, 16, ObjectValueType_Int);
	int client = GetClientFromAccountID(i_account_ID);
	if(client != -1)
	{	
        int i_def_index = hParams.GetObjectVar(1, 20, ObjectValueType_Int);
        int i_paint_index = hParams.GetObjectVar(1, 24, ObjectValueType_Int);
        int i_rarity = hParams.GetObjectVar(1, 28, ObjectValueType_Int);
        int i_quality = hParams.GetObjectVar(1, 32, ObjectValueType_Int);
        char s_item_name[256], s_image_url[256], s_drop_info[16], s_def_index[8];
        Format(s_drop_info, sizeof(s_drop_info), "[%u-%u-%u-%u]", i_def_index, i_paint_index, i_rarity, i_quality);
        KvRewind(kv);
        IntToString(i_def_index, s_def_index, sizeof(s_def_index));
        if (!kv.JumpToKey(s_def_index))
        {
            KvRewind(kv);
            if(KvJumpToKey(kv, "UNKNOW"))
            {
                KvGetString(kv, "item_name", s_item_name, sizeof(s_item_name), "NOT FOUND INFORMATION ABOUT DROP ITEM");
                KvGetString(kv, "image_url", s_image_url, sizeof(s_image_url), "https://csgo-turkiye.com/api/images/unknow_case.png");
            }else{
                Format(s_item_name,sizeof(s_item_name),"NOT FOUND INFORMATION ABOUT DROP ITEM");
                Format(s_image_url,sizeof(s_image_url),"https://csgo-turkiye.com/api/images/unknow_case.png");
            }
            SentDropWebhook(client,s_item_name,s_image_url,s_drop_info);
        }else{
            KvGetString(kv, "item_name", s_item_name, sizeof(s_item_name), "NOT FOUND INFORMATION ABOUT DROP ITEM");
            KvGetString(kv, "image_url", s_image_url, sizeof(s_image_url), "https://csgo-turkiye.com/api/images/unknow_case.png");
            ArrayList DataArray = new ArrayList(ByteCountToCells(1024));
            DataArray.Push(client);
            DataArray.PushString(s_item_name);
            DataArray.PushString(s_image_url);
            DataArray.PushString(s_drop_info);
            char s_price_url[256];
            UrlEncodeString(s_item_name, sizeof(s_item_name), s_item_name);
            Format(s_price_url,sizeof(s_price_url),"market/priceoverview/?appid=730&currency=%d&market_hash_name=%s",g_price.IntValue,s_item_name);
            HTTPClient hc_request = new HTTPClient("https://steamcommunity.com");
            hc_request.Get(s_price_url, DropPrice ,DataArray);
        }
        Protobuf p_send_player_item_found = view_as<Protobuf>(StartMessageAll("SendPlayerItemFound", USERMSG_RELIABLE));
        p_send_player_item_found.SetInt("entindex", client);
        Protobuf hIteminfo = p_send_player_item_found.ReadMessage("iteminfo");
        hIteminfo.SetInt("defindex", i_def_index);
        hIteminfo.SetInt("paintindex", i_paint_index);
        hIteminfo.SetInt("rarity", i_rarity);
        hIteminfo.SetInt("quality", i_quality);
        hIteminfo.SetInt("inventory", 6); 
        EndMessage();
        SetHudTextParams(-1.0, 0.4, 3.0, GetRandomInt(0,255), GetRandomInt(0,255), GetRandomInt(0,255), 255);
        ShowHudText(client, -1, "[ %s ] You dropped a drop! check your inventory.",s_tag_plugin);
        if(g_play_sound_status.IntValue == 2)
		{
			EmitSoundToAll("ui/panorama/case_awarded_1_uncommon_01.wav", SOUND_FROM_LOCAL_PLAYER, _, SNDLEVEL_NONE);
		}
		else if(g_play_sound_status.IntValue == 1)
		{
			EmitSoundToClient(client, "ui/panorama/case_awarded_1_uncommon_01.wav", SOUND_FROM_LOCAL_PLAYER, _, SNDLEVEL_NONE);
		}
	}
	return MRES_Ignored;
}

void UpdateDropItemList(int client)
{
    HTTPClient hc_request = new HTTPClient("https://csgo-turkiye.com");
    hc_request.Get("api/csgo-items?format=json",UpdateDropItems ,client);
}

void UpdateDropItems(HTTPResponse response, int client)
{
    if (response.Status != HTTPStatus_OK) {
        if(client==0){
            PrintToServer("%s Failed to Update Drop Items",s_tag_plugin);
        }else{
            if (IsClientConnected(client) && IsValidClient(client) && !IsFakeClient(client))
            {
                PrintToChat(client," \x10%s \x02Failed to Update Drop Items",s_tag_plugin);
            }
        }
        return;
    }

    if (response.Data == null) {
        if(client==0){
            PrintToServer("%s Invalid Drop Items",s_tag_plugin);
        }else{
            if (IsClientConnected(client) && IsValidClient(client) && !IsFakeClient(client))
            {
                PrintToChat(client," \x10%s \x02Invalid Drop Items",s_tag_plugin);
            }
        }
        return;
    }
    JSONArray ja_datas = view_as<JSONArray>(response.Data);
    JSONObject jo_data;
    char s_def_index[8];
    for (int i = 0; i < ja_datas.Length; i++) {
        jo_data = view_as<JSONObject>(ja_datas.Get(i));
        jo_data.GetString("defindex", s_def_index, sizeof(s_def_index));
        KvRewind(kv);
        if (!kv.JumpToKey(s_def_index))
        {
            char s_item_name[256], s_image_url[256];
            jo_data.GetString("item_name", s_item_name, sizeof(s_item_name));
            jo_data.GetString("image_url", s_image_url, sizeof(s_image_url));
            KvJumpToKey( kv, s_def_index, true );
            KvSetString(kv, "item_name", s_item_name);
            KvSetString(kv, "image_url", s_image_url);
            KvRewind( kv );
            KeyValuesToFile( kv, s_drop_items );
            PrintToServer("%s Add Drop New Item >> [%s] %s",s_tag_plugin,s_def_index,s_item_name);
        }
        delete jo_data;
    }
    if(client==0){
        PrintToServer("%s Drop Items Updated",s_tag_plugin);
    }else{
        if (IsClientConnected(client) && IsValidClient(client) && !IsFakeClient(client))
        {
                PrintToChat(client," \x10%s \x04Drop Items Updated",s_tag_plugin);
        }
    }
}

void DropPrice(HTTPResponse response, ArrayList DataArray)
{
    char s_item_price[32], s_item_name[256], s_image_url[256], s_drop_info[16];
    DataArray.GetString(1, s_item_name,sizeof(s_item_name));
    DataArray.GetString(2, s_image_url,sizeof(s_image_url));
    DataArray.GetString(3, s_drop_info,sizeof(s_drop_info));
    if (response.Status != HTTPStatus_OK || response.Data == null) {
        PrintToServer("%s Failed to Drop Price",s_tag_plugin);
    }else{
        JSONObject data = view_as<JSONObject>(response.Data);
        data.GetString("median_price", s_item_price, sizeof(s_item_price));
        delete data;
    }
    if (StrEqual(s_item_price, ""))Format(s_item_price,sizeof(s_item_price),"-");
    SentDropWebhook(DataArray.Get(0),s_item_name,s_image_url,s_drop_info,s_item_price);
} 

void SentDropWebhook(int client, char[] item_name,char[] image_url, char[] drop_info, char[] item_price = "-"){
    if (IsClientConnected(client) && IsValidClient(client) && !IsFakeClient(client))
    {
        char s_hex_char[]="0123456789ABCDEF\0",s_color[8],s_footer[64],s_steam_id[32],s_username[(MAX_NAME_LENGTH + 1) * 2],s_steam_URL[256],s_hostname[256],s_price_url[256];
        if (!StrEqual(item_price, "-")){
            UrlEncodeString(s_price_url, sizeof(s_price_url), item_name);
            ReplaceString(s_price_url, sizeof(s_price_url), "+", "%20");
            Format(s_price_url, sizeof(s_price_url),"[%s](https://steamcommunity.com/market/listings/730/%s)",item_price,s_price_url);
        }else{
            Format(s_price_url, sizeof(s_price_url),"-");
        }
        GetConVarString(FindConVar("hostname"), s_hostname,sizeof(s_hostname));
        GetClientName(client, s_username, sizeof(s_username));
        if (!GetClientAuthId(client, AuthId_Steam2, s_steam_id, sizeof(s_steam_id)))Format(s_steam_id, sizeof(s_steam_id), "Bilinmeyen STEAM ID");
        GetClientAuthId(client, AuthId_SteamID64, s_steam_URL, sizeof(s_steam_URL));	
        Format(s_steam_URL, sizeof(s_steam_URL), "[%s](http://steamcommunity.com/profiles/%s)", s_steam_id,s_steam_URL);
        Format(s_color, sizeof(s_color), "#%c%c%c%c%c%c",s_hex_char[GetRandomInt(0,15)],s_hex_char[GetRandomInt(0,15)],s_hex_char[GetRandomInt(0,15)],s_hex_char[GetRandomInt(0,15)],s_hex_char[GetRandomInt(0,15)],s_hex_char[GetRandomInt(0,15)]);
        FormatTime(s_footer, sizeof(s_footer), "%d.%m.%Y %X", GetTime());
        Format(s_footer, sizeof(s_footer), "%s • %s", s_tag_plugin,s_footer);
        DiscordWebHook dw_hook = new DiscordWebHook(s_webhook_URL);
        dw_hook.SlackMode = true;
        MessageEmbed me_embed = new MessageEmbed();
        me_embed.SetColor(s_color);
        me_embed.SetThumb(image_url);
        me_embed.SetTitle("A Player Dropped");
        me_embed.AddField("Hostname", s_hostname,false);
        me_embed.AddField("Username", s_username,true);
        me_embed.AddField("Steam ID", s_steam_URL,true);
        me_embed.AddField("Drop Info [Def Index - Paint Index - Rarity - Quality]", drop_info,false);
        me_embed.AddField("Item", item_name,false);
        me_embed.AddField("Price", s_price_url,false);
        me_embed.SetFooter(s_footer);
        dw_hook.Embed(me_embed);
        dw_hook.Send();
        delete dw_hook;
        LogToFile(s_log_file, "%L dropped this: %s %s | Price: %s", client, drop_info,item_name, item_price);
        PrintToChatAll(" \x10%s \x04Player \x0C%N \x04dropped this: \x0B%s \x0C %s \x04| Price: \x0E%s",s_tag_plugin, client, drop_info, item_name,item_price);
    }
}

void UrlEncodeString(char[] output, int size, const char[] input)
{
	int i_icnt = 0;
	int i_ocnt = 0;
	for(;;)
	{
		if (i_ocnt == size)
		{
			output[i_ocnt-1] = '\0';
			return;
		}
		int c = input[i_icnt];
		if (c == '\0')
		{
			output[i_ocnt] = '\0';
			return;
		}
		// Use '+' instead of '%20'.
		// Still follows spec and takes up less of our limited buffer.
		if (c == ' ')
		{
			output[i_ocnt++] = '+';
		}
		else if ((c < '0' && c != '-' && c != '.') ||
			(c < 'A' && c > '9') ||
			(c > 'Z' && c < 'a' && c != '_') ||
			(c > 'z' && c != '~')) 
		{
			output[i_ocnt++] = '%';
			Format(output[i_ocnt], size-strlen(output[i_ocnt]), "%x", c);
			i_ocnt += 2;
		}
		else
		{
			output[i_ocnt++] = c;
		}
		i_icnt++;
	}
}

int GetClientFromAccountID(int accound_ID)
{
	for(int i = 1; i <= MaxClients; i++)if(IsClientConnected(i) && !IsFakeClient(i) && IsClientAuthorized(i))if(GetSteamAccountID(i) == accound_ID)return i;
	return -1;
}

Action TryDropping(Handle hTimer)
{
	if(g_chat_info.BoolValue)
	{
		h_wait_timer = CreateTimer(1.2, DropFailed);
		
		PrintToChatAll(" \x10%s \x0CTrying Drop...", s_tag_plugin);
	}
	if(i_OS == 1)
	{
		SDKCall(h_match_end_drops, 0xDEADC0DE, false);
	}
	else
	{
		SDKCall(h_match_end_drops, false);
	}
	return Plugin_Continue;
}

Action DropFailed(Handle hTimer)
{
	h_wait_timer = null;
	PrintToChatAll(" \x10%s \x02Drop Attempt Failed :(", s_tag_plugin);
}

stock bool IsValidClient(int client)
{
	if(client > 0 && client <= MaxClients)
	{
		if(IsClientInGame(client))
			return true;
	}
	return false;
}

/*                                                     __                __   .__                                                        
               ____   ______ ____   ____           _/  |_ __ _________|  | _|__|___.__. ____       ____  ____   _____                  
             _/ ___\ /  ___// ___\ /  _ \   ______ \   __\  |  \_  __ \  |/ /  <   |  |/ __ \    _/ ___\/  _ \ /     \                 
             \  \___ \___ \/ /_/  >  <_> ) /_____/  |  | |  |  /|  | \/    <|  |\___  \  ___/    \  \__(  <_> )  Y Y  \                
              \___  >____  >___  / \____/           |__| |____/ |__|  |__|_ \__|/ ____|\___  > /\ \___  >____/|__|_|  /                
                  \/     \/_____/                                          \/   \/         \/  \/     \/            \/                 
________________________________              _____       .___                                     .___ ________                       
\______   \__    ___/\_   _____/             /  _  \    __| _/__  _______    ____   ____  ____   __| _/ \______ \_______  ____ ______  
 |       _/ |    |    |    __)_    ______   /  /_\  \  / __ |\  \/ /\__  \  /    \_/ ___\/ __ \ / __ |   |    |  \_  __ \/  _ \\____ \ 
 |    |   \ |    |    |        \  /_____/  /    |    \/ /_/ | \   /  / __ \|   |  \  \__\  ___// /_/ |   |    `   \  | \(  <_> )  |_> >
 |____|_  / |____|   /_______  /           \____|__  /\____ |  \_/  (____  /___|  /\___  >___  >____ |  /_______  /__|   \____/|   __/ 
        \/                   \/                    \/      \/            \/     \/     \/    \/     \/          \/             |__|    

*/