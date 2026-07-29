fx_version 'cerulean'
game 'gta5'

lua54 'yes'

author 'TwoPoint Development'
description 'TwoPointWeather: server-authoritative synced time and dynamic weather with smooth transitions and LB Phone compatibility data.'
version '1.3.1'

shared_script 'config.lua'

server_script 'server/main.lua'

client_scripts {
    'client/main.lua',
    'client/lb_phone.lua'
}
