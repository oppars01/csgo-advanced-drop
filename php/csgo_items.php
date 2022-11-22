<?php 

$STEAM_API_KEY = 'xxxxxxxxxxxxxxxxxxxxxxx';
function curl($url)
{
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
    curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0 (Windows; U; Windows NT 5.1; tr; rv:1.9.0.6) Gecko/2009011913 Firefox/3.0.6');
    $data = curl_exec($ch);
    curl_close($ch);
    return $data;
}

header('Content-Type: application/json');
if($_SERVER['REQUEST_METHOD'] == "GET") {
    $format = strip_tags(htmlspecialchars(addslashes(trim($_GET['format']))));
    $lang = strip_tags(htmlspecialchars(addslashes(trim($_GET['language']))));
    if(empty($lang))$lang = 'en';
    $result = json_decode(curl('https://api.steampowered.com/IEconItems_730/GetSchema/v2/?key='.$STEAM_API_KEY.'&format=json&language=en'),true);
    $result_lang = ($lang == "en" ? $result : json_decode(curl('https://api.steampowered.com/IEconItems_730/GetSchema/v2/?key='.$STEAM_API_KEY.'&format=json&language='.$lang),true));
    if($format!="json"){
        echo '"DropItems"
{
';
    }else{
        $jsonArray = array();
    }

    for($i=0; $i < count($result['result']['items']);$i++){
        $item = $result['result']['items'][$i];
        $item_lang = $result_lang['result']['items'][$i];
        if(!empty($item['defindex'])&&!empty($item['item_type_name'])){
            if($item['item_type_name']=="Container" && (stristr($item['item_name'], 'Case') || stristr($item['item_name'], 'Capsule'))){
                if($format!="json"){
                    echo '
    "'.$item['defindex'].'"
    {
        "item_name"             "'.$item['item_name'].'"
        "item_name_lang"             "'.$item_lang['item_name'].'"
        "image_url"             "'.$item['image_url'].'"
    }';
                }else{
                    $jsonArray[]= [
            "defindex"      =>      strval($item['defindex']),
            "item_name"     =>      $item['item_name'],
            "item_name_lang"     =>      $item_lang['item_name'],
            "image_url"     =>     $item['image_url']
            ];
                }
            }
        }
    }

    if($format!="json"){
        echo '
}';
    }else{
        echo json_encode($jsonArray, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
    }

}else{
    echo 'Invalid Request';
}