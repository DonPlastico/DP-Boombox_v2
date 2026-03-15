local MODELO_RADIO = GetHashKey('prop_boombox_01')

cargarModelo = function(modelo)
    while not HasModelLoaded(modelo) do
        Wait(0)
        RequestModel(modelo)
    end
    return modelo
end

mandarNotificacion = function(titulo, descripcion, tipo)
    local mensaje = descripcion
    tipo = tipo or "success"

    if Framework == "ESX" then
        ESX.ShowNotification(mensaje)
    elseif Framework == "qb" then
        QBCore.Functions.Notify(mensaje, tipo, 5000)
    end
end

-- ==========================================
-- 📡 NUEVO: RADAR DE ALTAVOCES CERCANOS
-- ==========================================
hayRadioCerca = function(coords, entityIgnore, radioMax)
    local objetos = GetGamePool('CObject')
    for _, obj in ipairs(objetos) do
        if GetEntityModel(obj) == MODELO_RADIO and obj ~= entityIgnore then
            local objCoords = GetEntityCoords(obj)
            -- Si la distancia es menor o igual al radio máximo, hay un altavoz cerca
            if #(coords - objCoords) <= radioMax then
                return true
            end
        end
    end
    return false
end

-- ==========================================
-- REEMPLAZA TU FUNCIÓN equiparRadio POR ESTA
-- ==========================================
equiparRadio = function(radioEntidad)
    local equipada = true
    CreateThread(function()
        local uiMostrada = false -- Lo controlamos dinámicamente

        while equipada do
            Wait(0)

            local playerCoords = GetEntityCoords(PlayerPedId())
            -- Comprobamos si hay otro altavoz a menos de 10.0 metros (ignorando el que llevamos en la mano)
            local cercaDeOtra = hayRadioCerca(playerCoords, radioEntidad, 10.0)

            -- 🔄 CONTROL DINÁMICO DE LA UI (Aparece y desaparece al caminar)
            if cercaDeOtra and uiMostrada then
                exports['DP-TextUI']:OcultarUI('radio_soltar')
                uiMostrada = false
            elseif not cercaDeOtra and not uiMostrada then
                exports['DP-TextUI']:MostrarUI('radio_soltar', 'Soltar radio en el suelo', 'E', false)
                uiMostrada = true
            end

            -- FIX: Usamos Pressed en lugar de Released + CONDICIÓN DE DISTANCIA
            -- Solo te deja soltarla si NO estás cerca de otra
            if IsControlJustPressed(0, 38) and not cercaDeOtra then
                equipada = false
                if uiMostrada then
                    exports['DP-TextUI']:OcultarUI('radio_soltar')
                end

                DetachEntity(radioEntidad)
                PlaceObjectOnGroundProperly(radioEntidad)
                FreezeEntityPosition(radioEntidad, true)

                if radiosActivas[radioEntidad] and
                    (radiosActivas[radioEntidad].data.estado == "reproduciendo" or
                        radiosActivas[radioEntidad].data.estado == "pausado") then
                    TriggerServerEvent('DP-Boombox_v2:syncActive', radiosActivas)
                end
            end

            -- GUARDAR EN INVENTARIO (La G siempre funciona, sin importar la distancia)
            if IsControlJustPressed(0, 47) then
                equipada = false
                if uiMostrada then
                    exports['DP-TextUI']:OcultarUI('radio_soltar')
                end

                DeleteEntity(radioEntidad)
                if Framework == "ESX" then
                    TriggerServerEvent('DP-Boombox_v2:giveItem', 'speaker')
                elseif Framework == "qb" then
                    TriggerServerEvent('DP-Boombox_v2:giveItem', 'boombox')
                end

                if radiosActivas[radioEntidad] then
                    TriggerServerEvent('DP-Boombox_v2:stopMusic', radioEntidad)
                end
            end
        end
    end)
end

CreateThread(function()
    local enZona = false
    local textosActivos = {}
    local radioObjetivo = 0 -- Variable para guardar el altavoz y no buscarlo en cada frame

    while true do
        local tiempoEspera = 500
        local jugador = PlayerPedId()
        local coordsJugador = GetEntityCoords(jugador)

        -- 1. OPTIMIZACIÓN EXTREMA: Solo buscamos el objeto pesado cada 500ms si no estamos ya en zona
        if not enZona then
            radioObjetivo = GetClosestObjectOfType(coordsJugador.x, coordsJugador.y, coordsJugador.z, 3.0, MODELO_RADIO,
                false, false, false)
        end

        -- 2. Si tenemos un altavoz válido a la vista
        if radioObjetivo ~= 0 and DoesEntityExist(radioObjetivo) and not IsEntityAttachedToAnyPed(radioObjetivo) then
            local coordsRadio = GetEntityCoords(radioObjetivo)
            local distancia = #(coordsJugador - coordsRadio) -- Cálculo matemático súper ligero

            -- Si estamos a menos de 3 metros, activamos la lógica de teclas
            if distancia <= 3.0 then

                if uiAbierta then
                    tiempoEspera = 250 -- Si la UI está abierta, no necesitamos teclas, bajamos el ritmo

                    if enZona then
                        for _, id in ipairs(textosActivos) do
                            exports['DP-TextUI']:OcultarUI(id)
                        end
                        textosActivos = {}
                        enZona = false
                    end

                    -- Actualización de la barra de progreso
                    local idMusica = 'id_' .. radioObjetivo
                    if exports.xsound:soundExists(idMusica) then
                        SendNUIMessage({
                            action = "updateTime",
                            currentTime = exports.xsound:getTimeStamp(idMusica),
                            duration = exports.xsound:getMaxDuration(idMusica)
                        })
                    end
                else
                    tiempoEspera = 0 -- Bucle rápido SOLO para escuchar las teclas

                    -- MENÚ CERRADO: Mostramos TextUI y esperamos teclas
                    if not enZona then
                        exports['DP-TextUI']:MostrarUI('radio_interactuar', 'Acceder al altavoz', 'E', false)
                        exports['DP-TextUI']:MostrarUI('radio_coger', 'Cogerlo', 'K', false)
                        exports['DP-TextUI']:MostrarUI('radio_recoger', 'Recoger', 'G', false) -- 🚨 CAMBIADO A G
                        textosActivos = {'radio_interactuar', 'radio_coger', 'radio_recoger'}
                        enZona = true
                    end

                    -- Detección de teclas
                    if IsControlJustPressed(0, 38) then -- TECLA E
                        abrirMenuRadio(radioObjetivo, coordsRadio)

                    elseif IsControlJustPressed(0, 311) then -- TECLA K
                        for _, id in ipairs(textosActivos) do
                            exports['DP-TextUI']:OcultarUI(id)
                        end
                        textosActivos = {}
                        enZona = false
                        FreezeEntityPosition(radioObjetivo, false)
                        AttachEntityToEntity(radioObjetivo, jugador, GetPedBoneIndex(jugador, 57005), 0.32, 0, -0.05,
                            0.10, 270.0, 60.0, true, true, false, true, 1, true)
                        equiparRadio(radioObjetivo)
                        radioObjetivo = 0

                    elseif IsControlJustPressed(0, 47) then -- 🚨 TECLA G (Control 47)
                        -- Al ser la tecla G, ya no necesitamos ningún filtro anti-escape mágico
                        if not IsPauseMenuActive() then
                            TriggerEvent('DP-Boombox_v2:recoger')
                            Wait(2000)
                            radioObjetivo = 0
                        end
                    end
                end
            else
                -- Si nos alejamos a más de 3 metros, borramos todo y volvemos a descansar (500ms)
                if enZona then
                    for _, id in ipairs(textosActivos) do
                        exports['DP-TextUI']:OcultarUI(id)
                    end
                    textosActivos = {}
                    enZona = false
                end
                radioObjetivo = 0
            end
        else
            -- Si el altavoz desaparece (lo recogen o lo borran)
            if enZona then
                for _, id in ipairs(textosActivos) do
                    exports['DP-TextUI']:OcultarUI(id)
                end
                textosActivos = {}
                enZona = false
            end
            radioObjetivo = 0
        end

        Wait(tiempoEspera)
    end
end)

abrirMenuRadio = function(radio, coordsRadio)
    -- Avisamos al script que hemos abierto el menú para bloquear las teclas
    uiAbierta = true
    radioMenuAbierto = radio -- Guardamos la entidad del altavoz actual

    if not radiosActivas[radio] then
        radiosActivas[radio] = {
            pos = coordsRadio,
            data = {
                estado = "detenido",
                link = "",
                title = nil
            }
        }
    else
        radiosActivas[radio].pos = coordsRadio
    end
    TriggerServerEvent('DP-Boombox_v2:syncActive', radiosActivas)

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openPlayer",
        id = radio,
        estado = radiosActivas[radio].data.estado,
        link = radiosActivas[radio].data.link,
        title = radiosActivas[radio].data.title
    })
end
