fx_version 'cerulean'
game 'gta5'

author 'bacasuoro'
description 'NGE Car Robbery per ESX/QBCore/Qbox'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/framework.lua',
    'client.lua'
}

server_scripts {
    'server/framework.lua',
    'server.lua'
}

dependencies {
    '/onesync',
    'ox_lib'
}

escrow_ignore {
    'config.lua'
}