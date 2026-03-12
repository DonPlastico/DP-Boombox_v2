local Framework = nil
local ESX = nil
local QBCore = nil

if GetResourceState('es_extended') == 'started' or GetResourceState('es_extended') == 'starting' then
    Framework = 'ESX'
    ESX = exports['es_extended']:getSharedObject()
elseif GetResourceState('qb-core') == 'started' or GetResourceState('qb-core') == 'starting' then
    Framework = 'qb'
    QBCore = exports['qb-core']:GetCoreObject()
else
    print("^0[^1ERROR^0] ¡No se pudo inicializar el Framework en DP-Boombox_v2!^0")
end

-- Función para generar un código aleatorio (Ej: X7B9K2M)
local function GenerarCodigoCompartir()
    local caracteres = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local codigo = ""
    for i = 1, 8 do
        local rand = math.random(1, #caracteres)
        codigo = codigo .. string.sub(caracteres, rand, rand)
    end
    return codigo
end

-- 🛠️ CREACIÓN DE TABLAS SQL
MySQL.ready(function()
    MySQL.Sync.execute([[
        CREATE TABLE IF NOT EXISTS `dp_listas_repro` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(50) NOT NULL DEFAULT '0',
            `owner` VARCHAR(255) NOT NULL DEFAULT '',
            `share_code` VARCHAR(15) NOT NULL DEFAULT '',
            PRIMARY KEY (`id`),
            UNIQUE INDEX `share_code` (`share_code`)
        ) COLLATE='utf8mb4_general_ci';
    ]])

    MySQL.Sync.execute([[
        CREATE TABLE IF NOT EXISTS `dp_canciones` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `url` VARCHAR(50) NOT NULL DEFAULT '0',
            `name` VARCHAR(150) NOT NULL DEFAULT '0',
            `author` VARCHAR(50) NOT NULL DEFAULT '0',
            `maxDuration` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            UNIQUE INDEX `url` (`url`)
        ) COLLATE='utf8mb4_general_ci';
    ]])

    MySQL.Sync.execute([[
        CREATE TABLE IF NOT EXISTS `dp_listas_jugadores` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `license` VARCHAR(255) NOT NULL DEFAULT '',
            `playlist` INT NOT NULL DEFAULT 0,
            `perm_rename` INT NOT NULL DEFAULT 0,
            `perm_add` INT NOT NULL DEFAULT 0,
            `perm_delete` INT NOT NULL DEFAULT 0,
            `perm_reorder` INT NOT NULL DEFAULT 0,
            `perm_manage` INT NOT NULL DEFAULT 0,
            `perm_future1` INT NOT NULL DEFAULT 0,
            `perm_future2` INT NOT NULL DEFAULT 0,
            INDEX `license` (`license`),
            PRIMARY KEY (`id`),
            CONSTRAINT `fk_dp_list_jugadores` FOREIGN KEY (`playlist`) REFERENCES `dp_listas_repro` (`id`) ON UPDATE CASCADE ON DELETE CASCADE
        ) COLLATE='utf8mb4_general_ci';
    ]])

    MySQL.Sync.execute([[
        CREATE TABLE IF NOT EXISTS `dp_listas_canciones` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `playlist` INT NOT NULL DEFAULT '0',
            `song` INT NOT NULL DEFAULT '0',
            PRIMARY KEY (`id`),
            CONSTRAINT `fk_dp_list_repro` FOREIGN KEY (`playlist`) REFERENCES `dp_listas_repro` (`id`) ON UPDATE CASCADE ON DELETE CASCADE,
            CONSTRAINT `fk_dp_cancion` FOREIGN KEY (`song`) REFERENCES `dp_canciones` (`id`) ON UPDATE CASCADE ON DELETE CASCADE
        ) COLLATE='utf8mb4_general_ci';
    ]])
end)

-- ==========================================
-- 📋 FUNCIONES LOCALES (DEBEN ESTAR ARRIBA)
-- ==========================================

-- OBTENER LAS PLAYLISTS DEL JUGADOR
local function getPlaylists(identificador, cb)
    local query = [[
        SELECT p.id, p.name, p.owner, p.share_code, 
               IF(p.owner = @id, 1, 0) as is_owner
        FROM dp_listas_repro p
        LEFT JOIN dp_listas_jugadores j ON p.id = j.playlist
        WHERE p.owner = @id OR j.license = @id
        GROUP BY p.id
    ]]
    MySQL.Async.fetchAll(query, {
        ['@id'] = identificador
    }, function(result)
        cb(result or {})
    end)
end

-- 📋 OBTENER DETALLES Y MIEMBROS DE LA LISTA (CON NOMBRES REALES)
local function fetchPlaylistDetails(playlistId, identificador, cb)
    local response = {
        playlist = {},
        members = {},
        myPerms = nil
    }

    MySQL.Async.fetchAll('SELECT id, name, owner FROM dp_listas_repro WHERE id = @id', {
        ['@id'] = playlistId
    }, function(plResult)
        if plResult and plResult[1] then
            response.playlist = plResult[1]
            local isOwner = (plResult[1].owner == identificador)

            local query = ""
            if Framework == "ESX" then
                query =
                    "SELECT j.*, u.firstname, u.lastname FROM dp_listas_jugadores j LEFT JOIN users u ON j.license = u.identifier WHERE j.playlist = @id"
            elseif Framework == "qb" then
                query =
                    "SELECT j.*, p.charinfo FROM dp_listas_jugadores j LEFT JOIN players p ON j.license = p.citizenid WHERE j.playlist = @id"
            end

            MySQL.Async.fetchAll(query, {
                ['@id'] = playlistId
            }, function(membersResult)
                local processedMembers = {}
                if membersResult then
                    for i = 1, #membersResult do
                        local m = membersResult[i]
                        local charName = "Desconocido"

                        if Framework == "ESX" then
                            if m.firstname and m.lastname then
                                charName = m.firstname .. " " .. m.lastname
                            end
                        elseif Framework == "qb" then
                            if m.charinfo then
                                local decoded = json.decode(m.charinfo)
                                if decoded and decoded.firstname and decoded.lastname then
                                    charName = decoded.firstname .. " " .. decoded.lastname
                                end
                            end
                        end

                        m.charName = charName
                        table.insert(processedMembers, m)

                        if m.license == identificador then
                            response.myPerms = m
                        end
                    end
                end

                -- 🔹 FIX: Pasamos también la 'license' para que el Front-End reconozca al dueño
                if isOwner then
                    response.myPerms = {
                        license = identificador,
                        perm_rename = 1,
                        perm_manage = 1,
                        perm_delete = 1,
                        perm_add = 1,
                        perm_reorder = 1
                    }
                end

                response.members = processedMembers
                cb(response)
            end)
        else
            cb(response)
        end
    end)
end

-- 💾 GUARDAR CAMBIOS DE EDICIÓN Y PERMISOS BLINDADO
RegisterServerEvent('DP-Boombox_v2:savePlaylistEdit', function(data)
    local src = source
    local playlistId = data.id
    local newName = data.newName
    local perms = data.permissions

    local identificador = nil
    if Framework == "ESX" then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            identificador = xPlayer.identifier
        end
    elseif Framework == "qb" then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            identificador = Player.PlayerData.citizenid
        end
    end
    if not identificador then
        return
    end

    -- Extraemos al dueño para verificar los bloqueos
    MySQL.Async.fetchAll('SELECT owner FROM dp_listas_repro WHERE id = @id', {
        ['@id'] = playlistId
    }, function(res)
        if not res or not res[1] then
            return
        end
        local isOwner = (res[1].owner == identificador)

        -- 1. Si está guardando permisos de un jugador...
        if perms then
            -- 🚨 SEGURIDAD: Si no eres el dueño e intentas editar tus propios permisos, TE BLOQUEAMOS.
            if not isOwner and perms.license == identificador then
                TriggerClientEvent('DP-Boombox_v2:notificar', src, 'error', 'No puedes auto-gestionarte los permisos.')
                return
            end

            -- 🚨 SEGURIDAD: Nadie puede editar al dueño (por si hubiera algún bug y saliera en la tabla)
            if not isOwner and perms.license == res[1].owner then
                TriggerClientEvent('DP-Boombox_v2:notificar', src, 'error', 'No puedes editar permisos del Creador.')
                return
            end

            MySQL.Async.execute([[
                UPDATE dp_listas_jugadores 
                SET perm_rename = @p1, perm_delete = @p2, perm_add = @p3, 
                    perm_reorder = @p4, perm_manage = @p5, perm_future1 = @p6, perm_future2 = @p7
                WHERE playlist = @id AND license = @license
            ]], {
                ['@p1'] = perms.perm_rename,
                ['@p2'] = perms.perm_delete,
                ['@p3'] = perms.perm_add,
                ['@p4'] = perms.perm_reorder,
                ['@p5'] = perms.perm_manage,
                ['@p6'] = perms.perm_future1,
                ['@p7'] = perms.perm_future2,
                ['@id'] = playlistId,
                ['@license'] = perms.license
            })
        end

        -- 2. Guardamos el nombre
        MySQL.Async.execute('UPDATE dp_listas_repro SET name = @name WHERE id = @id', {
            ['@name'] = newName,
            ['@id'] = playlistId
        }, function()
            TriggerClientEvent('DP-Boombox_v2:notificar', src, 'success', 'Cambios guardados correctamente.')
            TriggerClientEvent('DP-Boombox_v2:refreshPlaylists', src)
        end)
    end)
end)

-- ==========================================
-- 📦 USO DEL OBJETO Y CALLBACKS DE FRAMEWORK
-- ==========================================
if Framework == "ESX" then
    for nombreItem, _ in pairs(Config.Radios) do
        ESX.RegisterUsableItem(nombreItem, function(source)
            local xPlayer = ESX.GetPlayerFromId(source)
            TriggerClientEvent('DP-Boombox_v2:useBoombox', source)
            xPlayer.removeInventoryItem(nombreItem, 1)
        end)
    end

    ESX.RegisterServerCallback('DP-Boombox_v2:fetchPlaylists', function(source, cb)
        local xPlayer = ESX.GetPlayerFromId(source)
        getPlaylists(xPlayer.identifier, cb)
    end)

    ESX.RegisterServerCallback('DP-Boombox_v2:getPlaylistDetails', function(source, cb, playlistId)
        local xPlayer = ESX.GetPlayerFromId(source)
        fetchPlaylistDetails(playlistId, xPlayer.identifier, cb)
    end)

elseif Framework == "qb" then
    for nombreItem, _ in pairs(Config.Radios) do
        QBCore.Functions.CreateUseableItem(nombreItem, function(source)
            local Player = QBCore.Functions.GetPlayer(source)
            TriggerClientEvent('DP-Boombox_v2:useBoombox', source)
            Player.Functions.RemoveItem(nombreItem, 1)
        end)
    end

    QBCore.Functions.CreateCallback('DP-Boombox_v2:fetchPlaylists', function(source, cb)
        local Player = QBCore.Functions.GetPlayer(source)
        getPlaylists(Player.PlayerData.citizenid, cb)
    end)

    QBCore.Functions.CreateCallback('DP-Boombox_v2:getPlaylistDetails', function(source, cb, playlistId)
        local Player = QBCore.Functions.GetPlayer(source)
        fetchPlaylistDetails(playlistId, Player.PlayerData.citizenid, cb)
    end)
end

-- ==========================================
-- 🚀 EVENTOS DEL SERVIDOR (LÓGICA)
-- ==========================================

RegisterServerEvent('DP-Boombox_v2:deleteObj', function(netId)
    TriggerClientEvent('DP-Boombox_v2:deleteObj', -1, netId)
end)

RegisterServerEvent('DP-Boombox_v2:objDeleted', function()
    local src = source
    local itemDevolver = 'speaker'
    if Framework == "ESX" then
        local xPlayer = ESX.GetPlayerFromId(src)
        xPlayer.addInventoryItem(itemDevolver, 1)
    elseif Framework == "qb" then
        local Player = QBCore.Functions.GetPlayer(src)
        Player.Functions.AddItem(itemDevolver, 1)
    end
end)

RegisterNetEvent("DP-Boombox_v2:soundStatus", function(tipo, idMusica, datos)
    TriggerClientEvent("DP-Boombox_v2:soundStatus", -1, tipo, idMusica, datos)
end)

RegisterNetEvent("DP-Boombox_v2:syncActive", function(radiosActivas)
    TriggerClientEvent("DP-Boombox_v2:syncActive", -1, radiosActivas)
end)

RegisterServerEvent('DP-Boombox_v2:createPlaylist', function(nombreLista)
    local src = source
    local codigoUnico = GenerarCodigoCompartir()

    local function InsertarLista(identificador)
        MySQL.Async.insert(
            'INSERT INTO `dp_listas_repro` (`name`, `owner`, `share_code`) VALUES (@name, @owner, @code)', {
                ['@name'] = nombreLista,
                ['@owner'] = identificador,
                ['@code'] = codigoUnico
            }, function(insertId)
                TriggerClientEvent('DP-Boombox_v2:notificar', src, 'success', 'Lista creada: ' .. nombreLista)
                TriggerClientEvent('DP-Boombox_v2:refreshPlaylists', src)
            end)
    end

    if Framework == "ESX" then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            InsertarLista(xPlayer.identifier)
        end
    elseif Framework == "qb" then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            InsertarLista(Player.PlayerData.citizenid)
        end
    end
end)

RegisterServerEvent('DP-Boombox_v2:joinPlaylist', function(codigo)
    local src = source
    local identificador = nil

    if Framework == "ESX" then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            identificador = xPlayer.identifier
        end
    elseif Framework == "qb" then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            identificador = Player.PlayerData.citizenid
        end
    end

    if not identificador then
        return
    end

    MySQL.Async.fetchAll('SELECT id, name, owner FROM dp_listas_repro WHERE share_code = @code', {
        ['@code'] = codigo
    }, function(result)
        if result and #result > 0 then
            local playlist = result[1]

            if playlist.owner == identificador then
                TriggerClientEvent('DP-Boombox_v2:notificar', src, 'error', 'Ya eres el propietario de esta lista.')
                return
            end

            MySQL.Async.fetchAll('SELECT id FROM dp_listas_jugadores WHERE license = @license AND playlist = @playlist',
                {
                    ['@license'] = identificador,
                    ['@playlist'] = playlist.id
                }, function(joinResult)
                    if joinResult and #joinResult > 0 then
                        TriggerClientEvent('DP-Boombox_v2:notificar', src, 'error',
                            'Ya perteneces a la lista: ' .. playlist.name)
                    else
                        MySQL.Async.insert(
                            'INSERT INTO dp_listas_jugadores (license, playlist) VALUES (@license, @playlist)', {
                                ['@license'] = identificador,
                                ['@playlist'] = playlist.id
                            }, function()
                                TriggerClientEvent('DP-Boombox_v2:notificar', src, 'success',
                                    'Te has unido a: ' .. playlist.name)
                                TriggerClientEvent('DP-Boombox_v2:refreshPlaylists', src)
                            end)
                    end
                end)
        else
            TriggerClientEvent('DP-Boombox_v2:notificar', src, 'error', 'Código de lista inválido o no encontrado.')
        end
    end)
end)

-- ==========================================
-- 🎵 SISTEMA DE CANCIONES DE LA PLAYLIST
-- ==========================================
RegisterServerEvent('DP-Boombox_v2:getPlaylistSongs', function(data)
    local src = source
    local playlistId = data.playlistId

    -- 1. Buscamos el nombre de la lista para ponerlo en el título del menú
    MySQL.Async.fetchAll('SELECT name FROM dp_listas_repro WHERE id = @id', {
        ['@id'] = playlistId
    }, function(plRes)
        if plRes and plRes[1] then
            local playlistName = plRes[1].name

            -- 2. Buscamos las canciones cruzando la tabla de canciones con la de relación (JOIN)
            local query = [[
                SELECT c.id, c.url, c.name AS label, c.author, c.maxDuration 
                FROM dp_canciones c 
                INNER JOIN dp_listas_canciones lc ON c.id = lc.song 
                WHERE lc.playlist = @playlistId 
                ORDER BY lc.id ASC
            ]]

            MySQL.Async.fetchAll(query, {
                ['@playlistId'] = playlistId
            }, function(songs)
                -- Mandamos las canciones al cliente. Si no hay, mandamos una tabla vacía {}
                TriggerClientEvent('DP-Boombox_v2:loadPlaylistSongs', src, songs or {}, playlistName)
            end)
        end
    end)
end)

-- ==========================================
-- 🗑️ ABANDONAR / ELIMINAR / TRASPASAR LISTA
-- ==========================================

-- Función de ayuda para no repetir código sacando el identifier
local function GetPlayerIdentifier(src)
    if Framework == "ESX" then
        local xPlayer = ESX.GetPlayerFromId(src)
        return xPlayer and xPlayer.identifier or nil
    elseif Framework == "qb" then
        local Player = QBCore.Functions.GetPlayer(src)
        return Player and Player.PlayerData.citizenid or nil
    end
    return nil
end

-- INVITADO: Abandonar lista
RegisterServerEvent('DP-Boombox_v2:leavePlaylist', function(playlistId)
    local src = source
    local identifier = GetPlayerIdentifier(src)
    if not identifier then
        return
    end

    MySQL.Async.execute('DELETE FROM dp_listas_jugadores WHERE playlist = @id AND license = @license', {
        ['@id'] = playlistId,
        ['@license'] = identifier
    }, function(rowsChanged)
        if rowsChanged > 0 then
            TriggerClientEvent('DP-Boombox_v2:notificar', src, 'success', 'Has abandonado la lista.')
            TriggerClientEvent('DP-Boombox_v2:refreshPlaylists', src)
        end
    end)
end)

-- OWNER: Eliminar la lista (Destrucción total)
RegisterServerEvent('DP-Boombox_v2:deletePlaylist', function(playlistId)
    local src = source
    local identifier = GetPlayerIdentifier(src)
    if not identifier then
        return
    end

    -- Comprobamos por seguridad que de verdad es el dueño
    MySQL.Async.fetchAll('SELECT owner FROM dp_listas_repro WHERE id = @id', {
        ['@id'] = playlistId
    }, function(res)
        if res and res[1] and res[1].owner == identifier then
            -- Como en SQL pusimos 'ON DELETE CASCADE', al borrar la lista se borrarán automáticamente 
            -- los invitados y las canciones enlazadas a ella.
            MySQL.Async.execute('DELETE FROM dp_listas_repro WHERE id = @id', {
                ['@id'] = playlistId
            }, function()
                TriggerClientEvent('DP-Boombox_v2:notificar', src, 'success', 'Lista eliminada correctamente.')
                TriggerClientEvent('DP-Boombox_v2:refreshPlaylists', src)
            end)
        end
    end)
end)

-- OWNER: Traspasar a un invitado y salirse
RegisterServerEvent('DP-Boombox_v2:transferPlaylist', function(playlistId, newOwner)
    local src = source
    local identifier = GetPlayerIdentifier(src)
    if not identifier then
        return
    end

    MySQL.Async.fetchAll('SELECT owner FROM dp_listas_repro WHERE id = @id', {
        ['@id'] = playlistId
    }, function(res)
        if res and res[1] and res[1].owner == identifier then

            -- 1. Le pasamos el trono al nuevo dueño
            MySQL.Async.execute('UPDATE dp_listas_repro SET owner = @newOwner WHERE id = @id', {
                ['@newOwner'] = newOwner,
                ['@id'] = playlistId
            }, function()

                -- 2. Borramos al nuevo dueño de la tabla de invitados (porque ahora manda él)
                MySQL.Async.execute('DELETE FROM dp_listas_jugadores WHERE playlist = @id AND license = @newOwner', {
                    ['@id'] = playlistId,
                    ['@newOwner'] = newOwner
                }, function()
                    TriggerClientEvent('DP-Boombox_v2:notificar', src, 'success',
                        'Propiedad transferida. Has abandonado la lista.')
                    TriggerClientEvent('DP-Boombox_v2:refreshPlaylists', src)
                end)
            end)
        end
    end)
end)
