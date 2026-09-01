if ($http_user_agent ~* (nikto|scan|attack|inject|exploit)) {
    return 403;
}

if ($http_user_agent ~* (PetalBot|SemrushBot|AhrefsBot|MJ12bot|DotBot|Barkrowler|DataForSeoBot|BLEXBot|YandexBot)) {
    return 403;
}

if ($http_user_agent = "") {
    return 403;
}
