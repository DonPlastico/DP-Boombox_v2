fx_version "cerulean"
game "gta5"

description 'DP-Boombox_v2 (Custom UI)'
version '2.2.0'

lua54 'yes'

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/script.js'
}

client_scripts {
    'client/**.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/**.lua'
}

shared_scripts {
    'config.lua'
}

dependencies {
    'xsound'
}