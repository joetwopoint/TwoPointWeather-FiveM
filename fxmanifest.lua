fx_version '1.3.1'
game 'gta5'

author 'TwoPoint Development'
description 'Synced Tucson weather (Open-Meteo) + synced server-authority game time (not IRL) + /weather forecast UI'
version '1.3.1'

shared_scripts {
  'shared/config.lua'
}

server_scripts {
  'server/main.lua'
}

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/style.css',
  'html/script.js'
}

client_scripts {
  'client/main.lua'
}
