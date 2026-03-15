local xSound = exports.xsound
radiosActivas = {}
Framework = nil
local MODELO_RADIO = GetHashKey('prop_boombox_01')
local ARMA_DESARMADO = GetHashKey('WEAPON_UNARMED')
uiAbierta = false
local tiempoBloqueo = {}

if GetResourceState('es_extended') == 'started' or GetResourceState('es_extended') == 'starting' then
    Framework = 'ESX'
    ESX = exports['es_extended']:getSharedObject()
elseif GetResourceState('qb-core') == 'started' or GetResourceState('qb-core') == 'starting' then
    Framework = 'qb'
    QBCore = exports['qb-core']:GetCoreObject()
end

-- ============================================
-- NUI CALLBACKS (COMUNICACIÓN VIVO)
-- ============================================

RegisterNUICallback('closeUI', function(_, cb)
    SetNuiFocus(false, false)

    -- EL TRUCO ESTÁ AQUÍ: Retrasamos el aviso de que el menú está cerrado
    -- para que el juego ignore la tecla ESCAPE que acabas de soltar.
    CreateThread(function()
        Wait(500) -- Esperamos medio segundo
        uiAbierta = false
    end)

    cb('ok')
end)

RegisterNUICallback('clickOption', function(data, cb)
    SetNuiFocus(false, false)
    if data.event then
        TriggerEvent(data.event, data.args)
    end
    cb('ok')
end)

-- Acción Dinámica (Reproducir / Pausar / Reanudar)
RegisterNUICallback('playerAction', function(data, cb)
    uiAbierta = true
    local idMusica = 'id_' .. data.id
    local distanciaFija = Config.Radios['speaker'].rango
    local myServerId = GetPlayerServerId(PlayerId()) -- 🚨 ARREGLO DE IDENTIDAD ÚNICA

    if data.action == "play" then
        if data.url and data.url ~= "" then
            TriggerServerEvent("DP-Boombox_v2:soundStatus", "play", idMusica, {
                position = radiosActivas[data.id].pos,
                link = data.url,
                volume = tonumber(data.volume) / 100,
                distance = distanciaFija + 0.0
            })
            radiosActivas[data.id].data = {
                estado = "reproduciendo",
                link = data.url,
                title = data.title,
                currentId = myServerId -- 🚨 AHORA ES ÚNICO PARA CADA JUGADOR EN EL SERVIDOR
            }
            TriggerServerEvent('DP-Boombox_v2:syncActive', radiosActivas)
        end
    elseif data.action == "pause" then
        TriggerServerEvent("DP-Boombox_v2:soundStatus", "pause", idMusica, {})
        if radiosActivas[data.id] then
            radiosActivas[data.id].data.estado = "pausado"
            TriggerServerEvent('DP-Boombox_v2:syncActive', radiosActivas)
        end
    elseif data.action == "resume" then
        TriggerServerEvent("DP-Boombox_v2:soundStatus", "resume", idMusica, {})
        if radiosActivas[data.id] then
            radiosActivas[data.id].data.estado = "reproduciendo"
            TriggerServerEvent('DP-Boombox_v2:syncActive', radiosActivas)
        end
    end
    cb('ok')
end)

-- Actualización de volumen en tiempo real al mover la barra
RegisterNUICallback('changeVolume', function(data, cb)
    local idMusica = 'id_' .. data.id
    TriggerServerEvent("DP-Boombox_v2:soundStatus", "volume", idMusica, {
        volumen = tonumber(data.volume) / 100
    })
    cb('ok')
end)

RegisterNUICallback('seekTime', function(data, cb)
    local idMusica = 'id_' .. data.id
    -- Enviamos la orden al servidor para que el salto de tiempo se sincronice con TODOS los jugadores
    TriggerServerEvent("DP-Boombox_v2:soundStatus", "seek", idMusica, {
        time = tonumber(data.time)
    })
    cb('ok')
end)

-- ============================================
-- EVENTOS CORE
-- ============================================

RegisterNetEvent('DP-Boombox_v2:useBoombox', function()
    local jugador = PlayerPedId()

    -- BLOQUEO POR DISTANCIA AL USAR EL ITEM
    local playerCoords = GetEntityCoords(jugador)
    -- Buscamos si hay radios en el suelo a menos de 10 metros (0 = no ignorar ninguna)
    if hayRadioCerca(playerCoords, 0, 10.0) then
        mandarNotificacion('Error', 'Ya hay otro altavoz cerca. Aléjate para colocar uno nuevo.', 'error')
        return -- Cortamos la función aquí para que no saque el altavoz
    end

    local hash = cargarModelo(MODELO_RADIO)
    local x, y, z = table.unpack(GetOffsetFromEntityInWorldCoords(jugador, 0.0, 3.0, 0.5))
    local radioEntidad = CreateObjectNoOffset(hash, x, y, z, true, false)

    SetModelAsNoLongerNeeded(hash)
    SetCurrentPedWeapon(jugador, ARMA_DESARMADO)
    AttachEntityToEntity(radioEntidad, jugador, GetPedBoneIndex(jugador, 57005), 0.32, 0, -0.05, 0.10, 270.0, 60.0,
        true, true, false, true, 1, true)
    equiparRadio(radioEntidad)
end)

RegisterNetEvent('DP-Boombox_v2:deleteObj', function(netId)
    local entidad = NetToObj(netId)
    if DoesEntityExist(entidad) then
        DeleteObject(entidad)
        if not DoesEntityExist(entidad) then
            TriggerServerEvent('DP-Boombox_v2:objDeleted')
        end
    end
end)

AddEventHandler('DP-Boombox_v2:recoger', function()
    local jugador = PlayerPedId()
    local coordsJugador = GetEntityCoords(jugador)
    local radioCercana = GetClosestObjectOfType(coordsJugador.x, coordsJugador.y, coordsJugador.z, 3.0, MODELO_RADIO,
        false, false, false)

    if radioCercana == 0 then
        return
    end

    local coordsRadio = GetEntityCoords(radioCercana)
    local idMusica = 'id_' .. radioCercana

    TaskTurnPedToFaceCoord(jugador, coordsRadio.x, coordsRadio.y, coordsRadio.z, 2000)
    TaskPlayAnim(jugador, "pickup_object", "pickup_low", 8.0, 8.0, -1, 50, 0, false, false, false)
    Wait(1000)

    if xSound:soundExists(idMusica) then
        TriggerServerEvent("DP-Boombox_v2:soundStatus", "stop", idMusica, {})
    end

    FreezeEntityPosition(radioCercana, false)
    TriggerServerEvent("DP-Boombox_v2:deleteObj", ObjToNet(radioCercana))

    if radiosActivas[radioCercana] then
        radiosActivas[radioCercana] = nil
    end
    TriggerServerEvent('DP-Boombox_v2:syncActive', radiosActivas)
    ClearPedTasks(jugador)
end)

RegisterNetEvent('DP-Boombox_v2:soundStatus', function(tipo, idMusica, datos)
    CreateThread(function()
        if tipo == "position" then
            if xSound:soundExists(idMusica) then
                xSound:Position(idMusica, datos.position)
            end
        elseif tipo == "play" then
            tiempoBloqueo[idMusica] = GetGameTimer() + 8000 -- Ponemos la venda de 8 segundos a xSound

            -- 🚨 FIX DEFINITIVO: DESTRUIR EL REPRODUCTOR VIEJO ANTES DE CREAR EL NUEVO
            -- Esto limpia la caché de xSound y obliga a que la nueva canción empiece 100% en el segundo 0
            if xSound:soundExists(idMusica) then
                xSound:Destroy(idMusica)
                Wait(50) -- Micro-pausa para asegurarnos de que se borre de la memoria de FiveM
            end

            xSound:PlayUrlPos(idMusica, datos.link, datos.volume, datos.position)
            xSound:Distance(idMusica, datos.distance)
            xSound:setVolume(idMusica, datos.volume)
        elseif tipo == "volume" then
            if xSound:soundExists(idMusica) then
                xSound:setVolume(idMusica, datos.volumen)
            end
        elseif tipo == "pause" then
            if xSound:soundExists(idMusica) then
                xSound:Pause(idMusica)
            end
        elseif tipo == "resume" then
            if xSound:soundExists(idMusica) then
                xSound:Resume(idMusica)
            end
        elseif tipo == "stop" then
            if xSound:soundExists(idMusica) then
                xSound:Destroy(idMusica)
            end
        elseif tipo == "seek" then
            if xSound:soundExists(idMusica) then
                xSound:setTimeStamp(idMusica, datos.time)
            end
        end
    end)
end)

RegisterNetEvent('DP-Boombox_v2:syncActive', function(radiosSincronizadas)
    radiosActivas = radiosSincronizadas
end)

RegisterNUICallback('createPlaylist', function(data, cb)
    -- data.name contiene el título que el usuario escribió
    TriggerServerEvent('DP-Boombox_v2:createPlaylist', data.name)
    cb('ok')
end)

RegisterNUICallback('joinPlaylist', function(data, cb)
    -- Le pasamos el código que escribió el usuario al servidor
    TriggerServerEvent('DP-Boombox_v2:joinPlaylist', data.code)
    cb('ok')
end)

-- Evento genérico para notificaciones
RegisterNetEvent('DP-Boombox_v2:notificar', function(tipo, mensaje)
    mandarNotificacion('ALTAVOZ', mensaje, tipo)
end)

-- Recibir la orden del servidor de refrescar las listas
RegisterNetEvent('DP-Boombox_v2:refreshPlaylists', function()
    if uiAbierta then
        SendNUIMessage({
            action = "requestPlaylistsRefresh"
        })
    end
end)

-- Recibimos las canciones del servidor y se las inyectamos al HTML
RegisterNetEvent('DP-Boombox_v2:loadPlaylistSongs', function(songs, playlistName)
    SendNUIMessage({
        action = "loadPlaylistSongs",
        songs = songs,
        playlistName = playlistName
    })
end)

-- NUI: El JS nos pide que le mandemos las playlists
RegisterNUICallback('getPlaylists', function(_, cb)
    if Framework == "ESX" then
        ESX.TriggerServerCallback('DP-Boombox_v2:fetchPlaylists', function(listas)
            SendNUIMessage({
                action = "loadPlaylists",
                data = listas
            })
        end)
    elseif Framework == "qb" then
        QBCore.Functions.TriggerCallback('DP-Boombox_v2:fetchPlaylists', function(listas)
            SendNUIMessage({
                action = "loadPlaylists",
                data = listas
            })
        end)
    end

    cb('ok') -- 🔓 ¡SOLUCIÓN! Lo sacamos fuera para liberar el JS instantáneamente
end)

RegisterNUICallback('getPlaylistDetails', function(data, cb)
    if Framework == "ESX" then
        ESX.TriggerServerCallback('DP-Boombox_v2:getPlaylistDetails', function(detalles)
            SendNUIMessage({
                action = "openEditModalData",
                data = detalles
            })
        end, data.id)
    elseif Framework == "qb" then
        QBCore.Functions.TriggerCallback('DP-Boombox_v2:getPlaylistDetails', function(detalles)
            SendNUIMessage({
                action = "openEditModalData",
                data = detalles
            })
        end, data.id)
    end
    cb('ok')
end)

RegisterNUICallback('savePlaylistEdit', function(data, cb)
    TriggerServerEvent('DP-Boombox_v2:savePlaylistEdit', data)
    cb('ok')
end)

-- El JS nos pide que busquemos las canciones de una lista
RegisterNUICallback('getPlaylistSongs', function(data, cb)
    TriggerServerEvent('DP-Boombox_v2:getPlaylistSongs', data)
    cb('ok')
end)

-- Obtener datos para el modal de borrado (Reutilizamos la petición de obtener miembros)
RegisterNUICallback('getPlaylistForDelete', function(data, cb)
    if Framework == "ESX" then
        ESX.TriggerServerCallback('DP-Boombox_v2:getPlaylistDetails', function(detalles)
            SendNUIMessage({
                action = "openDeleteModalData",
                data = detalles
            })
        end, data.id)
    elseif Framework == "qb" then
        QBCore.Functions.TriggerCallback('DP-Boombox_v2:getPlaylistDetails', function(detalles)
            SendNUIMessage({
                action = "openDeleteModalData",
                data = detalles
            })
        end, data.id)
    end
    cb('ok')
end)

RegisterNUICallback('leavePlaylist', function(data, cb)
    TriggerServerEvent('DP-Boombox_v2:leavePlaylist', data.id)
    cb('ok')
end)

RegisterNUICallback('deletePlaylist', function(data, cb)
    TriggerServerEvent('DP-Boombox_v2:deletePlaylist', data.id)
    cb('ok')
end)

RegisterNUICallback('transferPlaylist', function(data, cb)
    TriggerServerEvent('DP-Boombox_v2:transferPlaylist', data.id, data.newOwner)
    cb('ok')
end)

RegisterNUICallback('addSongToPlaylist', function(data, cb)
    TriggerServerEvent('DP-Boombox_v2:addSongToPlaylist', data)
    cb('ok')
end)

RegisterNetEvent('DP-Boombox_v2:refreshPlaylistSongs', function(playlistId)
    if uiAbierta then
        SendNUIMessage({
            action = "requestSongsRefresh",
            playlistId = playlistId
        })
    end
end)

RegisterNetEvent('DP-Boombox_v2:addSongResult', function(status)
    if uiAbierta then
        SendNUIMessage({
            action = "addSongResult",
            status = status
        })
    end
end)

RegisterNUICallback('importYouTubePlaylist', function(data, cb)
    TriggerServerEvent('DP-Boombox_v2:importYouTubePlaylist', data)
    cb('ok')
end)

RegisterNetEvent('DP-Boombox_v2:ytImportResult', function(status)
    if uiAbierta then
        SendNUIMessage({
            action = "ytImportResult",
            status = status
        })
    end
end)

RegisterNUICallback('importYouTubeToExistingPlaylist', function(data, cb)
    TriggerServerEvent('DP-Boombox_v2:importYouTubeToExistingPlaylist', data)
    cb('ok')
end)

RegisterNetEvent('DP-Boombox_v2:ytImportToExistingResult', function(status)
    if uiAbierta then
        SendNUIMessage({
            action = "ytImportToExistingResult",
            status = status
        })
    end
end)

RegisterNUICallback('removeSongFromPlaylist', function(data, cb)
    TriggerServerEvent('DP-Boombox_v2:removeSongFromPlaylist', data)
    cb('ok')
end)

-- ============================================
-- 🚨 AUTO-REPRODUCCIÓN Y CONTROL DE TIEMPO 🚨
-- ============================================
local cooldownFinCancion = {}

CreateThread(function()
    while true do
        Wait(500) -- Lo bajamos a 500ms para que sea el doble de rápido y fluido detectando el final

        local myServerId = GetPlayerServerId(PlayerId())

        for radioId, radioInfo in pairs(radiosActivas) do
            local idMusica = 'id_' .. radioId

            -- Si la radio existe en el mundo y está sonando ahora mismo
            if xSound:soundExists(idMusica) and xSound:isPlaying(idMusica) then

                -- EL CANDADO: Si acaba de empezar, ignoramos el código por 8 segundos
                if not tiempoBloqueo[idMusica] or GetGameTimer() > tiempoBloqueo[idMusica] then

                    local currentTime = xSound:getTimeStamp(idMusica)
                    local duration = xSound:getMaxDuration(idMusica)

                    -- Reducimos el margen a 1.5s para que apure más la canción antes de saltar
                    if duration and currentTime and duration > 10.0 and currentTime > 5.0 and currentTime >=
                        (duration - 1.5) then

                        -- Comprobamos que TÚ seas el que inició la canción
                        if radioInfo.data and radioInfo.data.currentId == myServerId then

                            -- 🎁 FIX: Si no está en enfriamiento, mandamos la orden
                            if not cooldownFinCancion[idMusica] or GetGameTimer() > cooldownFinCancion[idMusica] then
                                cooldownFinCancion[idMusica] = GetGameTimer() + 5000 -- Bloqueamos esta radio 5 segs para no spamear

                                SendNUIMessage({
                                    action = "songEnded"
                                })
                            end
                        end

                    end
                end
            end
        end
    end
end)

-- ============================================
-- 🔄 SINCRONIZADOR DE LA BARRA DE PROGRESO 🔄
-- ============================================
CreateThread(function()
    while true do
        Wait(250) -- 🚨 Acelerado al DOBLE (4 veces por segundo) para máxima fluidez

        -- Solo gasta recursos si tienes el menú abierto
        if uiAbierta then
            for radioId, radioInfo in pairs(radiosActivas) do
                local idMusica = 'id_' .. radioId

                -- Buscamos si la radio está cerca y sonando
                if xSound:soundExists(idMusica) and xSound:isPlaying(idMusica) then
                    local currentPos = xSound:getTimeStamp(idMusica)
                    local maxDur = xSound:getMaxDuration(idMusica)

                    -- Enviamos los datos reales al JavaScript
                    SendNUIMessage({
                        action = "updateTime",
                        radioId = radioId,
                        currentTime = currentPos,
                        duration = maxDur
                    })
                end
            end
        else
            Wait(1000) -- Si el menú está cerrado, descansa para no consumir recursos
        end
    end
end)

-- ============================================
-- LIMPIEZA TOTAL AL REINICIAR (STOP/RESTART)
-- ============================================
AddEventHandler('onResourceStop', function(resourceName)
    -- Solo actuamos si el script que se detiene es este
    if GetCurrentResourceName() ~= resourceName then
        return
    end

    -- 1. DETENER TODA LA MÚSICA
    -- Recorremos las radios que el cliente conoce
    for radioId, _ in pairs(radiosActivas) do
        local idMusica = 'id_' .. radioId
        if xSound:soundExists(idMusica) then
            xSound:Destroy(idMusica) -- Esto mata el sonido en seco
        end
    end

    -- 2. BORRAR OBJETOS (PROPS) DEL SUELO
    local objetosDelMundo = GetGamePool('CObject')
    for _, entidad in ipairs(objetosDelMundo) do
        if GetEntityModel(entidad) == MODELO_RADIO then
            DeleteEntity(entidad)
        end
    end

    -- 3. OCULTAR UI PARA EVITAR TEXTOS PEGADOS
    exports['DP-TextUI']:OcultarUI()
end)
