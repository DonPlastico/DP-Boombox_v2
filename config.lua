Config = {}

-- ==========================================
-- CONFIGURACIÓN DE YOUTUBE API
-- ==========================================
-- Necesario para importar listas de reproducción enteras.
-- Consíguela gratis en: https://console.cloud.google.com/
-- Si se deja por defecto, el botón del menú dará un aviso al jugador.
Config.YouTubeAPIKey = "AIzaSyDA6BFjxaSrC9tIEZMmpAO4vMpFqfx4rcc"
-- Config.YouTubeAPIKey = "PON_AQUI_TU_API_KEY_DE_YOUTUBE"

-- Configuración de las radios. 
-- Descomenta o añade más en el futuro con diferentes rangos de sonido.
Config.Radios = {
    ['speaker'] = {
        rango = 25
    }

    -- ['pruebas'] = {
    --     rango = 50
    -- },

    -- ['pruebas_2'] = {
    --     rango = 150
    -- }
}

-- Configuración de radio para coche
Config.CarRadio = {
    ItemInstall = 'vehicle_radio', -- El nombre del ítem que acabamos de crear en qb-core
    Command = 'carradio', -- El comando para abrir el menú estando dentro
    InstallTime = 7500, -- Tiempo de la barra de progreso al instalar (en milisegundos)
    VolumeMax = 100, -- Volumen máximo permitido
    Distance = 25.0, -- Rango máximo al que se escuchará el coche desde fuera

    -- Configuraciones de animaciones al instalar
    AnimDict = "mini@repair",
    AnimName = "fixing_a_ped"
}
