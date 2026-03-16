local xSound = exports.xsound
radiosActivas = {}
Framework = nil
local MODELO_RADIO = GetHashKey('prop_boombox_01')
local ARMA_DESARMADO = GetHashKey('WEAPON_UNARMED')
uiAbierta = false
local tiempoBloqueo = {}
local moveWhileOpen = false
radioMenuAbierto = nil
local isTyping = false

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
    radioMenuAbierto = nil

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

RegisterNUICallback('updateMovePref', function(data, cb)
    moveWhileOpen = data.status
    TriggerServerEvent('DP-Boombox_v2:saveMovePref', data.status) -- 💾 MANDA A GUARDAR A LA BD
    cb('ok')
end)

RegisterNUICallback('saveBoomboxPos', function(data, cb)
    -- Le pasamos directamente el objeto 'data' (que contiene top y left) al servidor
    TriggerServerEvent('DP-Boombox_v2:saveBoomboxPos', data)
    cb('ok')
end)

RegisterNUICallback('setTypingFocus', function(data, cb)
    isTyping = data.isTyping
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

RegisterNetEvent('DP-Boombox_v2:useBoombox', function(nombreItem)
    local jugador = PlayerPedId()

    -- BLOQUEO EN VEHÍCULOS
    if IsPedInAnyVehicle(jugador, false) then
        mandarNotificacion('Error', '¡No puedes utilizar este ítem dentro de un vehículo!', 'error')
        return -- Cortamos aquí. El ítem no se borra, sigue en tu inventario.
    end

    -- BLOQUEO POR DISTANCIA AL USAR EL ITEM
    local playerCoords = GetEntityCoords(jugador)
    -- Buscamos si hay radios en el suelo a menos de 10 metros
    if hayRadioCerca(playerCoords, 0, 10.0) then
        mandarNotificacion('Error', 'Ya hay otro altavoz cerca. Aléjate para colocar uno nuevo.', 'error')
        return -- Cortamos aquí. El ítem no se borra.
    end

    -- ✅ TODO ESTÁ CORRECTO: AHORA SÍ LE DECIMOS AL SERVIDOR QUE LO BORRE
    TriggerServerEvent('DP-Boombox_v2:removeItem', nombreItem)

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
    local obj = NetworkGetEntityFromNetworkId(netId)

    if obj and DoesEntityExist(obj) then
        -- Pedimos permiso a FiveM para tomar el control de este objeto (por si lo puso otro)
        NetworkRequestControlOfEntity(obj)

        local timeout = 0
        -- Esperamos hasta medio segundo para que FiveM nos ceda el control
        while not NetworkHasControlOfEntity(obj) and timeout < 50 do
            Wait(10)
            timeout = timeout + 1
        end

        -- Una vez tenemos el control (o si ya lo teníamos), lo destruimos
        if NetworkHasControlOfEntity(obj) then
            DeleteEntity(obj)
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
    SendNUIMessage({
        action = "refreshPlaylists"
    })
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
    -- Quitamos el 'if uiAbierta' para que reciba la señal siempre.
    -- El JavaScript se encargará de decidir si necesita redibujar la pantalla o no.
    SendNUIMessage({
        action = "forceRefreshSongs",
        playlistId = playlistId
    })
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

RegisterNUICallback('wipeUserData', function(_, cb)
    TriggerServerEvent('DP-Boombox_v2:wipeUserData')
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
-- 🏃‍♂️ SISTEMA DE MOVIMIENTO CON UI ABIERTA
-- ============================================
CreateThread(function()
    local inputMantenido = false

    while true do
        if uiAbierta then
            -- 1. Evaluamos si debemos permitir que el juego lea el teclado (NO si estamos escribiendo)
            local deberiaMantenerInput = not isTyping

            -- Encendemos o apagamos la "magia" dinámicamente
            if inputMantenido ~= deberiaMantenerInput then
                SetNuiFocusKeepInput(deberiaMantenerInput)
                inputMantenido = deberiaMantenerInput
            end

            -- 2. BLOQUEOS (Solo necesarios si el juego ESTÁ leyendo el teclado)
            if deberiaMantenerInput then
                DisableControlAction(0, 1, true) -- Cámara Derecha/Izquierda
                DisableControlAction(0, 2, true) -- Cámara Arriba/Abajo
                DisableControlAction(0, 24, true) -- Atacar (Click Izquierdo)
                DisableControlAction(0, 25, true) -- Apuntar (Click Derecho)
                DisableControlAction(0, 37, true) -- Rueda de armas (TAB)
                DisableControlAction(0, 200, true) -- ESC
                DisablePlayerFiring(PlayerPedId(), true)

                -- Si el switch de "Moverme" está apagado, bloqueamos las teclas de movimiento
                if not moveWhileOpen then
                    DisableControlAction(0, 30, true) -- A/D
                    DisableControlAction(0, 31, true) -- W/S
                    DisableControlAction(0, 21, true) -- Sprint
                    DisableControlAction(0, 22, true) -- Salto
                    DisableControlAction(0, 36, true) -- Agacharse
                end
            else
                -- Si estamos escribiendo, el juego ya ignora el teclado automáticamente, 
                -- pero forzamos el bloqueo de la tecla ESC por seguridad para no abrir el menú de pausa.
                DisableControlAction(0, 200, true)
            end

            Wait(0)
        else
            -- Si cerramos la UI, restauramos todo a la normalidad
            if inputMantenido then
                SetNuiFocusKeepInput(false)
                inputMantenido = false
            end
            Wait(250)
        end
    end
end)

-- ============================================
-- 📏 VIGILANTE DE DISTANCIA (AUTO-CIERRE)
-- ============================================
CreateThread(function()
    while true do
        local sleep = 1000

        -- Solo gasta recursos si tienes un menú abierto
        if uiAbierta and radioMenuAbierto then
            sleep = 500 -- Revisamos cada medio segundo

            -- 1. Comprobamos si el altavoz sigue existiendo en el mundo
            if DoesEntityExist(radioMenuAbierto) then
                local playerCoords = GetEntityCoords(PlayerPedId())
                local radioCoords = GetEntityCoords(radioMenuAbierto)
                local distancia = #(playerCoords - radioCoords)

                -- 2. Límite de distancia: 5.0 metros
                if distancia > 5.0 then
                    SendNUIMessage({
                        action = "close"
                    }) -- Ordenamos al JS cerrar la animación
                    SetNuiFocus(false, false)
                    uiAbierta = false
                    radioMenuAbierto = nil
                    mandarNotificacion('Error', 'Te has alejado demasiado del altavoz.', 'error')
                end
            else
                -- 3. Si el altavoz fue borrado (alguien lo guardó o un admin lo limpió)
                SendNUIMessage({
                    action = "close"
                })
                SetNuiFocus(false, false)
                uiAbierta = false
                radioMenuAbierto = nil
                mandarNotificacion('Error', 'El altavoz ha desaparecido.', 'error')
            end
        end

        Wait(sleep)
    end
end)

-- ============================================
-- 🔄 CARGAR PREFERENCIAS DESDE LA BD
-- ============================================
local function CargarPreferenciasDB()
    if Framework == "ESX" then
        ESX.TriggerServerCallback('DP-Boombox_v2:getMovePref', function(pref)
            moveWhileOpen = pref
            SendNUIMessage({
                action = "updateMovePrefUI",
                status = moveWhileOpen
            })
        end)
    elseif Framework == "qb" then
        QBCore.Functions.TriggerCallback('DP-Boombox_v2:getMovePref', function(pref)
            moveWhileOpen = pref
            SendNUIMessage({
                action = "updateMovePrefUI",
                status = moveWhileOpen
            })
        end)
    end
end

-- ============================================
-- 🔄 CARGAR PREFERENCIAS DESDE LA BD
-- ============================================
local function CargarPreferenciasDB()
    if Framework == "ESX" then
        ESX.TriggerServerCallback('DP-Boombox_v2:getMovePref', function(pref)
            moveWhileOpen = pref
            SendNUIMessage({
                action = "updateMovePrefUI",
                status = moveWhileOpen
            })
        end)
    elseif Framework == "qb" then
        QBCore.Functions.TriggerCallback('DP-Boombox_v2:getMovePref', function(pref)
            moveWhileOpen = pref
            SendNUIMessage({
                action = "updateMovePrefUI",
                status = moveWhileOpen
            })
        end)
    end
end

-- 🪄 NUEVA: Función para cargar la posición del panel
local function CargarPosicionDB()
    if Framework == "ESX" then
        ESX.TriggerServerCallback('DP-Boombox_v2:getBoomboxPos', function(pos)
            if pos and pos.top and pos.left then
                SendNUIMessage({
                    action = "loadBoomboxPos",
                    top = pos.top,
                    left = pos.left
                })
            end
        end)
    elseif Framework == "qb" then
        QBCore.Functions.TriggerCallback('DP-Boombox_v2:getBoomboxPos', function(pos)
            if pos and pos.top and pos.left then
                SendNUIMessage({
                    action = "loadBoomboxPos",
                    top = pos.top,
                    left = pos.left
                })
            end
        end)
    end
end

-- Cuando el jugador carga en el servidor por primera vez
RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function()
    Wait(3000)
    CargarPreferenciasDB()
    CargarPosicionDB() -- 👈 Añadido
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(3000)
    CargarPreferenciasDB()
    CargarPosicionDB() -- 👈 Añadido
end)

-- Por si reinicias el script mientras estás dentro probando cosas
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        Wait(2000)
        CargarPreferenciasDB()
        CargarPosicionDB() -- 👈 Añadido
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

-- ============================================
-- 🚗 SISTEMA DE RADIO PARA VEHÍCULOS
-- ============================================

-- 1. Evento para instalar la radio (Se llama desde el server al usar el ítem 'vehicle_radio')
RegisterNetEvent('DP-Boombox_v2:installCarRadio', function()
    local ped = PlayerPedId()

    if not IsPedInAnyVehicle(ped, false) then
        mandarNotificacion('Error', 'Debes estar sentado dentro de un vehículo para instalar la radio.', 'error')
        return
    end

    local veh = GetVehiclePedIsIn(ped, false)
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then
        return
    end

    -- Limpiamos los espacios en blanco de la matrícula por seguridad para la Base de Datos
    plate = string.gsub(plate, "^%s*(.-)%s*$", "%1")

    -- Preguntamos al servidor si este coche ya tiene radio instalada
    if Framework == "ESX" then
        ESX.TriggerServerCallback('DP-Boombox_v2:checkCarRadio', function(hasRadio)
            if hasRadio then
                mandarNotificacion('Error', 'Este vehículo ya tiene un sistema de sonido instalado.', 'error')
            else
                IniciarInstalacionRadio(veh, plate)
            end
        end, plate)
    elseif Framework == "qb" then
        QBCore.Functions.TriggerCallback('DP-Boombox_v2:checkCarRadio', function(hasRadio)
            if hasRadio then
                mandarNotificacion('Error', 'Este vehículo ya tiene un sistema de sonido instalado.', 'error')
            else
                IniciarInstalacionRadio(veh, plate)
            end
        end, plate)
    end
end)

-- 2. Función de la Barra de Progreso y Animación
function IniciarInstalacionRadio(veh, plate)
    local ped = PlayerPedId()
    local animDict = Config.CarRadio.AnimDict or "mini@repair"
    local animName = Config.CarRadio.AnimName or "fixing_a_ped"
    local installTime = Config.CarRadio.InstallTime or 7500

    while not HasAnimDictLoaded(animDict) do
        Wait(10)
        RequestAnimDict(animDict)
    end
    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 49, 0, false, false, false)

    local function InstalacionCompletada()
        ClearPedTasks(ped)
        -- Le decimos al servidor que guarde la matrícula y nos quite el ítem
        TriggerServerEvent('DP-Boombox_v2:carRadioInstalled', plate)
        mandarNotificacion('Éxito', 'Has instalado la radio en el vehículo.', 'success')

        -- Le avisamos al inventario al instante para que encienda el botón
        TriggerEvent('DP-Inventory:client:UpdateVehicleRadio', true)
    end

    local function InstalacionCancelada()
        ClearPedTasks(ped)
        mandarNotificacion('Error', 'Instalación cancelada.', 'error')
    end

    -- Ejecutamos la barra de progreso correspondiente
    if Framework == "qb" then
        QBCore.Functions.Progressbar("install_radio", "Instalando sistema de sonido...", installTime, false, true, {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true
        }, {}, {}, {}, InstalacionCompletada, InstalacionCancelada)
    elseif Framework == "ESX" then
        -- Usamos el export estándar 'progressbar'. Si tu server ESX usa ox_lib, avísame y te lo adapto a lib.progressBar
        exports['progressbar']:Progress({
            name = "install_radio",
            duration = installTime,
            label = "Instalando sistema de sonido...",
            useWhileDead = false,
            canCancel = true,
            controlDisables = {
                disableMovement = true,
                disableCarMovement = true,
                disableCombat = true
            }
        }, function(cancelled)
            if not cancelled then
                InstalacionCompletada()
            else
                InstalacionCancelada()
            end
        end)
    end
end

-- 3. Comando y Export para ABRIR la radio
RegisterCommand(Config.CarRadio.Command, function()
    AbrirRadioVehiculo()
end)
exports('OpenCarRadio', function()
    AbrirRadioVehiculo()
end)

function AbrirRadioVehiculo()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        mandarNotificacion('Error', 'Debes estar dentro de un vehículo para usar la radio.', 'error')
        return
    end

    local veh = GetVehiclePedIsIn(ped, false)
    local plate = GetVehicleNumberPlateText(veh)
    plate = string.gsub(plate, "^%s*(.-)%s*$", "%1")

    -- Verificamos si tiene radio antes de abrir el panel
    if Framework == "ESX" then
        ESX.TriggerServerCallback('DP-Boombox_v2:checkCarRadio', function(hasRadio)
            if hasRadio then
                abrirMenuRadioVehiculo(veh, plate)
            else
                mandarNotificacion('Error', 'Este vehículo no tiene radio instalada.', 'error')
            end
        end, plate)
    elseif Framework == "qb" then
        QBCore.Functions.TriggerCallback('DP-Boombox_v2:checkCarRadio', function(hasRadio)
            if hasRadio then
                abrirMenuRadioVehiculo(veh, plate)
            else
                mandarNotificacion('Error', 'Este vehículo no tiene radio instalada.', 'error')
            end
        end, plate)
    end
end

-- 4. Adaptación del Menú para Coches (Usa la matrícula como ID en lugar del número de entidad)
function abrirMenuRadioVehiculo(veh, plate)
    uiAbierta = true
    radioMenuAbierto = veh
    local radioId = "veh_" .. plate

    if not radiosActivas[radioId] then
        radiosActivas[radioId] = {
            pos = GetEntityCoords(veh),
            isVehicle = true,
            entity = veh,
            data = {
                estado = "detenido",
                link = "",
                title = nil
            }
        }
    else
        radiosActivas[radioId].pos = GetEntityCoords(veh)
        radiosActivas[radioId].entity = veh
    end
    TriggerServerEvent('DP-Boombox_v2:syncActive', radiosActivas)

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openPlayer",
        id = radioId,
        estado = radiosActivas[radioId].data.estado,
        link = radiosActivas[radioId].data.link,
        title = radiosActivas[radioId].data.title
    })
end

-- 5. Bucle para actualizar la posición 3D de la música mientras el coche conduce
CreateThread(function()
    while true do
        Wait(200) -- Se actualiza 5 veces por segundo
        for radioId, info in pairs(radiosActivas) do
            if info.isVehicle and info.entity and DoesEntityExist(info.entity) then
                local coords = GetEntityCoords(info.entity)
                local idMusica = 'id_' .. radioId
                if exports.xsound:soundExists(idMusica) and exports.xsound:isPlaying(idMusica) then
                    exports.xsound:Position(idMusica, coords)
                end
            end
        end
    end
end)
