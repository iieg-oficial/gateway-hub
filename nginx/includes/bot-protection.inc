if ($http_user_agent ~* (scrapy|httpclient|spider|java|perl|ruby|php|go-http|node-fetch|axios|postman|insomnia|httpie|headless|phantom|selenium|puppeteer|playwright|mechanize|libwww|lwp|urllib|winhttp|httrack|clshttp|archiver|loader|email|harvest|extract|grab|miner|nikto|scan|attack|inject|exploit)) {
    return 403;
}

if ($http_user_agent ~* (ChatGPT|GPTBot|Google-Extended|anthropic|ClaudeBot|CCBot|Bytespider|PetalBot|SemrushBot|AhrefsBot|MJ12bot|DotBot|Barkrowler|DataForSeoBot|BLEXBot|YandexBot)) {
    return 403;
}

if ($http_user_agent ~* (^curl|^wget|python-requests|python-urllib|aiohttp)) {
    return 403;
}

if ($http_user_agent = "") {
    return 403;
}
