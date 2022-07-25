#include <sourcemod>
#include <multicolors>
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
	version = "1.3", 
	url = "csgo-turkiye.com"
};

char s_drop_items[ PLATFORM_MAX_PATH ],s_log_file[ PLATFORM_MAX_PATH ], s_tag_plugin[ 64 ], s_webhook_URL[ 256 ], s_language[ 8 ], s_prime_api_key[ 32 ];
ConVar g_webhook = null, g_tag = null, g_price = null, g_wait_timer = null, g_chat_info = null, g_play_sound_status = null, g_active_info = null, g_language = null, g_prime_api_key = null;
Handle h_match_end_drops = null, h_wait_timer = null;
int i_OS = -1, i_price, i_play_sound_status;
float f_wait_timer;
bool b_chat_info, b_active_info, b_client_prime_status [ MAXPLAYERS+1 ] = {false , ...};
Address a_drop_for_all_players_patch = Address_Null;

public void OnPluginStart()
{   
    LoadTranslations("advanced-drop.phrases.txt");
    CVAR_Load();
    RegAdminCmd("sm_updatedropitems", CommandDropItemUpdate, ADMFLAG_ROOT);
    RegAdminCmd("sm_updatedropallitems", CommandDropAllItemUpdate, ADMFLAG_ROOT);
    GameData h_game_data = LoadGameConfigFile("advanced_drop.games");
    if (!h_game_data)
	{
		SetFailState("%t", "GameData Error", s_tag_plugin);
		return;
	}
    i_OS = h_game_data.GetOffset("OS");
    if(i_OS == -1)
    {
        SetFailState("%t", "OS Error", s_tag_plugin);
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
        SetFailState("%t", "RewardMatchEndDrops Error", s_tag_plugin);
        return;
	}
    DynamicDetour dd_record_player_item_drop = DynamicDetour.FromConf(h_game_data, "CCSGameRules::RecordPlayerItemDrop");
    if (!dd_record_player_item_drop)
	{
        SetFailState("%t", "RecordPlayerItemDrop Error", s_tag_plugin);
        return;
	}
    if(!dd_record_player_item_drop.Enable(Hook_Post, Detour_RecordPlayerItemDrop))
	{
        SetFailState("%t", "RecordPlayerItemDrop Error 2", s_tag_plugin);
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
			LogError("%t", "DropForAllPlayersPatch Error", s_tag_plugin);
		}
	}
	else
	{
        LogError("%t", "DropForAllPlayersPatch Error 2", s_tag_plugin);
	}
    delete h_game_data;
    BuildPath(Path_SM, s_log_file, sizeof( s_log_file ), "logs/advanced_drop.log");
    for (int i = 1; i <= MaxClients; i++)if (IsValidClient(i)) ClientPrimeStatus(i);
}

public void OnPluginEnd()
{
	if(a_drop_for_all_players_patch != Address_Null)StoreToAddress(a_drop_for_all_players_patch, 0x01, NumberType_Int8);	
}

public void OnMapStart()
{
    CVAR_Load();
    if(!DirExists("addons/sourcemod/configs/CSGO-Turkiye_com"))CreateDirectory("/addons/sourcemod/configs/AdvancedDrop", 511);
    BuildPath( Path_SM, s_drop_items, sizeof( s_drop_items ), "configs/AdvancedDrop/dropitems.cfg" );
    UpdateDropItemList(0);
    PrecacheSound("ui/panorama/case_awarded_1_uncommon_01.wav");
    CreateTimer(f_wait_timer, TryDropping, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
    
}

public void OnConfigsExecuted(){
    if(b_active_info)
	{
        char s_map_name[256],s_hostname[256],s_content[512];
        GetConVarString(FindConVar("hostname"), s_hostname,sizeof(s_hostname));
        GetCurrentMap(s_map_name, sizeof(s_map_name));
        Format(s_content,sizeof(s_content),"%t","Drop Active", s_tag_plugin,s_hostname, s_map_name);
        DiscordWebHook dw_hook = new DiscordWebHook(s_webhook_URL);
        dw_hook.SetContent(s_content);
        dw_hook.Send();
        delete dw_hook;
    }
}


public void OnClientPostAdminCheck(int client)
{
	ClientPrimeStatus(client);
}

void CVAR_Load(){
    g_webhook = CreateConVar( "sm_webhook_advanced_drop", "https://discord.com/api/webhooks/xxxxx/xxxxxxx", "Advanced Drop Webhook URL" );
    g_tag = CreateConVar( "sm_tag_advanced_drop", "[ Advanced Drop ]", "Advanced Drop Plugin Tag" );
    g_price = CreateConVar( "sm_price_advanced_drop", "1", "Advanced Drop Item Currency" );
    g_language = CreateConVar( "sm_language_advanced_drop", "en", "Advanced Drop Item Name Language" );
    g_active_info = CreateConVar("sm_active_info_advanced_drop", "1", "Every time the map changes, send the drop active information to the discord server?", _, true, 0.0, true, 1.0);
    g_wait_timer = CreateConVar("sm_wait_timer_advanced_drop", "182", "How many seconds should a drop attempt be made? (Do not do less than 3 minutes, ideal is 10 minutes)", _, true, 60.0);
    g_chat_info = CreateConVar("sm_chat_info_advanced_drop", "1", "Show drop attempts in chat?", _, true, 0.0, true, 1.0);
    g_play_sound_status = CreateConVar("sm_sound_status_advanced_drop", "2", "Play a sound when the drop drops? [0 - no | 1 - just drop it | 2 - to everyone]", _, true, 0.0, true, 2.0);
    g_prime_api_key = CreateConVar( "sm_prime_api_key_advanced_drop", "XXXXX-XXXXX-XXXXX-XXXXX", "prime.napas.cc - Web API authentication key." );
    AutoExecConfig(true, "advanced_drop");
    GetConVarString(g_webhook, s_webhook_URL, sizeof(s_webhook_URL));
    GetConVarString(g_tag, s_tag_plugin, sizeof(s_tag_plugin));
    GetConVarString(g_language, s_language, sizeof(s_language));
    i_price = GetConVarInt(g_price);
    f_wait_timer = GetConVarFloat(g_wait_timer);
    i_play_sound_status = GetConVarInt(g_play_sound_status);
    b_chat_info = GetConVarBool(g_chat_info);
    b_active_info = GetConVarBool(g_active_info);
    HookConVarChange(g_webhook, OnCvarChanged);
    HookConVarChange(g_tag, OnCvarChanged);
    HookConVarChange(g_price, OnCvarChanged);
    HookConVarChange(g_language, OnCvarChanged);
    HookConVarChange(g_wait_timer, OnCvarChanged);
    HookConVarChange(g_chat_info, OnCvarChanged);
    HookConVarChange(g_play_sound_status, OnCvarChanged);
    HookConVarChange(g_active_info, OnCvarChanged);
    HookConVarChange(g_prime_api_key, OnCvarChanged);
}

public int OnCvarChanged(Handle convar, const char[] oldVal, const char[] newVal)
{
    if(convar == g_webhook) strcopy(s_webhook_URL, sizeof(s_webhook_URL), newVal);
    else if(convar == g_tag) strcopy(s_tag_plugin, sizeof(s_tag_plugin), newVal);
    else if(convar == g_language) strcopy(s_language, sizeof(s_language), newVal);
    else if(convar == g_prime_api_key) strcopy(s_prime_api_key, sizeof(s_prime_api_key), newVal);
    else if(convar == g_price) i_price = GetConVarInt(convar);
    else if(convar == g_wait_timer) f_wait_timer = GetConVarFloat(convar);
    else if(convar == g_chat_info) b_chat_info = GetConVarBool(convar);
    else if(convar == g_play_sound_status) i_play_sound_status = GetConVarInt(convar);
    else if(convar == g_active_info) b_active_info = GetConVarBool(convar);
}


public Action CommandDropItemUpdate(int client, int args)
{
    UpdateDropItemList(client);
    return Plugin_Handled;
}

public Action CommandDropAllItemUpdate(int client, int args)
{
    DeleteFile(s_drop_items);
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
	if(client != -1 && b_client_prime_status[ client ])
	{	
        int i_def_index = hParams.GetObjectVar(1, 20, ObjectValueType_Int);
        int i_paint_index = hParams.GetObjectVar(1, 24, ObjectValueType_Int);
        int i_rarity = hParams.GetObjectVar(1, 28, ObjectValueType_Int);
        int i_quality = hParams.GetObjectVar(1, 32, ObjectValueType_Int);
        char s_item_name[256], s_item_name_lang[256], s_image_url[256], s_drop_info[16], s_def_index[8];
        Format(s_drop_info, sizeof(s_drop_info), "[%u-%u-%u-%u]", i_def_index, i_paint_index, i_rarity, i_quality);
        KeyValues kv = CreateKeyValues( "DropItems" );
        FileToKeyValues( kv, s_drop_items );
        KvRewind(kv);
        IntToString(i_def_index, s_def_index, sizeof(s_def_index));
        if (!kv.JumpToKey(s_def_index))
        {
            Format(s_item_name,sizeof(s_item_name),"-");
            Format(s_item_name,sizeof(s_item_name_lang),"%t", "Unknow Drop");
            Format(s_image_url,sizeof(s_image_url),"https://csgo-turkiye.com/api/images/unknow_case.png");
            SentDropWebhook(client,s_item_name,s_item_name_lang,s_image_url,s_drop_info);
        }else{
            KvGetString(kv, "item_name", s_item_name, sizeof(s_item_name), "-");
            KvGetString(kv, "item_name_lang", s_item_name_lang, sizeof(s_item_name_lang), "NOT FOUND INFORMATION ABOUT DROP ITEM");
            KvGetString(kv, "image_url", s_image_url, sizeof(s_image_url), "https://csgo-turkiye.com/api/images/unknow_case.png");
            ArrayList DataArray = new ArrayList(ByteCountToCells(1024));
            DataArray.Push(client);
            DataArray.PushString(s_item_name);
            DataArray.PushString(s_item_name_lang);
            DataArray.PushString(s_image_url);
            DataArray.PushString(s_drop_info);
            char s_price_url[256];
            UrlEncodeString(s_price_url, sizeof(s_item_name), s_item_name);
            Format(s_price_url,sizeof(s_price_url),"market/priceoverview/?appid=730&currency=%d&market_hash_name=%s",i_price,s_price_url);
            HTTPClient hc_request = new HTTPClient("https://steamcommunity.com");
            hc_request.Get(s_price_url, DropPrice ,DataArray);
        }
        delete kv;
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
        ShowHudText(client, -1, "%t", "Drop ShowHudText", s_tag_plugin);
        if(i_play_sound_status == 2)
		{
			EmitSoundToAll("ui/panorama/case_awarded_1_uncommon_01.wav", SOUND_FROM_LOCAL_PLAYER, _, SNDLEVEL_NONE);
		}
		else if(i_play_sound_status== 1)
		{
			EmitSoundToClient(client, "ui/panorama/case_awarded_1_uncommon_01.wav", SOUND_FROM_LOCAL_PLAYER, _, SNDLEVEL_NONE);
		}
	}
	return MRES_Ignored;
}

void UpdateDropItemList(int client)
{
    char api_request_url[128];
    Format(api_request_url, sizeof(api_request_url), "api/csgo-items?format=json&language=%s", s_language);
    HTTPClient hc_request = new HTTPClient("https://csgo-turkiye.com");
    hc_request.Get(api_request_url, UpdateDropItems ,client);
}

void UpdateDropItems(HTTPResponse response, int client)
{
    if (response.Status != HTTPStatus_OK) {
        if(client==0){
            PrintToServer("%t", "Failed to Update Drop Items Console", s_tag_plugin);
        }else{
            if (IsValidClient(client))
            {
                CPrintToChat(client,"%t", "Failed to Update Drop Items Client", s_tag_plugin);
            }
        }
        LogError("%t", "Failed to Update Drop Items Console", s_tag_plugin);
        return;
    }

    if (response.Data == null) {
        if(client==0){
            PrintToServer("%t", "Invalid Drop Items Console", s_tag_plugin);
        }else{
            if (IsValidClient(client))
            {
                CPrintToChat(client,"%t","Invalid Drop Items Client" ,s_tag_plugin);
            }
        }
        return;
    }
    JSONArray ja_datas = view_as<JSONArray>(response.Data);
    JSONObject jo_data;
    char s_def_index[8];
    KeyValues kv = CreateKeyValues( "DropItems" );
    FileToKeyValues( kv, s_drop_items );
    for (int i = 0; i < ja_datas.Length; i++) {
        jo_data = view_as<JSONObject>(ja_datas.Get(i));
        jo_data.GetString("defindex", s_def_index, sizeof(s_def_index));
        KvRewind(kv);
        if (!kv.JumpToKey(s_def_index))
        {
            char s_item_name[256], s_item_name_lang[256], s_image_url[256];
            jo_data.GetString("item_name", s_item_name, sizeof(s_item_name));
            jo_data.GetString("item_name_lang", s_item_name_lang, sizeof(s_item_name_lang));
            jo_data.GetString("image_url", s_image_url, sizeof(s_image_url));
            KvJumpToKey( kv, s_def_index, true );
            KvSetString(kv, "item_name", s_item_name);
            KvSetString(kv, "item_name_lang", s_item_name_lang);
            KvSetString(kv, "image_url", s_image_url);
            KvRewind( kv );
            KeyValuesToFile( kv, s_drop_items );
            PrintToServer("%t", "Add Drop New Item", s_tag_plugin, s_def_index, s_item_name_lang);
        }
        delete jo_data;
    }
    delete kv;
    if(client==0){
        PrintToServer("%t", "Drop Items Updated Console", s_tag_plugin);
    }else{
        if (IsValidClient(client))
        {
                CPrintToChat(client,"%t", "Drop Items Updated Client",s_tag_plugin);
        }
    }
}

void DropPrice(HTTPResponse response, ArrayList DataArray)
{
    char s_item_price[32], s_item_name[256], s_item_name_lang[256], s_image_url[256], s_drop_info[16];
    DataArray.GetString(1, s_item_name, sizeof(s_item_name));
    DataArray.GetString(2, s_item_name_lang, sizeof(s_item_name_lang));
    DataArray.GetString(3, s_image_url, sizeof(s_image_url));
    DataArray.GetString(4, s_drop_info, sizeof(s_drop_info));
    if (response.Status != HTTPStatus_OK || response.Data == null) {
        PrintToServer("%s Failed to Drop Price", s_tag_plugin);
    }else{
        JSONObject data = view_as<JSONObject>(response.Data);
        data.GetString("median_price", s_item_price, sizeof(s_item_price));
        delete data;
    }
    if (StrEqual(s_item_price, ""))Format(s_item_price,sizeof(s_item_price),"-");
    SentDropWebhook(DataArray.Get(0), s_item_name, s_item_name_lang, s_image_url, s_drop_info, s_item_price);
} 

void SentDropWebhook(int client, char[] item_name, char[] item_name_lang, char[] image_url, char[] drop_info, char[] item_price = "-"){
    if (IsValidClient(client))
    {
        char s_hex_char[]="0123456789ABCDEF\0", s_color[8], s_temp[256], s_temp2[256]; 
        Format(s_color, sizeof(s_color), "#%c%c%c%c%c%c",s_hex_char[GetRandomInt(0,15)],s_hex_char[GetRandomInt(0,15)],s_hex_char[GetRandomInt(0,15)],s_hex_char[GetRandomInt(0,15)],s_hex_char[GetRandomInt(0,15)],s_hex_char[GetRandomInt(0,15)]);
        DiscordWebHook dw_hook = new DiscordWebHook(s_webhook_URL);
        dw_hook.SlackMode = true;
        MessageEmbed me_embed = new MessageEmbed();
        me_embed.SetColor(s_color);
        me_embed.SetThumb(image_url);
        
        Format(s_temp, sizeof(s_temp), "%t", "Embed SetTitle");
        if (!StrEqual(s_temp, "")){
            me_embed.SetTitle(s_temp);
        }

        Format(s_temp, sizeof(s_temp), "%t", "Embed Field Hostname Title");
        if (s_temp[0] != '-'){
            char s_hostname[256], s_net_ip[ 16 ];
            GetConVarString(FindConVar("hostname"), s_hostname,sizeof(s_hostname));
            int i_longip = GetConVarInt(FindConVar("hostip")), i_port = GetConVarInt(FindConVar("hostport")), i_pieces[4];
            i_pieces[0] = (i_longip >> 24) & 0x000000FF;
            i_pieces[1] = (i_longip >> 16) & 0x000000FF;
            i_pieces[2] = (i_longip >> 8) & 0x000000FF;
            i_pieces[3] = i_longip & 0x000000FF;
            Format(s_net_ip, sizeof(s_net_ip), "%d.%d.%d.%d", i_pieces[0], i_pieces[1], i_pieces[2], i_pieces[3]);
            Format(s_temp2, sizeof(s_temp2), "%t", "Embed Field Hostname Content", s_hostname, s_net_ip, i_port);
            me_embed.AddField(s_temp, s_temp2,false);
        }
        
        Format(s_temp, sizeof(s_temp), "%t", "Embed Field Player Info Title");
        if (s_temp[0] != '-'){
            char s_steam_id[32],  s_steam_id64[32], s_username[(MAX_NAME_LENGTH + 1) * 2];
            GetClientName(client, s_username, sizeof(s_username));
            GetClientAuthId(client, AuthId_Steam2, s_steam_id, sizeof(s_steam_id));
            GetClientAuthId(client, AuthId_SteamID64, s_steam_id64, sizeof(s_steam_id64));	
            Format(s_temp2, sizeof(s_temp2), "%t", "Embed Field Player Info Content", s_username, s_steam_id, s_steam_id64);
            me_embed.AddField(s_temp, s_temp2,false);
        }

        Format(s_temp, sizeof(s_temp), "%t", "Embed Field Drop Info Title");
        if (s_temp[0] != '-'){	
            Format(s_temp2, sizeof(s_temp2), "%t", "Embed Field Drop Info Content", item_name, drop_info);
            me_embed.AddField(s_temp, s_temp2,false);
        }

        Format(s_temp, sizeof(s_temp), "%t", "Embed Field Item Info Title");
        if (s_temp[0] != '-'){	
            me_embed.AddField(s_temp, item_name_lang,false);
        }

        Format(s_temp, sizeof(s_temp), "%t", "Embed Field Price Info Title");
        if (s_temp[0] != '-'){
            char s_price_url[256];
            if (!StrEqual(item_name, "-")){
                UrlEncodeString(s_price_url, sizeof(s_price_url), item_name);
                Format(s_price_url, sizeof(s_price_url),"[%s](https://steamcommunity.com/market/listings/730/%s)",item_price,s_price_url);
            }else{
                Format(s_price_url, sizeof(s_price_url),"-");
            }
            me_embed.AddField(s_temp, s_price_url,false);
        }

        FormatTime(s_temp2, sizeof(s_temp2), "%d.%m.%Y %X", GetTime());
        Format(s_temp, sizeof(s_temp), "%t", "Embed Footer", s_tag_plugin, s_temp2);
        if (s_temp[0] != '-'){
            me_embed.SetFooter(s_temp);
        }

        dw_hook.Embed(me_embed);
        dw_hook.Send();
        delete dw_hook;
        LogToFile(s_log_file, "%t", "Drop Log", client, drop_info,item_name_lang, item_price);
        CPrintToChatAll("%t", "Drop Log Chat",s_tag_plugin, client, drop_info, item_name_lang,item_price);
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
		}else if ((c < '0' && c != '-' && c != '.') ||
			(c < 'A' && c > '9') ||
			(c > 'Z' && c < 'a' && c != '_') ||
			(c > 'z' && c != '~')) 
		{
			output[i_ocnt++] = '%';
			Format(output[i_ocnt], size-strlen(output[i_ocnt]), "%x", c);
			i_ocnt += 2;
		}
		else output[i_ocnt++] = c;
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
	if(b_chat_info)
	{
		h_wait_timer = CreateTimer(1.2, DropFailed);
		CPrintToChatAll("%t", "Trying Drop", s_tag_plugin);
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
    CPrintToChatAll("%t", "Drop Attempt Failed", s_tag_plugin);
}

void ClientPrimeStatus(int client){
    b_client_prime_status[ client ] = false;
    if (IsValidClient(client)){
        if (SteamWorks_HasLicenseForApp(client, 624820) == k_EUserHasLicenseResultHasLicense){
            b_client_prime_status[ client ] = true;
            PrintToServer("%t", "Client Prime", s_tag_plugin, client);
        }else
        {
            char s_account_id[24];
            Handle h_request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, "https://prime.napas.cc/request");
            SteamWorks_SetHTTPRequestNetworkActivityTimeout(h_request, 10);
            IntToString(GetSteamAccountID(client), s_account_id, sizeof(s_account_id));
            SteamWorks_SetHTTPRequestGetOrPostParameter(h_request, "key", 		s_prime_api_key);
            SteamWorks_SetHTTPRequestGetOrPostParameter(h_request, "accountid", s_account_id);
            SteamWorks_SetHTTPCallbacks(h_request, HTTPRequestComplete);
            SteamWorks_SetHTTPRequestContextValue(h_request, client);
            SteamWorks_SendHTTPRequest(h_request);
        }
    }
}

void HTTPRequestComplete(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int client){
	delete hRequest;
	if(IsValidClient(client)){
		if(bFailure){
                PrintToServer("%t", "Failed to Prime Control", s_tag_plugin, client);
                CreateTimer(15.0, TIMER_DELAY, client, TIMER_FLAG_NO_MAPCHANGE);
		}else{
            switch(eStatusCode){
			case k_EHTTPStatusCode200OK:{
                b_client_prime_status[client] = true;
                PrintToServer("%t", "Client Prime", s_tag_plugin, client);
            }
            case k_EHTTPStatusCode204NoContent:{
                b_client_prime_status[client] = false;
                PrintToServer("%t", "Client NoPrime", s_tag_plugin, client);
            }
			case k_EHTTPStatusCode400BadRequest:{
                PrintToServer("%t", "Prime Api Invalid Request", s_tag_plugin, client);
			}
			case k_EHTTPStatusCode403Forbidden:{
				PrintToServer("%t", "Prime Api Invalid Api Key", s_tag_plugin, client);
			}
			case k_EHTTPStatusCode503ServiceUnavailable:{
                PrintToServer("%t", "Prime Api Try", s_tag_plugin, client);
                CreateTimer(15.0, TIMER_DELAY, client, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
        }
		
	}
}

Action TIMER_DELAY(Handle hTimer, int client){
	if(IsValidClient(client)){
        ClientPrimeStatus(client);
    }
}

bool IsValidClient(int client, bool nobots = true)
{
	if (client <= 0 || client > MaxClients || !IsClientConnected(client) || (nobots && IsFakeClient(client)))return false;
	return IsClientInGame(client);
}


/*

░█████╗░░██████╗░██████╗░░█████╗░░░░░░░████████╗██╗░░░██╗██████╗░██╗░░██╗██╗██╗░░░██╗███████╗░░░░█████╗░░█████╗░███╗░░░███╗
██╔══██╗██╔════╝██╔════╝░██╔══██╗░░░░░░╚══██╔══╝██║░░░██║██╔══██╗██║░██╔╝██║╚██╗░██╔╝██╔════╝░░░██╔══██╗██╔══██╗████╗░████║
██║░░╚═╝╚█████╗░██║░░██╗░██║░░██║█████╗░░░██║░░░██║░░░██║██████╔╝█████═╝░██║░╚████╔╝░█████╗░░░░░██║░░╚═╝██║░░██║██╔████╔██║
██║░░██╗░╚═══██╗██║░░╚██╗██║░░██║╚════╝░░░██║░░░██║░░░██║██╔══██╗██╔═██╗░██║░░╚██╔╝░░██╔══╝░░░░░██║░░██╗██║░░██║██║╚██╔╝██║
╚█████╔╝██████╔╝╚██████╔╝╚█████╔╝░░░░░░░░░██║░░░╚██████╔╝██║░░██║██║░╚██╗██║░░░██║░░░███████╗██╗╚█████╔╝╚█████╔╝██║░╚═╝░██║
░╚════╝░╚═════╝░░╚═════╝░░╚════╝░░░░░░░░░░╚═╝░░░░╚═════╝░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░░╚═╝░░░╚══════╝╚═╝░╚════╝░░╚════╝░╚═╝░░░░░╚═╝

*/