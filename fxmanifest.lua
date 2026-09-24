fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'
lua54 'yes'

name 'rsg_chest'
author 'romeorem'
description 'Coffres à code posables (placement gizmo) + perquisition pour les forces de l\'ordre - RSG Core'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/nui.lua',
    'client/placement.lua',
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

dependencies {
    'rsg-core',
    'rsg-inventory',
    'ox_lib',
    'oxmysql',
}
