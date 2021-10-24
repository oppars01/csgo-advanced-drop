# CS:GO Advanced Drop
Attempts to drop drops for the duration of the map. It sends the falling drops to the discord server in an advanced way.

# Description (Açıklama)

**[EN]**

In the game "Counter-Strike: Global Offensive", it allows the drop to drop before the map time expires. It sends the falling drops to your discord server as a notification. It finds the instant price of a dropped item by determining the price type on the cvar. Drop items are updated by command or automatically at every map start. You can find the data provided via the Steam Api in the following site, simply translated into "json" and "vdf" formats. You can manually edit the file "csgo/addons/sourcemod/configs/CSGO-Turkiye_com/dropitems.cfg" in case of error on pull from website. If you change the Oge names, it will give an error in the market price. If you change the item names, you will make a mistake in the market price. You can find all logs in "csgo/addons/sourcemod/logs/advanced_drop.log".

--------------------
**[TR]**

"Counter-Strike: Global Offensive" oyununda harita süresi bitmeden drop düşmesini sağlar. Düşen dropları bildirim olarak discord sunucunuza atar. Düşen bir ögenin fiyat tipi cvar üzerinden belirlenerek anlık fiyatını bulur. Drop ögeleri komut ile veya her harita başlangıcında otomatik olarak güncellenir. Steam Api üzerinden sağlanan verileri aşağıda belirtilen sitede basit şekilde "json" ve "vdf" formatına çevrilmiş olarak bulabilirsiniz. Web sitesinden çekme durumunda hata olması durumunda "csgo/addons/sourcemod/configs/CSGO-Turkiye_com/dropitems.cfg" dosyasına manuel olarak düzenleyebilirsiniz. Çge isimlerini değiştirirseniniz market fiyatında hata verecektir. "csgo/addons/sourcemod/logs/advanced_drop.log" klasöründe tümkayıtları bulabilirsiniz.

**JSON:** https://csgo-turkiye.com/api/csgo-items?format=json
**VDF:** https://csgo-turkiye.com/api/csgo-items?format=vdf or https://csgo-turkiye.com/api/csgo-items
