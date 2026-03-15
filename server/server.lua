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

-- OBTENER LAS PLAYLISTS DEL JUGADOR (CON HASTA 5 CANCIONES PARA EL MOSAICO)
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
    }, function(playlists)
        -- Si no tiene listas, devolvemos vacío y terminamos
        if not playlists or #playlists == 0 then
            cb({})
            return
        end

        -- Si tiene listas, preparamos una búsqueda para traer sus canciones
        local playlistIds = {}
        for i = 1, #playlists do
            table.insert(playlistIds, playlists[i].id)
        end

        local idsString = table.concat(playlistIds, ",")
        local songsQuery = string.format([[
            SELECT lc.playlist, c.url 
            FROM dp_listas_canciones lc 
            JOIN dp_canciones c ON lc.song = c.id 
            WHERE lc.playlist IN (%s) 
            ORDER BY lc.id ASC
        ]], idsString)

        -- Buscamos las canciones y las agrupamos
        MySQL.Async.fetchAll(songsQuery, {}, function(songs)
            local thumbnailsByPlaylist = {}

            if songs then
                for i = 1, #songs do
                    local pId = songs[i].playlist
                    if not thumbnailsByPlaylist[pId] then
                        thumbnailsByPlaylist[pId] = {}
                    end
                    -- Limitamos a un máximo de 5 canciones por lista para el mosaico
                    if #thumbnailsByPlaylist[pId] < 5 then
                        table.insert(thumbnailsByPlaylist[pId], songs[i].url)
                    end
                end
            end

            -- Metemos las URL dentro de los datos de cada playlist
            for i = 1, #playlists do
                playlists[i].thumbnails = thumbnailsByPlaylist[playlists[i].id] or {}
            end

            cb(playlists)
        end)
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

    -- CORTAMOS EL STRING A 50 CARACTERES POR SEGURIDAD
    local newName = string.sub(data.newName, 1, 50)
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

    -- CORTAMOS EL STRING A 50 CARACTERES POR SEGURIDAD
    local nombreSeguro = string.sub(nombreLista, 1, 50)

    local function InsertarLista(identificador)
        MySQL.Async.insert(
            'INSERT INTO `dp_listas_repro` (`name`, `owner`, `share_code`) VALUES (@name, @owner, @code)', {
                ['@name'] = nombreSeguro,
                ['@owner'] = identificador,
                ['@code'] = codigoUnico
            }, function(insertId)
                TriggerClientEvent('DP-Boombox_v2:notificar', src, 'success', 'Lista creada: ' .. nombreSeguro)
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

-- ==========================================
-- 🎵 AÑADIR CANCIÓN A LA LISTA
-- ==========================================
RegisterServerEvent('DP-Boombox_v2:addSongToPlaylist', function(data)
    local src = source
    local playlistId = data.playlistId
    local url = data.url

    -- Recortamos los nombres para evitar el "Data too long" de SQL (150 y 50 caracteres)
    local title = string.sub(data.title, 1, 150)
    local author = string.sub(data.author, 1, 50)

    -- 1. Insertar la canción en la tabla general (Si ya existe la URL, actualizamos su nombre)
    MySQL.Async.execute([[
        INSERT INTO dp_canciones (url, name, author, maxDuration) 
        VALUES (@url, @name, @author, 0)
        ON DUPLICATE KEY UPDATE name = @name, author = @author
    ]], {
        ['@url'] = url,
        ['@name'] = title,
        ['@author'] = author
    }, function()

        -- 2. Obtenemos la ID interna de la canción en la base de datos
        MySQL.Async.fetchAll('SELECT id FROM dp_canciones WHERE url = @url', {
            ['@url'] = url
        }, function(res)
            if res and res[1] then
                local songId = res[1].id

                -- 3. Comprobamos si esta canción ya está en ESTA playlist
                MySQL.Async.fetchAll('SELECT id FROM dp_listas_canciones WHERE playlist = @playlist AND song = @song',
                    {
                        ['@playlist'] = playlistId,
                        ['@song'] = songId
                    }, function(relRes)
                        if relRes and #relRes > 0 then
                            -- ¡LA CANCIÓN YA ESTÁ EN LA LISTA! Avisamos al menú JS para que ponga el texto en rojo
                            TriggerClientEvent('DP-Boombox_v2:addSongResult', src, 'duplicate')
                        else
                            -- 4. No existe en la lista, la enlazamos
                            MySQL.Async.execute(
                                'INSERT INTO dp_listas_canciones (playlist, song) VALUES (@playlist, @song)', {
                                    ['@playlist'] = playlistId,
                                    ['@song'] = songId
                                }, function()
                                    TriggerClientEvent('DP-Boombox_v2:notificar', src, 'success', 'Añadida: ' .. title)
                                    TriggerClientEvent('DP-Boombox_v2:refreshPlaylistSongs', src, playlistId)

                                    -- ¡ÉXITO! Avisamos al menú JS para que cierre el modal
                                    TriggerClientEvent('DP-Boombox_v2:addSongResult', src, 'success')
                                end)
                        end
                    end)
            end
        end)
    end)
end)

-- ==========================================
-- 🌐 IMPORTAR PLAYLIST DESDE YOUTUBE (SIN DEADLOCKS)
-- ==========================================
RegisterServerEvent('DP-Boombox_v2:importYouTubePlaylist', function(data)
    local src = source
    local ytPlaylistId = data.ytPlaylistId
    local identifier = nil

    if Framework == "ESX" then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            identifier = xPlayer.identifier
        end
    elseif Framework == "qb" then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            identifier = Player.PlayerData.citizenid
        end
    end
    if not identifier then
        return
    end

    if not Config.YouTubeAPIKey or Config.YouTubeAPIKey == "" or Config.YouTubeAPIKey ==
        "PON_AQUI_TU_API_KEY_DE_YOUTUBE" then
        TriggerClientEvent('DP-Boombox_v2:notificar', src, 'error', 'El servidor no ha configurado la API de YouTube.')
        TriggerClientEvent('DP-Boombox_v2:ytImportResult', src, 'error')
        return
    end

    local urlPlaylistInfo = "https://www.googleapis.com/youtube/v3/playlists?part=snippet&id=" .. ytPlaylistId ..
                                "&key=" .. Config.YouTubeAPIKey

    PerformHttpRequest(urlPlaylistInfo, function(errInfo, textInfo, headersInfo)
        local nombreLista = "Importación YT (" .. string.sub(ytPlaylistId, 1, 5) .. ")"

        if errInfo == 200 then
            local resInfo = json.decode(textInfo)
            if resInfo and resInfo.items and #resInfo.items > 0 then
                nombreLista = string.sub(resInfo.items[1].snippet.title, 1, 50)
            end
        end

        local apiUrl = "https://www.googleapis.com/youtube/v3/playlistItems?part=snippet&maxResults=50&playlistId=" ..
                           ytPlaylistId .. "&key=" .. Config.YouTubeAPIKey

        PerformHttpRequest(apiUrl, function(err, text, headers)
            if err == 200 then
                local response = json.decode(text)

                if response and response.items and #response.items > 0 then
                    -- 🚨 CREAMOS UN THREAD PARA INSERTAR UNA A UNA Y EVITAR DEADLOCKS 🚨
                    CreateThread(function()
                        local newPlaylistId = MySQL.Sync.insert(
                            'INSERT INTO `dp_listas_repro` (`name`, `owner`, `share_code`) VALUES (@name, @owner, @code)',
                            {
                                ['@name'] = nombreLista,
                                ['@owner'] = identifier,
                                ['@code'] = "YT" .. math.random(10000, 99999)
                            })

                        local cancionesAgregadas = 0

                        for i = 1, #response.items do
                            local item = response.items[i].snippet
                            local title = string.sub(item.title, 1, 150)
                            local author = string.sub(item.videoOwnerChannelTitle or "YouTube", 1, 50)
                            local videoId = item.resourceId.videoId
                            local url = "https://www.youtube.com/watch?v=" .. videoId

                            if title ~= "Private video" and title ~= "Deleted video" then
                                MySQL.Sync.execute([[
                                    INSERT INTO dp_canciones (url, name, author, maxDuration) 
                                    VALUES (@url, @name, @author, 0)
                                    ON DUPLICATE KEY UPDATE name = @name, author = @author
                                ]], {
                                    ['@url'] = url,
                                    ['@name'] = title,
                                    ['@author'] = author
                                })

                                local res = MySQL.Sync.fetchAll('SELECT id FROM dp_canciones WHERE url = @url', {
                                    ['@url'] = url
                                })
                                if res and res[1] then
                                    MySQL.Sync.execute([[
                                        INSERT INTO dp_listas_canciones (playlist, song) 
                                        SELECT @playlist, @song 
                                        WHERE NOT EXISTS (
                                            SELECT 1 FROM dp_listas_canciones WHERE playlist = @playlist AND song = @song
                                        )
                                    ]], {
                                        ['@playlist'] = newPlaylistId,
                                        ['@song'] = res[1].id
                                    })
                                end
                                cancionesAgregadas = cancionesAgregadas + 1

                                -- 🚨 DAMOS UN RESPIRO A LA BASE DE DATOS (Milisegundos) 🚨
                                Wait(25)
                            end
                        end

                        TriggerClientEvent('DP-Boombox_v2:notificar', src, 'success',
                            'Importada: ' .. nombreLista .. ' (' .. cancionesAgregadas .. ' canciones)')
                        TriggerClientEvent('DP-Boombox_v2:refreshPlaylists', src)
                        TriggerClientEvent('DP-Boombox_v2:ytImportResult', src, 'success')
                    end)
                else
                    TriggerClientEvent('DP-Boombox_v2:notificar', src, 'error',
                        'La lista de YouTube está vacía o es privada.')
                    TriggerClientEvent('DP-Boombox_v2:ytImportResult', src, 'error')
                end
            else
                TriggerClientEvent('DP-Boombox_v2:notificar', src, 'error', 'Error al leer YouTube. Comprueba la URL.')
                TriggerClientEvent('DP-Boombox_v2:ytImportResult', src, 'error')
            end
        end, 'GET', '')
    end, 'GET', '')
end)

-- ==========================================
-- 🌐 INYECTAR YOUTUBE PLAYLIST A UNA LISTA EXISTENTE (SIN DEADLOCKS)
-- ==========================================
RegisterServerEvent('DP-Boombox_v2:importYouTubeToExistingPlaylist', function(data)
    local src = source
    local ytPlaylistId = data.ytPlaylistId
    local targetPlaylistId = data.playlistId
    local identifier = nil

    if Framework == "ESX" then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            identifier = xPlayer.identifier
        end
    elseif Framework == "qb" then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            identifier = Player.PlayerData.citizenid
        end
    end
    if not identifier then
        return
    end

    if not Config.YouTubeAPIKey or Config.YouTubeAPIKey == "" or Config.YouTubeAPIKey ==
        "PON_AQUI_TU_API_KEY_DE_YOUTUBE" then
        TriggerClientEvent('DP-Boombox_v2:notificar', src, 'error', 'El servidor no ha configurado la API de YouTube.')
        TriggerClientEvent('DP-Boombox_v2:ytImportToExistingResult', src, 'error')
        return
    end

    local apiUrl = "https://www.googleapis.com/youtube/v3/playlistItems?part=snippet&maxResults=50&playlistId=" ..
                       ytPlaylistId .. "&key=" .. Config.YouTubeAPIKey

    PerformHttpRequest(apiUrl, function(err, text, headers)
        if err == 200 then
            local response = json.decode(text)

            if response and response.items and #response.items > 0 then
                -- 🚨 CREAMOS UN THREAD PARA INSERTAR UNA A UNA Y EVITAR DEADLOCKS 🚨
                CreateThread(function()
                    local cancionesAgregadas = 0

                    for i = 1, #response.items do
                        local item = response.items[i].snippet
                        local title = string.sub(item.title, 1, 150)
                        local author = string.sub(item.videoOwnerChannelTitle or "YouTube", 1, 50)
                        local videoId = item.resourceId.videoId
                        local url = "https://www.youtube.com/watch?v=" .. videoId

                        if title ~= "Private video" and title ~= "Deleted video" then
                            MySQL.Sync.execute([[
                                INSERT INTO dp_canciones (url, name, author, maxDuration) 
                                VALUES (@url, @name, @author, 0)
                                ON DUPLICATE KEY UPDATE name = @name, author = @author
                            ]], {
                                ['@url'] = url,
                                ['@name'] = title,
                                ['@author'] = author
                            })

                            local res = MySQL.Sync.fetchAll('SELECT id FROM dp_canciones WHERE url = @url', {
                                ['@url'] = url
                            })
                            if res and res[1] then
                                MySQL.Sync.execute([[
                                    INSERT INTO dp_listas_canciones (playlist, song) 
                                    SELECT @playlist, @song 
                                    WHERE NOT EXISTS (
                                        SELECT 1 FROM dp_listas_canciones WHERE playlist = @playlist AND song = @song
                                    )
                                ]], {
                                    ['@playlist'] = targetPlaylistId,
                                    ['@song'] = res[1].id
                                })
                            end
                            cancionesAgregadas = cancionesAgregadas + 1

                            -- 🚨 DAMOS UN RESPIRO A LA BASE DE DATOS (Milisegundos) 🚨
                            Wait(25)
                        end
                    end

                    TriggerClientEvent('DP-Boombox_v2:notificar', src, 'success',
                        'Se han inyectado ' .. cancionesAgregadas .. ' canciones a tu lista.')
                    TriggerClientEvent('DP-Boombox_v2:refreshPlaylists', src)
                    TriggerClientEvent('DP-Boombox_v2:refreshPlaylistSongs', src, targetPlaylistId)
                    TriggerClientEvent('DP-Boombox_v2:ytImportToExistingResult', src, 'success')
                end)
            else
                TriggerClientEvent('DP-Boombox_v2:notificar', src, 'error',
                    'La lista de YouTube está vacía o es privada.')
                TriggerClientEvent('DP-Boombox_v2:ytImportToExistingResult', src, 'error')
            end
        else
            TriggerClientEvent('DP-Boombox_v2:notificar', src, 'error', 'Error al leer YouTube. Comprueba la URL.')
            TriggerClientEvent('DP-Boombox_v2:ytImportToExistingResult', src, 'error')
        end
    end, 'GET', '')
end)

-- ==========================================
-- 🗑️ ELIMINAR CANCIÓN DE UNA LISTA
-- ==========================================
RegisterServerEvent('DP-Boombox_v2:removeSongFromPlaylist', function(data)
    local src = source
    local songId = data.songId
    local playlistId = data.playlistId
    local identifier = nil

    -- Obtenemos el identificador del jugador (Seguridad)
    if Framework == "ESX" then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            identifier = xPlayer.identifier
        end
    elseif Framework == "qb" then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            identifier = Player.PlayerData.citizenid
        end
    end
    if not identifier then
        return
    end

    -- Borramos la relación de esa canción con esa lista específica
    MySQL.Async.execute('DELETE FROM dp_listas_canciones WHERE playlist = @playlist AND song = @song', {
        ['@playlist'] = playlistId,
        ['@song'] = songId
    }, function(rowsChanged)
        if rowsChanged > 0 then
            TriggerClientEvent('DP-Boombox_v2:notificar', src, 'success', 'Canción eliminada de la lista.')

            -- 1. Refrescamos las canciones que estás viendo abajo
            TriggerClientEvent('DP-Boombox_v2:refreshPlaylistSongs', src, playlistId)

            -- 2. Refrescamos tus listas de arriba (Por si el mosaico de imágenes ha cambiado)
            TriggerClientEvent('DP-Boombox_v2:refreshPlaylists', src)
        else
            TriggerClientEvent('DP-Boombox_v2:notificar', src, 'error', 'No se pudo eliminar la canción.')
        end
    end)
end)

-- ============================================
-- ⚙️ PREFERENCIAS DEL USUARIO (BASE DE DATOS)
-- ============================================

-- 1. Callback para OBTENER la preferencia al cargar el jugador
if Framework == "ESX" then
    ESX.RegisterServerCallback('DP-Boombox_v2:getMovePref', function(source, cb)
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            -- 🔒 FIX: Ahora lee de la columna específica del Boombox
            MySQL.Async.fetchScalar('SELECT boombox_move_open FROM dp_preferences WHERE citizenid = @id', {
                ['@id'] = xPlayer.identifier
            }, function(result)
                cb(result == 1) 
            end)
        else
            cb(false)
        end
    end)
elseif Framework == "qb" then
    QBCore.Functions.CreateCallback('DP-Boombox_v2:getMovePref', function(source, cb)
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            -- 🔒 FIX: Ahora lee de la columna específica del Boombox
            MySQL.Async.fetchScalar('SELECT boombox_move_open FROM dp_preferences WHERE citizenid = @id', {
                ['@id'] = Player.PlayerData.citizenid
            }, function(result)
                cb(result == 1)
            end)
        else
            cb(false)
        end
    end)
end

-- 2. Evento para GUARDAR la preferencia cuando el jugador le da al switch
RegisterNetEvent('DP-Boombox_v2:saveMovePref', function(status)
    local src = source
    local identifier = nil

    if Framework == "ESX" then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then identifier = xPlayer.identifier end
    elseif Framework == "qb" then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then identifier = Player.PlayerData.citizenid end
    end

    if not identifier then return end

    local valorInt = status and 1 or 0

    -- 🔒 FIX: Ahora guarda y actualiza en la columna específica del Boombox
    MySQL.Async.execute([[
        INSERT INTO dp_preferences (citizenid, boombox_move_open) 
        VALUES (@id, @valor) 
        ON DUPLICATE KEY UPDATE boombox_move_open = @valor
    ]], {
        ['@id'] = identifier,
        ['@valor'] = valorInt
    })
end)

-- ============================================
-- 💥 WIPE DE DATOS DE USUARIO (ZONA PELIGROSA)
-- ============================================
RegisterNetEvent('DP-Boombox_v2:wipeUserData')
AddEventHandler('DP-Boombox_v2:wipeUserData', function()
    local src = source
    local identifier = nil

    -- Obtenemos el identificador
    if Framework == "ESX" then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            identifier = xPlayer.identifier
        end
    elseif Framework == "qb" then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            identifier = Player.PlayerData.citizenid
        end
    end

    if not identifier then
        return
    end

    -- PASO 1: Encontrar todas las listas de las que este jugador es DUEÑO
    MySQL.Async.fetchAll('SELECT id FROM dp_listas_repro WHERE owner = @owner', {
        ['@owner'] = identifier
    }, function(misListas)

        -- PASO 2: Si tiene listas propias, las eliminamos completamente
        if misListas and #misListas > 0 then
            for _, lista in ipairs(misListas) do
                local listId = lista.id

                -- Borramos los permisos/miembros de esa lista
                MySQL.Async.execute('DELETE FROM dp_listas_jugadores WHERE playlist = @id', {
                    ['@id'] = listId
                })
                -- Borramos las canciones de esa lista
                MySQL.Async.execute('DELETE FROM dp_listas_canciones WHERE playlist = @id', {
                    ['@id'] = listId
                })
                -- Borramos la lista en sí
                MySQL.Async.execute('DELETE FROM dp_listas_repro WHERE id = @id', {
                    ['@id'] = listId
                })
            end
        end

        -- PASO 3: Sacar al jugador de cualquier otra lista en la que sea INVITADO
        MySQL.Async.execute('DELETE FROM dp_listas_jugadores WHERE license = @license', {
            ['@license'] = identifier
        }, function()

            -- PASO 4: Notificar y refrescar
            TriggerClientEvent('DP-Boombox_v2:notificar', src, 'success',
                'Todos tus datos y listas han sido eliminados.')

            -- Obligamos a su cliente a recargar las listas (que ahora estarán vacías)
            TriggerClientEvent('DP-Boombox_v2:refreshPlaylists', src)

            -- Y como extra de cortesía, avisamos a TODO EL SERVIDOR para que se les refresque 
            -- el menú si por casualidad estaban mirando una lista que acabas de borrar.
            TriggerClientEvent('DP-Boombox_v2:refreshPlaylists', -1)
        end)
    end)
end)
