# CS:GO Advanced Drop
Attempts to drop drops for the duration of the map. It sends the falling drops to the discord server in an advanced way.

# Dependencies (Bağımlılık)

> [Discord Api](https://github.com/Deathknife/sourcemod-discord)

# Description (Açıklama)

**[EN]**

In the game "Counter-Strike: Global Offensive", it allows the drop to drop before the map time expires. It sends the falling drops to your discord server as a notification. It finds the instant price of a dropped item by determining the price type on the cvar. Drop items are updated by command or automatically at every map start. You can find the data provided via the Steam Api in the following site, simply translated into "json" and "vdf" formats. You can manually edit the file "csgo/addons/sourcemod/configs/CSGO-Turkiye_com/dropitems.cfg" in case of error on pull from website. If you change the Oge names, it will give an error in the market price. If you change the item names, you will make a mistake in the market price. You can find all logs in "csgo/addons/sourcemod/logs/advanced_drop.log".

**[TR]**

"Counter-Strike: Global Offensive" oyununda harita süresi bitmeden drop düşmesini sağlar. Düşen dropları bildirim olarak discord sunucunuza atar. Düşen bir ögenin fiyat tipi cvar üzerinden belirlenerek anlık fiyatını bulur. Drop ögeleri komut ile veya her harita başlangıcında otomatik olarak güncellenir. Steam Api üzerinden sağlanan verileri aşağıda belirtilen sitede basit şekilde "json" ve "vdf" formatına çevrilmiş olarak bulabilirsiniz. Web sitesinden çekme durumunda hata olması durumunda "csgo/addons/sourcemod/configs/CSGO-Turkiye_com/dropitems.cfg" dosyasına manuel olarak düzenleyebilirsiniz. Çge isimlerini değiştirirseniniz market fiyatında hata verecektir. "csgo/addons/sourcemod/logs/advanced_drop.log" klasöründe tümkayıtları bulabilirsiniz.

**JSON:** https://csgo-turkiye.com/api/csgo-items?format=json

**VDF:** https://csgo-turkiye.com/api/csgo-items?format=vdf or https://csgo-turkiye.com/api/csgo-items

# Commands (Komutlar)

-  sm_updatedropitems (ROOT)

**[EN]**

Used to update drop items.

**[TR]**

Drop ögelerini güncellemek için kullanılır.

# Settings (Ayarlar) [ cvar => csgo/cfg/CSGO_Turkiye/advanced-drop.cfg ]

| cvar          | Default       | EN            | TR            |
| ------------- | ------------- | ------------- | ------------- |
| sm_webhook_advenced_drop | https://discord.com/api/webhooks/xxxxx/xxxxxxx | Advanced Drop Webhook URL | Webhook URL |
| sm_tag_advenced_drop | [ csgo-turkiye.com Advanced Drop ] | Advanced Drop Plugin Tag | Eklenti Tagı |
| sm_price_advenced_drop | 1 (1:$ - 2:£ - 3:€ - 4:CHF - 5:pуб. - 6:zł - 7:R$ - 8:¥ - 9:kr - 10:Rp - 11:RM - 12:P - 13:S$ - 14:฿ - 15:₫ - 16:₩ - 17:TL - 18:₴ - 19:Mex$ - 20:CDN$ - 21:A$ - 22:NZ$ - 23:¥ - 24:₹ - 25:CLP$ - 26:S/. - 27:COL$ - 28:R - 29:HK$ - 30:NT$ - 31:SR - 32:AED - 34:ARS$ - 35:₪ - 37:₸ - 38:KD - 39:QR - 40:₡ - 41:$U) | Advanced Drop Item Price | Para Birimi |
| sm_wait_timer_advenced_drop | 182 | How many seconds should a drop attempt be made? (3Do not do less than 3 minutes, ideal is 10 minutes) | Kaç saniye düşme denemesi yapılmalıdır? (3 dakikadan az yapmayın, ideali 10 dakikadır) |
| sm_chat_info_advenced_drop | 1 | Show drop attempts in chat? | Drop denemeleri sohbette gösterilsin mi? |
| sm_sound_status_advenced_drop | 2 | Play a sound when the drop drops? [0 - no | 1 - just drop it | 2 - to everyone] | Drop düştüğünde bir ses çalınsın mı? [0 - hayır | 1 - sadece drop düşene | 2 - herkese] |

