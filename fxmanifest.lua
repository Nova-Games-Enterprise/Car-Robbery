fx_version 'cerulean'
game 'gta5'

author 'bacasuoro'
description 'Sistema di furto veicoli per ESX'
version '1.0.0'

shared_script 'config.lua'

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}

dependencies {
    'es_extended'
}

escrow_ignore {
    'config.lua'
}