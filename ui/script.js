// ==========================================
// 1. VARIABLES GLOBALES
// ==========================================
let currentRadioId = null;
let currentState = "detenido";
let currentPlayingUrl = "";
let isDraggingProgress = false;
let isBufferingNewSong = false;
let bufferingTimeout;
let isLoopEnabled = localStorage.getItem('DPBoombox_Loop') === 'true';
let isLoopSingleEnabled = localStorage.getItem('DPBoombox_LoopSingle') === 'true';
let isShuffleEnabled = localStorage.getItem('DPBoombox_Shuffle') === 'true';
let shuffleQueue = []; // Almacena el orden aleatorio matemático
let currentShuffleIndex = -1; // Por dónde vamos en la cola aleatoria
let isAutoChangingSong = false;
let moveWhileOpen = false; // Ahora se controla desde la BD


// ==========================================
// 2. RECEPCIÓN DE MENSAJES UNIFICADA (LUA -> JS)
// ==========================================
window.addEventListener('message', function (event) {
    const data = event.data;

    switch (data.action) {
        case "openPlayer":
            openPlayer(data);
            break;

        case "close":
            closeUI();
            break;

        case "ytImportResult":
            if (data.status === "success") {
                document.getElementById('modal-overlay').style.display = 'none';
            } else {
                const btn = document.getElementById('btn-confirm-yt-import');
                if (btn) {
                    btn.innerText = "ERROR (Lista privada o API mal)";
                    btn.style.background = "var(--danger)";
                }
            }
            break;

        case "ytImportToExistingResult":
            if (data.status === "success") {
                document.getElementById('modal-overlay').style.display = 'none';
            } else {
                const btn = document.getElementById('btn-confirm-yt-import-existing');
                if (btn) {
                    btn.innerText = "ERROR (Lista privada o vacía)";
                    btn.style.background = "var(--danger)";
                }
            }
            break;

        case "updateTime":
            // 🔒 FIX: Comprobamos que el tiempo que nos llega es EXCLUSIVAMENTE del altavoz que tenemos abierto
            if (data.radioId == currentRadioId) {
                updateProgressBar(data);
            }
            break;

        case "loadPlaylists":
            renderPlaylists(data.data);
            break;

        case "requestPlaylistsRefresh":
            fetchToLua('getPlaylists');
            break;

        case "openEditModalData":
            renderEditModal(data.data);
            break;

        case "openDeleteModalData":
            renderDeleteModal(data.data);
            break;

        case "loadPlaylistSongs":
            renderSongsList(data.songs, data.playlistName);
            break;

        case "requestSongsRefresh":
            if (currentSelectedPlaylistId === data.playlistId) {
                fetchToLua('getPlaylistSongs', { playlistId: data.playlistId });
            }
            break;

        case "addSongResult":
            handleAddSongResult(data.status);
            break;

        case "songEnded":
            playNextSong(true);
            break;

        case "updateMovePrefUI":
            moveWhileOpen = data.status;
            const moveSwitch = document.getElementById('setting-move-ped');
            if (moveSwitch) {
                moveSwitch.checked = moveWhileOpen;
            }
            break;
    }
});

// Helper genérico para mandar eventos a Lua
function fetchToLua(endpoint, bodyData = {}) {
    fetch(`https://${GetParentResourceName()}/${endpoint}`, {
        method: 'POST',
        body: JSON.stringify(bodyData)
    });
}

// ==========================================
// 3. CORE & REPRODUCTOR
// ==========================================
function closeUI() {
    // Cerramos cualquier modal o dropdown abierto al cerrar la UI
    document.getElementById('modal-overlay').style.display = 'none';
    document.getElementById('dropdown-add-playlist').style.display = 'none';
    document.getElementById('dropdown-add-song').style.display = 'none';

    document.getElementById('app').style.display = 'none';
    fetchToLua('closeUI');
}

document.onkeyup = function (data) {
    if (data.key === 'Escape') closeUI();
};

function openPlayer(data) {
    // Mostrar app
    document.getElementById('app').style.display = 'flex';
    document.getElementById('player-container').style.display = 'flex';

    // Resetear barra progreso
    const progressInput = document.getElementById('input-progress');
    progressInput.value = 0;
    progressInput.disabled = (data.estado === "detenido" || !data.estado);
    document.getElementById('current-time').innerText = "00:00";
    document.getElementById('total-time').innerText = "00:00";

    // Cargar datos
    currentRadioId = data.id;
    currentState = data.estado || "detenido";
    currentPlayingUrl = data.link || "";

    // Actualizar UI
    document.getElementById('input-url').value = currentPlayingUrl;

    // Cargar volumen guardado de este altavoz específico
    const savedVolume = localStorage.getItem('DPBoombox_Volume_' + currentRadioId);
    if (savedVolume !== null) {
        updateVolumeUI(parseInt(savedVolume)); // Ponemos el que tenía guardado
    } else {
        updateVolumeUI(50); // Si es la primera vez que se abre este altavoz, al 50%
    }

    // QUE SE VEA LA FOTO NADA MÁS ABRIR EL MENÚ
    updateThumbnail(currentPlayingUrl);

    const titleBox = document.getElementById('now-playing-title');
    if ((currentState === "reproduciendo" || currentState === "pausado") && data.title) {
        titleBox.innerText = data.title;
        titleBox.style.color = 'white';
    } else {
        titleBox.innerText = 'SIN CANCIÓN';
        titleBox.style.color = 'var(--primary-color)';
    }

    // Aplicar diseño de botones al abrir según el LocalStorage
    document.getElementById('btn-toggle-shuffle').classList.toggle('active-state', isShuffleEnabled);

    // Sincronizar el botón visual (El valor ya llegó de la BD)
    const moveSwitch = document.getElementById('setting-move-ped');
    if (moveSwitch) moveSwitch.checked = moveWhileOpen;

    // 🚨 PREVENCIÓN DE CONFLICTOS AL ARRANCAR
    if (isLoopEnabled && isLoopSingleEnabled) {
        isLoopEnabled = false;
        localStorage.setItem('DPBoombox_Loop', false);
    }

    document.getElementById('btn-toggle-loop').classList.toggle('active-state', isLoopEnabled);
    document.getElementById('btn-toggle-loop-single').classList.toggle('active-state', isLoopSingleEnabled);

    updatePlayButton();

    // 💾 LEER DE MEMORIA LOCAL (O usar la de altavoz por defecto si es la primera vez)
    const savedTab = localStorage.getItem('DPBoombox_LastTab') || 'page-player';
    switchToTab(savedTab);

    // Si la pestaña guardada era la biblioteca, le pedimos a Lua que cargue las listas
    if (savedTab === 'page-saved-songs') {
        fetchToLua('getPlaylists');
    }
}

function updatePlayButton() {
    const btn = document.querySelector('.media-center #btn-play-action');
    if (!btn) return;

    const iconElement = btn.querySelector('iconify-icon');
    if (!iconElement) return;

    // Cambiamos el icono según el estado global
    if (currentState === "reproduciendo") {
        iconElement.setAttribute('icon', 'mdi:pause-circle');
    } else {
        iconElement.setAttribute('icon', 'mdi:play-circle');
    }

    const urlInput = document.getElementById('input-url');
    if (urlInput) {
        btn.disabled = (urlInput.value.trim() === "");
    }

    // 🚨 LLAMADA A LA MAGIA: Sincronizar la lista de abajo
    syncPlaylistIcons();
}

// Busca qué canción está sonando y enciende su icono en la lista
function syncPlaylistIcons() {
    const overlays = document.querySelectorAll('.pl-play-overlay');

    overlays.forEach(overlay => {
        const songUrl = overlay.getAttribute('data-url');
        const icon = overlay.querySelector('iconify-icon');
        const itemDiv = overlay.closest('.playlist-item');

        if (songUrl === currentPlayingUrl) {
            // Es la canción actual: la marcamos como activa visualmente
            overlay.classList.add('active');
            itemDiv.classList.add('playing-active');

            if (currentState === "reproduciendo") {
                icon.setAttribute('icon', 'mdi:pause');
            } else {
                icon.setAttribute('icon', 'mdi:play');
            }
        } else {
            // No es la canción actual: la apagamos
            overlay.classList.remove('active');
            itemDiv.classList.remove('playing-active');
            icon.setAttribute('icon', 'mdi:play');
        }
    });
}

function updateProgressBar(data) {
    // 🚨 INTELIGENCIA ANTI-BUGS:
    // Si estamos esperando una nueva canción, miramos si el tiempo de Lua es muy bajo (menos de 1.5s).
    // Si es así, significa que la nueva canción YA EMPEZÓ y quitamos el bloqueo al instante.
    if (isBufferingNewSong) {
        // 🐛 BUG FIX: Exigimos que data.duration > 5 para confirmar que son los metadatos reales de YouTube
        if (data.currentTime < 1.5 && data.duration > 5) {
            isBufferingNewSong = false;
            clearTimeout(bufferingTimeout); // Cancelamos el seguro
        } else {
            return; // Sigue siendo la canción vieja muriendo o cargando, ignoramos sus tiempos.
        }
    }

    const progressInput = document.getElementById('input-progress');
    progressInput.max = data.duration;
    progressInput.value = data.currentTime;
    progressInput.disabled = (data.duration <= 0);
    document.getElementById('current-time').innerText = formatTime(data.currentTime);
    document.getElementById('total-time').innerText = formatTime(data.duration);
}

function formatTime(seconds) {
    if (isNaN(seconds) || seconds < 0) return "00:00";
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);
    return h > 0 ?
        `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}` :
        `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
}

// ==========================================
// 4. CONTROLES DEL REPRODUCTOR (EVENTOS)
// ==========================================
document.getElementById('input-progress').addEventListener('input', e => {
    isDraggingProgress = true;
    document.getElementById('current-time').innerText = formatTime(e.target.value);
});

document.getElementById('input-progress').addEventListener('change', e => {
    isDraggingProgress = false;
    const seekValue = parseFloat(e.target.value);
    const maxValue = parseFloat(e.target.max);

    // 🚨 PREVENCIÓN ANTI-BUGS: Si arrastras la barra a los últimos 2 segundos de la canción,
    // forzamos el salto a la siguiente para evitar que xSound se asfixie al cargar tan poco margen.
    if (maxValue > 10 && seekValue >= (maxValue - 2.0)) {
        playNextSong(true);
    } else {
        fetchToLua('seekTime', { id: currentRadioId, time: seekValue });
    }
});

document.getElementById('input-url').addEventListener('input', e => {
    const btn = document.getElementById('btn-play-action');
    const iconElement = btn.querySelector('iconify-icon');
    const currentInputValue = e.target.value.trim();

    // Activamos o desactivamos el botón en tiempo real si hay texto
    btn.disabled = (currentInputValue === "");

    // QUE LA FOTO APAREZCA AL PEGAR EL LINK 
    updateThumbnail(currentInputValue);

    if (currentInputValue !== currentPlayingUrl) {
        // Si es una URL nueva, preparamos el icono de Play,
        // EXCEPTO si el script lo está cambiando automáticamente
        if (!isAutoChangingSong) {
            iconElement.setAttribute('icon', 'mdi:play-circle');
        }
    } else {
        // Si vuelve a la URL actual, restauramos su estado
        updatePlayButton();
    }
});

// ==========================================
// CONTROL DE VOLUMEN DINÁMICO Y TOOLTIP FLOTANTE
// ==========================================
const volPill = document.getElementById('volume-pill');
const btnToggleVol = document.getElementById('btn-toggle-volume');
const volInput = document.getElementById('input-volume');
const volIcon = document.getElementById('volume-icon');
const volTooltip = document.getElementById('volume-tooltip');

// 1. Estirar / Encoger el botón al darle clic
btnToggleVol.addEventListener('click', e => {
    e.stopPropagation();
    volPill.classList.toggle('expanded');
    // Si cerramos el menú, forzamos a ocultar el tooltip
    if (!volPill.classList.contains('expanded')) {
        volTooltip.style.opacity = '0';
        volTooltip.style.visibility = 'hidden';
    }
});

// 2. Encoger si se clica fuera de la píldora
document.addEventListener('click', e => {
    if (volPill.classList.contains('expanded') && !volPill.contains(e.target)) {
        volPill.classList.remove('expanded');
        volTooltip.style.opacity = '0';
        volTooltip.style.visibility = 'hidden';
    }
});

// 3. Modificar volumen y actualizar visuales
volInput.addEventListener('input', e => {
    const val = parseInt(e.target.value);
    updateVolumeUI(val);

    // Guardamos el volumen en el PC asignado a la ID de este altavoz
    if (currentRadioId) {
        localStorage.setItem('DPBoombox_Volume_' + currentRadioId, val);
    }

    fetchToLua('changeVolume', { id: currentRadioId, volume: val });
});

function updateVolumeUI(val) {
    volInput.value = val;
    volTooltip.innerText = val + '%';

    if (val === 0) {
        volIcon.setAttribute('icon', 'mdi:volume-mute');
    } else if (val > 0 && val < 50) {
        volIcon.setAttribute('icon', 'mdi:volume-low');
    } else if (val >= 50 && val < 100) {
        volIcon.setAttribute('icon', 'mdi:volume-medium');
    } else if (val === 100) {
        volIcon.setAttribute('icon', 'mdi:volume-high');
    }
}

// 4. MAGIA DEL TOOLTIP QUE SIGUE AL RATÓN (SOLO EN EL CIRCULITO)
let isDraggingVol = false;

// Función matemática para saber si el ratón toca el circulito blanco
function isMouseOverThumb(clientY) {
    const rect = volInput.getBoundingClientRect();
    const val = parseInt(volInput.value);

    // El input mide 70px de alto y el circulito 14px.
    // El centro del círculo se mueve entre el píxel 7 (0%) y el 63 (100%). Distancia de 56px.
    const thumbCenterFromBottom = (val / 100) * 56 + 7;

    // Calculamos a qué altura exacta de la barra está tu ratón
    const mouseYFromBottom = rect.bottom - clientY;

    // Si la distancia entre tu ratón y el circulito es menor o igual a 10px, estás encima.
    return Math.abs(mouseYFromBottom - thumbCenterFromBottom) <= 10;
}

// Al mover el ratón por la barra, decidimos si mostramos el tooltip o no
volInput.addEventListener('mousemove', (e) => {
    // Solo lo mostramos si estamos arrastrando o si tocamos el circulito
    if (isDraggingVol || isMouseOverThumb(e.clientY)) {
        volTooltip.style.opacity = '1';
        volTooltip.style.visibility = 'visible';
        volTooltip.style.left = e.clientX + 'px';
        volTooltip.style.top = e.clientY + 'px';
    } else {
        // Si el ratón está en la barra negra vacía, lo escondemos
        volTooltip.style.opacity = '0';
        volTooltip.style.visibility = 'hidden';
    }
});

// Desaparece al sacar el ratón del input por completo
volInput.addEventListener('mouseleave', () => {
    if (!isDraggingVol) {
        volTooltip.style.opacity = '0';
        volTooltip.style.visibility = 'hidden';
    }
});

// Al hacer clic en la barra, forzamos a que aparezca y lo ponemos en "modo arrastre"
volInput.addEventListener('mousedown', (e) => {
    isDraggingVol = true;
    volTooltip.style.opacity = '1';
    volTooltip.style.visibility = 'visible';
    volTooltip.style.left = e.clientX + 'px';
    volTooltip.style.top = e.clientY + 'px';
});

// Al soltar el clic, apagamos el modo arrastre
document.addEventListener('mouseup', (e) => {
    if (isDraggingVol) {
        isDraggingVol = false;
        // Si al soltar, el ratón ya no está encima del circulito, lo escondemos
        if (!volInput.matches(':hover') || !isMouseOverThumb(e.clientY)) {
            volTooltip.style.opacity = '0';
            volTooltip.style.visibility = 'hidden';
        }
    }
});

document.getElementById('btn-play-action').addEventListener('click', async function () {
    const url = document.getElementById('input-url').value.trim();
    if (!url) return;

    let action = "play";
    let isNewSong = false;

    if (url === currentPlayingUrl) {
        action = (currentState === "reproduciendo") ? "pause" : "resume";
    } else {
        isNewSong = true;
    }

    // 1. SI ES PAUSAR O REANUDAR (Es instantáneo y no carga nada nuevo)
    if (action !== "play") {
        currentState = (action === "pause") ? "pausado" : "reproduciendo";
        updatePlayButton();
        fetchToLua('playerAction', {
            id: currentRadioId,
            url: url,
            volume: document.getElementById('input-volume').value,
            title: document.getElementById('now-playing-title').innerText,
            action: action
        });
        return; // Salimos de la función para no ejecutar el código de abajo
    }

    // 2. SI ES UNA CANCIÓN NUEVA (PLAY)
    if (isNewSong) {
        isBufferingNewSong = true;
        const progressInput = document.getElementById('input-progress');
        progressInput.value = 0;
        document.getElementById('current-time').innerText = "00:00";
        document.getElementById('total-time').innerText = "00:00";

        clearTimeout(bufferingTimeout);
        // 🚨 FIX: Aumentamos el escudo visual a 8 segundos para que el JS ignore 
        // cualquier "tiempo fantasma" hasta que la nueva canción esté sonando de verdad.
        bufferingTimeout = setTimeout(() => { isBufferingNewSong = false; }, 8000);
    }

    // 🚨 MAGIA ANTI-BUGS: ACTUALIZAMOS EL ESTADO DE INMEDIATO (SIN ESPERAR A INTERNET)
    currentPlayingUrl = url;
    currentState = "reproduciendo";
    updatePlayButton(); // Esto pone el icono en Pause y pinta la lista de verde al milisegundo

    let fetchedTitle = document.getElementById('now-playing-title').innerText;

    // Comprobamos si el título ya es uno real (Si viene de una lista, ya lo sabemos)
    let isKnownTitle = (fetchedTitle !== "CARGANDO..." && fetchedTitle !== "SIN CANCIÓN" && fetchedTitle !== "");

    if (!isKnownTitle) {
        document.getElementById('now-playing-title').innerText = "CARGANDO...";
        document.getElementById('now-playing-title').style.color = 'var(--primary-color)';
    } else {
        document.getElementById('now-playing-title').style.color = 'white';
    }

    // Mandamos a reproducir a FiveM inmediatamente para que suene ya
    fetchToLua('playerAction', {
        id: currentRadioId,
        url: url,
        volume: document.getElementById('input-volume').value,
        title: isKnownTitle ? fetchedTitle : "Cargando...",
        action: action
    });

    // 3. SOLO buscamos en internet si es un enlace manual pegado a mano en el panel
    if (!isKnownTitle) {
        try {
            const res = await fetch(`https://noembed.com/embed?dataType=json&url=${encodeURIComponent(url)}`);
            const data = await res.json();

            // Si cuando llega la respuesta sigues en la misma canción, actualizamos el título
            if (currentPlayingUrl === url) {
                fetchedTitle = data.title || "URL Personalizada";
                document.getElementById('now-playing-title').innerText = fetchedTitle;
                document.getElementById('now-playing-title').style.color = 'white';

                // Actualizamos el servidor silenciosamente con el nombre real
                fetchToLua('playerAction', {
                    id: currentRadioId, url: url, volume: document.getElementById('input-volume').value,
                    title: fetchedTitle, action: "play"
                });
            }
        } catch {
            if (currentPlayingUrl === url) {
                document.getElementById('now-playing-title').innerText = "URL Personalizada";
                document.getElementById('now-playing-title').style.color = 'white';
            }
        }
    }
});

// ==========================================
// 5. SISTEMA DE TABS (PESTAÑAS)
// ==========================================
const tabTitles = {
    'page-player': { title: 'Altavoz', subtitle: 'Escucha una canción en cualquier momento' },
    'page-saved-songs': { title: 'Listas de reproducciones', subtitle: 'Gestiona tus playlists a tu gusto' },
    'page-settings': { title: 'Ajustes', subtitle: 'Configuración avanzada el altavoz' }
};

document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', function () {
        switchToTab(this.getAttribute('data-target'));
        // Si entramos a la biblioteca, pedimos listas a Lua
        if (this.getAttribute('data-target') === 'page-saved-songs') {
            fetchToLua('getPlaylists');
        }
    });
});

function switchToTab(targetId) {
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-page').forEach(p => p.style.display = 'none');

    document.querySelector(`[data-target="${targetId}"]`).classList.add('active');
    document.getElementById(targetId).style.display = 'block';

    const targetPage = document.getElementById(targetId);
    if (targetPage) {
        targetPage.style.display = 'flex'; // 👈 CAMBIA 'block' POR 'flex' AQUÍ
        targetPage.classList.add('active-tab');
    }

    if (tabTitles[targetId]) {
        document.getElementById('main-title').innerText = tabTitles[targetId].title;
        document.getElementById('main-subtitle').innerText = tabTitles[targetId].subtitle;
    }

    // 💾 GUARDAR EN MEMORIA LOCAL
    localStorage.setItem('DPBoombox_LastTab', targetId);
}

// ==========================================
// 6. SISTEMA UNIFICADO DE MODALES DINÁMICOS (DRY)
// ==========================================
const modalOverlay = document.getElementById('modal-overlay');
const modalContentContainer = document.getElementById('modal-content-container');

// Cierra el modal si clickeas el fondo oscuro
modalOverlay.addEventListener('click', e => {
    if (e.target === modalOverlay) modalOverlay.style.display = 'none';
});

// Motor del modal: Pinta el interior dinámicamente usando CLASES CSS y lo muestra
function showDynamicModal(icon, title, subtitle, bodyHtml) {
    modalContentContainer.innerHTML = `
        <div class="page-header modern-header">
            <div class="section-title">
                <div class="title-icon-wrap"><iconify-icon icon="${icon}"></iconify-icon></div>
                <div class="title-text">
                    <h2>${title}</h2>
                    <p>${subtitle}</p>
                </div>
            </div>
        </div>
        <div class="content-body modal-body-centered">
            ${bodyHtml}
        </div>
    `;
    modalOverlay.style.display = 'flex';
}

// ==========================================
// 7. GESTIÓN DE PLAYLISTS (BIBLIOTECA)
// ==========================================
const dropdownAddPlaylist = document.getElementById('dropdown-add-playlist');

document.getElementById('btn-add-playlist').addEventListener('click', e => {
    e.stopPropagation();
    dropdownAddPlaylist.style.display = dropdownAddPlaylist.style.display === 'flex' ? 'none' : 'flex';
});

document.addEventListener('click', e => {
    if (dropdownAddPlaylist.style.display === 'flex' && !dropdownAddPlaylist.contains(e.target)) {
        dropdownAddPlaylist.style.display = 'none';
    }
});

// Variable global para saber qué lista tenemos abierta
let currentSelectedPlaylistId = null;
let currentPlaylistSongs = [];

// Generador dinámico de Mosaicos para las Playlists
function generatePlaylistCover(urls) {
    // 🚨 SI NO HAY CANCIONES, DEVOLVEMOS EL ICONO
    if (!urls || urls.length === 0) {
        return `<div class="pl-cover pl-cover-empty"><iconify-icon icon="mdi:music-off"></iconify-icon></div>`;
    }

    // Convertimos las URLs en enlaces de miniaturas de YouTube
    const thumbs = urls.map(url => {
        const id = extractYouTubeID(url);
        return id ? `https://img.youtube.com/vi/${id}/hqdefault.jpg` : '';
    }).filter(src => src !== '');

    const count = Math.min(thumbs.length, 5);

    // 🚨 SI HAY CANCIONES PERO ERAN ENLACES INVÁLIDOS, DEVOLVEMOS EL ICONO
    if (count === 0) {
        return `<div class="pl-cover pl-cover-empty"><iconify-icon icon="mdi:music-off"></iconify-icon></div>`;
    }

    let html = `<div class="pl-cover pl-cover-grid grid-${count}">`;

    if (count === 5) {
        // Si son 5, ponemos 4 de fondo y la 5ª en el centro flotando
        for (let i = 0; i < 4; i++) {
            html += `<div class="pl-thumb" style="background-image: url('${thumbs[i]}');"></div>`;
        }
        html += `<div class="pl-thumb-center" style="background-image: url('${thumbs[4]}');"></div>`;
    } else {
        // Para 1, 2, 3 o 4, simplemente las pintamos normales
        for (let i = 0; i < count; i++) {
            html += `<div class="pl-thumb" style="background-image: url('${thumbs[i]}');"></div>`;
        }
    }
    html += `</div>`;
    return html;
}

// RENDERIZAR PLAYLISTS AL RECIBIRLAS DE LUA
function renderPlaylists(listas) {
    const container = document.getElementById('library-content');
    container.innerHTML = '';

    if (!listas || listas.length === 0) {
        container.innerHTML = `
            <div class="empty-state">
                <iconify-icon icon="picon:playlist"></iconify-icon>
                <p>No tienes listas. ¡Crea una o importa un código!</p>
            </div>`;
        return;
    }

    listas.forEach(pl => {
        const isOwner = pl.is_owner === 1;
        const isSelected = currentSelectedPlaylistId === pl.id;

        const div = document.createElement('div');
        div.className = `playlist-item ${isSelected ? 'selected' : ''}`;

        div.innerHTML = `
            ${generatePlaylistCover(pl.thumbnails)}
            <div class="pl-info">
                <span class="pl-title">${pl.name}</span>
                <span class="pl-role">${isOwner ? 'Propietario' : 'Invitado'}</span>
            </div>
            <div class="pl-actions">
                <button class="btn-icon" title="Compartir" onclick="event.stopPropagation(); openModalShare('${pl.name}', '${pl.share_code}')">
                    <iconify-icon icon="mdi:share-variant"></iconify-icon>
                </button>
                <button class="btn-icon" title="Editar" onclick="event.stopPropagation(); openModalEdit(${pl.id}, ${isOwner})">
                    <iconify-icon icon="mdi:pencil"></iconify-icon>
                </button>
                <button class="btn-icon delete" title="${isOwner ? 'Eliminar' : 'Abandonar'}" onclick="event.stopPropagation(); openModalDelete(${pl.id}, ${isOwner})">
                    <iconify-icon icon="${isOwner ? 'mdi:trash-can' : 'mdi:exit-run'}"></iconify-icon>
                </button>
            </div>
        `;

        // AL HACER CLIC EN LA TARJETA, LA SELECCIONAMOS
        div.onclick = () => selectPlaylist(pl.id, pl.name);

        container.appendChild(div);
    });
}

// ==========================================
// LÓGICA DE CANCIONES Y SELECCIÓN (CON DESELECCIÓN)
// ==========================================
function selectPlaylist(id, name) {
    // Si hacemos clic en la misma lista que ya estaba seleccionada, la deseleccionamos
    if (currentSelectedPlaylistId === id) {
        currentSelectedPlaylistId = null;

        // 1. Quitamos la selección visual (quitando la clase y refrescando)
        document.querySelectorAll('.playlist-item').forEach(item => item.classList.remove('selected'));
        fetchToLua('getPlaylists');

        // 2. Reseteamos el título de la sección inferior
        document.getElementById('songs-section-title').innerText = "SELECCIONA UNA LISTA";

        // 3. Ocultamos el botón "+"
        document.getElementById('btn-add-song').style.display = 'none';
        document.getElementById('dropdown-add-song').style.display = 'none';

        // 4. Devolvemos el contenedor a su estado de "caja vacía" original
        document.getElementById('songs-list-content').innerHTML = `
            <div class="empty-state">
                <iconify-icon icon="mdi:playlist-music-outline"></iconify-icon>
                <p>Haz clic en una lista de arriba para ver sus canciones.</p>
            </div>
        `;
        return; // Salimos de la función aquí para no ejecutar la carga de canciones
    }

    // --- SI ES UNA LISTA NUEVA, HACEMOS LA CARGA NORMAL ---
    currentSelectedPlaylistId = id;

    // 1. Efecto visual: Marcamos la lista seleccionada
    document.querySelectorAll('.playlist-item').forEach(item => item.classList.remove('selected'));
    // Refrescamos las listas para que se aplique el estilo a la correcta
    fetchToLua('getPlaylists');

    // 2. Cambiamos el texto del panel inferior
    document.getElementById('songs-section-title').innerText = `Canciones de "${name}" (Cargando...)`;

    // 3. Mostramos el botón "+" de la zona inferior
    document.getElementById('btn-add-song').style.display = 'flex';

    // 4. Pedimos a Lua las canciones de esta playlist
    fetchToLua('getPlaylistSongs', { playlistId: id });
}

function renderSongsList(songs, playlistName) {
    // GUARDAMOS LAS CANCIONES EN MEMORIA PARA VERIFICAR DUPLICADOS LUEGO
    currentPlaylistSongs = songs;

    const container = document.getElementById('songs-list-content');
    const title = document.getElementById('songs-section-title');

    title.innerText = `Canciones de "${playlistName}" (${songs.length})`;
    container.innerHTML = '';

    if (songs.length === 0) {
        container.innerHTML = `
            <div class="empty-state">
                <iconify-icon icon="solar:music-notes-broken" style="font-size: 40px; opacity: 0.5; margin-bottom: 5px;"></iconify-icon>
                <p style="font-weight: 700; letter-spacing: 1px;">LISTA VACÍA</p>
                <p style="color: var(--text-muted); font-size: 10px; max-width: 80%; line-height: 1.6;">
                    Aquí saldrán las canciones de esta lista una vez las metas dándole al botón <b style="color: var(--primary-color); font-size: 12px; margin-left: 5px; margin-right: 5px;">+</b> de arriba.
                </p>
            </div>`;
        return;
    }

    // Pintamos las canciones igual que las listas para que mantenga el diseño
    songs.forEach(song => {
        const div = document.createElement('div');
        div.className = 'playlist-item';

        const videoId = extractYouTubeID(song.url);
        const thumbUrl = videoId ? `https://img.youtube.com/vi/${videoId}/hqdefault.jpg` : '';

        // Comprobamos el estado actual para dibujarlo correctamente al abrir la lista
        const isPlayingThis = (currentPlayingUrl === song.url && currentState === "reproduciendo");
        const isPausedThis = (currentPlayingUrl === song.url && currentState === "pausado");

        let iconType = isPlayingThis ? "mdi:pause" : "mdi:play";
        let overlayClass = (isPlayingThis || isPausedThis) ? "pl-play-overlay active" : "pl-play-overlay";

        // El HTML de la portada ahora incluye nuestro botón oculto
        const coverHtml = `
            <div class="pl-cover" style="background-image: url('${thumbUrl}'); background-size: cover; background-position: center;">
                <div class="${overlayClass}" data-url="${song.url}" onclick="event.stopPropagation(); toggleSongPlay('${song.url}', '${song.label.replace(/'/g, "\\'")}')">
                    <iconify-icon icon="${iconType}"></iconify-icon>
                </div>
            </div>`;

        div.innerHTML = `
            ${coverHtml}
            <div class="pl-info">
                <span class="pl-title" title="${song.label}">${song.label}</span>
                <span class="pl-role">${song.author || 'Sin autor'}</span>
            </div>
            <div class="pl-actions">
                <button class="btn-icon delete" title="Eliminar" onclick="event.stopPropagation(); deleteSongFromList(${song.id}, ${currentSelectedPlaylistId})">
                    <iconify-icon icon="mdi:trash-can"></iconify-icon>
                </button>
            </div>
        `;
        container.appendChild(div);
    });
}

// ==========================================
// 🚨 EL "MANDO A DISTANCIA" DEL REPRODUCTOR GLOBAL 🚨
// ==========================================
function toggleSongPlay(url, title) {
    const urlInput = document.getElementById('input-url');

    // Si clicamos en una canción DIFERENTE a la que está sonando
    if (currentPlayingUrl !== url) {

        isAutoChangingSong = true; // 🔒 BLOQUEAMOS EL ICONO VISUAL

        urlInput.value = url;
        // Simulamos que el usuario ha escrito la URL para activar el botón principal
        urlInput.dispatchEvent(new Event('input'));

        // Cambiamos el título visualmente rápido para que se vea reactivo
        document.getElementById('now-playing-title').innerText = title;

        isAutoChangingSong = false; // 🔓 DESBLOQUEAMOS
    }

    // Le decimos al botón gigante de abajo que haga su trabajo (Play o Pause)
    document.getElementById('btn-play-action').click();
}

// ACCIÓN: CREAR PLAYLIST (Pagar texto dinámico)
document.getElementById('btn-create-playlist').addEventListener('click', () => {
    dropdownAddPlaylist.style.display = 'none';

    // HTML dinámico usando clases CSS (input-group para textAlign:left, modal-actions para gap/margin)
    const content = `
        <div class="input-group">
            <label>NOMBRE DE LA LISTA</label>
            <input type="text" id="input-new-playlist" placeholder="Ej: Canciones de Rol..." maxlength="50" required>
        </div>
        <div class="modal-actions">
            <button type="button" class="btn btn-solid" id="btn-confirm-playlist">CREAR LISTA</button>
        </div>
    `;

    showDynamicModal('ion:create', 'CREAR PLAYLIST', 'Elige un título para tu lista', content);
    // Autofocus al input
    setTimeout(() => document.getElementById('input-new-playlist').focus(), 100);

    document.getElementById('btn-confirm-playlist').addEventListener('click', () => {
        const input = document.getElementById('input-new-playlist');
        const title = input.value.trim();
        if (title === "") {
            input.style.borderColor = 'var(--danger)'; // Este style inline se queda por ser feedback temporal (1s)
            setTimeout(() => input.style.borderColor = 'var(--border-color)', 1000);
            return;
        }
        modalOverlay.style.display = 'none';
        fetchToLua('createPlaylist', { name: title });
    });
});

// ==========================================
// FUNCIÓN AUXILIAR PARA COPIAR EN FIVEM
// ==========================================
function fallbackCopyTextToClipboard(text) {
    var textArea = document.createElement("textarea");
    textArea.value = text;
    textArea.style.top = "0";
    textArea.style.left = "0";
    textArea.style.position = "fixed";
    document.body.appendChild(textArea);
    textArea.focus();
    textArea.select();
    try {
        document.execCommand('copy');
    } catch (err) {
        console.error('Error al copiar', err);
    }
    document.body.removeChild(textArea);
}

// ACCIÓN: COMPARTIR PLAYLIST
function openModalShare(playlistName, shareCode) {
    const content = `
        <p class="modal-text-secondary">
            Copia este código y dáselo a tus amigos para que puedan unirse.
        </p>
        <div class="share-code-container">
            <input type="text" value="${shareCode}" readonly class="share-code-input">
            <button class="btn-icon btn-copy-margin-fix" id="btn-copy-code">
                <iconify-icon icon="mdi:content-copy"></iconify-icon>
            </button>
        </div>
        <div class="modal-actions">
            <button type="button" class="btn btn-solid" onclick="document.getElementById('modal-overlay').style.display = 'none';">CERRAR</button>
        </div>
    `;

    showDynamicModal('mdi:share-variant', 'COMPARTIR LISTA', playlistName, content);

    // Lógica de copiar compatible con FiveM
    document.getElementById('btn-copy-code').addEventListener('click', function () {
        fallbackCopyTextToClipboard(shareCode);
        this.innerHTML = '<iconify-icon icon="mdi:check-bold" style="color: white;"></iconify-icon>';
        setTimeout(() => this.innerHTML = '<iconify-icon icon="mdi:content-copy"></iconify-icon>', 2000);
    });
}

// ==========================================
// ACCIÓN: IMPORTAR PLAYLIST
// ==========================================
document.getElementById('btn-import-playlist').addEventListener('click', () => {
    dropdownAddPlaylist.style.display = 'none'; // Cerramos el desplegable

    // HTML dinámico para el modal
    const content = `
        <div class="input-group">
            <label>CÓDIGO DE INVITACIÓN</label>
            <input type="text" id="input-import-code" class="import-code-input" placeholder="Ej: X7B9K2M" required>
        </div>
        <div class="modal-actions">
            <button type="button" class="btn btn-solid" id="btn-confirm-import">UNIRSE</button>
        </div>
    `;

    showDynamicModal('fluent:arrow-import-24-filled', 'IMPORTAR LISTA', 'Introduce el código de la playlist', content);
    setTimeout(() => document.getElementById('input-import-code').focus(), 100);

    // Lógica para enviar el código a Lua
    document.getElementById('btn-confirm-import').addEventListener('click', () => {
        const input = document.getElementById('input-import-code');
        const code = input.value.trim().toUpperCase();

        if (code === "") {
            input.style.borderColor = 'var(--danger)';
            setTimeout(() => input.style.borderColor = 'var(--border-color)', 1000);
            return;
        }

        document.getElementById('modal-overlay').style.display = 'none';
        fetchToLua('joinPlaylist', { code: code });
    });
});

// ==========================================
// ACCIÓN: EDITAR PLAYLIST (PETICIÓN A LUA)
// ==========================================
function openModalEdit(id, isOwner) {
    // Hemos eliminado el bloqueo de "Solo el propietario puede editar"
    // Ahora le pedimos a Lua los datos y él nos dirá qué permisos tenemos.
    fetchToLua('getPlaylistDetails', { id: id });
}

// ==========================================
// RENDERIZAR EL MODAL DE EDICIÓN CON PERMISOS
// ==========================================
let currentEditMembers = [];

function renderEditModal(data) {
    const playlist = data.playlist;
    currentEditMembers = data.members || [];
    const myPerms = data.myPerms || {}; // Mis permisos actuales (o totales si soy dueño)

    // Solo construimos la lista de miembros si tenemos permisos de gestionarlos
    const canManage = (myPerms.perm_manage === 1);
    const canRename = (myPerms.perm_rename === 1);

    // AÑADIMOS "disabled selected hidden" PARA QUE ACTÚE COMO UN PLACEHOLDER REAL
    let membersOptions = '<option value="none" disabled selected hidden>Selecciona un miembro...</option>';

    if (currentEditMembers.length === 0) {
        membersOptions = '<option value="none" disabled selected>Nadie se ha unido a esta lista aún.</option>';
    } else {
        const myLicense = myPerms.license;
        const isOwner = (playlist.owner === myLicense);

        currentEditMembers.forEach(m => {
            let disabledAttr = '';
            let extraText = '';

            // 1. Un invitado no puede editarse a sí mismo
            if (!isOwner && m.license === myLicense) {
                disabledAttr = ' disabled';
                extraText = ' (Tú)';
            }
            // 2. Un invitado nunca puede editar al dueño
            else if (!isOwner && m.license === playlist.owner) {
                disabledAttr = ' disabled';
                extraText = ' (Dueño)';
            }

            membersOptions += `<option value="${m.license}"${disabledAttr}>${m.charName}${extraText}</option>`;
        });
    }

    // Si puede renombrar, mostramos el input con límite de 50; si no, lo ocultamos guardando el valor.
    const renameHtml = canRename ? `
        <div class="input-group" style="text-align: left;">
            <label>RENOMBRAR LA LISTA</label>
            <input type="text" id="input-edit-name" value="${playlist.name}" maxlength="50" required>
        </div>
        <hr style="border-color: var(--border-color); margin: 5px 0; opacity: 0.5;">
    ` : `<input type="hidden" id="input-edit-name" value="${playlist.name}">`;

    // Si puede gestionar personas, mostramos el desplegable de usuarios
    const manageHtml = canManage ? `
        <div class="input-group" style="text-align: left;">
            <label>GESTIONAR MIEMBROS</label>
            <select id="select-edit-member" class="styled-select">
                ${membersOptions}
            </select>
            <p id="no-member-msg" style="color: var(--danger); font-size: 9px; margin-top: 5px; ${currentEditMembers.length === 0 ? '' : 'display:none;'}">
                Esta lista no está en uso por otra persona.
            </p>
        </div>

        <div id="permissions-container" style="display: none; flex-direction: column; gap: 5px;">
            ${generateToggleHTML('perm_rename', 'Renombrar Lista', 'Permitir cambiar el nombre')}
            ${generateToggleHTML('perm_delete', 'Eliminar Canciones', 'Permitir borrar temas')}
            ${generateToggleHTML('perm_add', 'Añadir Canciones', 'Permitir guardar nuevos temas')}
            ${generateToggleHTML('perm_reorder', 'Cambiar Orden', 'Permitir mover canciones')}
            ${generateToggleHTML('perm_manage', 'Gestionar Personas', 'Permitir editar permisos')}
            ${generateToggleHTML('perm_future1', 'Opción Futura 1', 'Reservado')}
            ${generateToggleHTML('perm_future2', 'Opción Futura 2', 'Reservado')}
        </div>
    ` : `
        <div style="background: rgba(0,0,0,0.3); padding: 10px; border-radius: 4px; text-align: center; margin-top: 10px;">
            <p style="color: var(--warning-text); font-size: 11px; margin: 0;">
                <iconify-icon icon="mdi:lock-outline" style="font-size: 16px; vertical-align: middle;"></iconify-icon><br>
                Solo el propietario o un moderador de la lista puede gestionar a los miembros.
            </p>
        </div>
    `;

    // Unimos los bloques para construir el interior del modal
    const content = `
        <div class="modal-body-scrollable">
            ${renameHtml}
            ${manageHtml}
        </div>

        <div class="modal-actions">
            <button type="button" class="btn btn-solid" id="btn-save-edit" ${(canRename || canManage) ? '' : 'style="display:none;"'}>GUARDAR CAMBIOS</button>
        </div>
    `;

    showDynamicModal('mdi:pencil', 'EDITAR LISTA', (canRename || canManage) ? 'Ajustes y permisos' : 'Modo Lectura', content);

    // Lógica para cambiar los interruptores cuando seleccionamos un jugador distinto
    const selectMember = document.getElementById('select-edit-member');
    if (selectMember) {
        const permContainer = document.getElementById('permissions-container');
        selectMember.addEventListener('change', (e) => {
            const license = e.target.value;
            if (license === "none") {
                permContainer.style.display = 'none';
            } else {
                permContainer.style.display = 'flex';
                const member = currentEditMembers.find(m => m.license === license);
                if (member) {
                    document.getElementById('toggle-perm_rename').checked = member.perm_rename === 1;
                    document.getElementById('toggle-perm_delete').checked = member.perm_delete === 1;
                    document.getElementById('toggle-perm_add').checked = member.perm_add === 1;
                    document.getElementById('toggle-perm_reorder').checked = member.perm_reorder === 1;
                    document.getElementById('toggle-perm_manage').checked = member.perm_manage === 1;
                    document.getElementById('toggle-perm_future1').checked = member.perm_future1 === 1;
                    document.getElementById('toggle-perm_future2').checked = member.perm_future2 === 1;
                }
            }
        });
    }

    // Guardar cambios (solo procesará lo que exista en el DOM)
    const btnSave = document.getElementById('btn-save-edit');
    if (btnSave) {
        btnSave.addEventListener('click', () => {
            const newName = document.getElementById('input-edit-name') ? document.getElementById('input-edit-name').value.trim() : playlist.name;
            let permissionsToSave = null;

            if (selectMember && selectMember.value !== "none") {
                permissionsToSave = {
                    license: selectMember.value,
                    perm_rename: document.getElementById('toggle-perm_rename').checked ? 1 : 0,
                    perm_delete: document.getElementById('toggle-perm_delete').checked ? 1 : 0,
                    perm_add: document.getElementById('toggle-perm_add').checked ? 1 : 0,
                    perm_reorder: document.getElementById('toggle-perm_reorder').checked ? 1 : 0,
                    perm_manage: document.getElementById('toggle-perm_manage').checked ? 1 : 0,
                    perm_future1: document.getElementById('toggle-perm_future1').checked ? 1 : 0,
                    perm_future2: document.getElementById('toggle-perm_future2').checked ? 1 : 0
                };
            }

            document.getElementById('modal-overlay').style.display = 'none';
            fetchToLua('savePlaylistEdit', {
                id: playlist.id,
                newName: newName,
                permissions: permissionsToSave
            });
        });
    }
}

// Generador de HTML para los interruptores
function generateToggleHTML(id, title, desc) {
    return `
        <div class="permission-item">
            <div class="permission-info">
                <span class="permission-title">${title}</span>
                <span class="permission-desc">${desc}</span>
            </div>
            <label class="toggle-switch">
                <input type="checkbox" id="toggle-${id}">
                <span class="toggle-slider"></span>
            </label>
        </div>
    `;
}

// ==========================================
// ACCIÓN: ABANDONAR O ELIMINAR/TRASPASAR LISTA
// ==========================================
function openModalDelete(id, isOwner) {
    if (!isOwner) {
        // 1. SI ES INVITADO: Solo le preguntamos si quiere salir
        const content = `
            <p class="modal-text-secondary">
                ¿Estás seguro de que quieres abandonar esta lista?<br><br>
                Si deseas volver a unirte más adelante, <b>deberás solicitar el código de invitación al propietario de nuevo</b>.
            </p>
            <div class="modal-actions">
                <button type="button" class="btn btn-solid" style="background: var(--danger); border-color: var(--danger);" onclick="confirmLeavePlaylist(${id})">SALIR DE LA LISTA</button>
            </div>
        `;
        showDynamicModal('mdi:exit-run', 'ABANDONAR LISTA', 'Confirmación de salida', content);
    } else {
        // 2. SI ES OWNER: Le pedimos a Lua los miembros para ver si puede traspasarla
        fetchToLua('getPlaylistForDelete', { id: id });
    }
}

// Acción directa para el invitado
function confirmLeavePlaylist(id) {
    document.getElementById('modal-overlay').style.display = 'none';
    fetchToLua('leavePlaylist', { id: id });
}

// Renderizar el modal complejo para el DUEÑO
function renderDeleteModal(data) {
    const playlist = data.playlist;
    const members = data.members || [];

    // Preparamos el selector de miembros para traspasar
    let membersOptions = '<option value="none" disabled selected hidden>Selecciona a quién traspasarla...</option>';
    let hasMembers = false;

    members.forEach(m => {
        // Asegurarnos de que no nos mostramos a nosotros mismos
        if (m.license !== playlist.owner) {
            membersOptions += `<option value="${m.license}">${m.charName}</option>`;
            hasMembers = true;
        }
    });

    // Si hay miembros, mostramos el selector. Si no, mostramos un mensaje rojo.
    const transferHtml = hasMembers ? `
        <hr style="border-color: var(--border-color); margin: 5px 0; opacity: 0.5;">
        <div class="input-group" style="text-align: left;">
            <label>¿TRASPASAR LISTA ANTES DE SALIR?</label>
            <select id="select-transfer-member" class="styled-select">
                ${membersOptions}
            </select>
            <p style="color: var(--text-muted); font-size: 9px; margin-top: 5px;">
                Si seleccionas a un jugador, se le otorgará la propiedad absoluta y tú abandonarás la lista.
            </p>
        </div>
    ` : `
        <hr style="border-color: var(--border-color); opacity: 0.5;">
        <p style="color: var(--warning-text); font-size: 10px; margin: 0; text-align: center;">
            No hay miembros en esta lista. Solo puedes eliminarla definitivamente.
        </p>
    `;

    // HTML dinámico del modal del Owner
    const content = `
        <div class="modal-body-scrollable">
            <p class="modal-text-secondary">
                Estás a punto de eliminar esta lista y expulsar a todos los miembros. Esta acción NO se puede deshacer.
            </p>
            ${transferHtml}
        </div>
        <div class="modal-actions">
            <button type="button" class="btn btn-solid" id="btn-confirm-delete" style="background: var(--danger); border-color: var(--danger);">ELIMINAR LISTA</button>
        </div>
    `;

    showDynamicModal('mdi:trash-can', 'ELIMINAR LISTA', playlist.name, content);

    // LÓGICA DINÁMICA: Cambiar el botón rojo a verde si selecciona traspasar
    const selectTransfer = document.getElementById('select-transfer-member');
    const btnConfirm = document.getElementById('btn-confirm-delete');

    if (selectTransfer) {
        selectTransfer.addEventListener('change', (e) => {
            if (e.target.value !== "none") {
                btnConfirm.innerText = "TRASPASAR Y SALIR";
                btnConfirm.style.background = "white";
                btnConfirm.style.borderColor = "white";
            } else {
                btnConfirm.innerText = "ELIMINAR LISTA";
                btnConfirm.style.background = "var(--danger)";
                btnConfirm.style.borderColor = "var(--danger)";
            }
        });
    }

    // Ejecutar la acción final elegida
    btnConfirm.addEventListener('click', () => {
        document.getElementById('modal-overlay').style.display = 'none';

        // Si hay alguien seleccionado en el menú, traspasamos. Si no, borramos el mundo.
        if (selectTransfer && selectTransfer.value !== "none") {
            fetchToLua('transferPlaylist', { id: playlist.id, newOwner: selectTransfer.value });
        } else {
            fetchToLua('deletePlaylist', { id: playlist.id });
        }

        // Si teníamos esta lista seleccionada abajo, la deseleccionamos visualmente
        if (currentSelectedPlaylistId === playlist.id) {
            document.getElementById('songs-section-title').innerText = "SELECCIONA UNA LISTA PARA VER EL CONTENIDO";
            document.getElementById('songs-list-content').innerHTML = `
                <div class="empty-state">
                    <iconify-icon icon="mdi:playlist-music-outline"></iconify-icon>
                    <p>Haz clic en una lista de arriba para ver sus canciones.</p>
                </div>`;
            document.getElementById('btn-add-song').style.display = 'none';
            currentSelectedPlaylistId = null;
        }
    });
}

// ==========================================
// ACCIONES INDIVIDUALES DE CANCIONES
// ==========================================

// Reproducir una canción directamente desde la lista
function playSong(url) {
    // 1. Ponemos la URL en el input de la pestaña principal
    document.getElementById('input-url').value = url;

    // 2. Simulamos un clic en el botón de "REPRODUCIR" para que aproveche toda tu lógica existente
    document.getElementById('btn-play-action').click();

    // (Opcional) Te lleva automáticamente a la pestaña del reproductor para que veas la barra
    switchToTab('page-player');
}

// Eliminar canción (Hueco preparado para el siguiente paso)
function deleteSongFromList(songId) {
    console.log("Falta programar el Modal para eliminar la canción con ID:", songId);
    // Aquí abriremos el modal oscuro de confirmación
}



// ==========================================
// FUNCIONES PARA LA MINIATURA DE YOUTUBE
// ==========================================
function extractYouTubeID(url) {
    if (!url) return null;
    // Expresión regular que detecta cualquier tipo de enlace de YouTube y saca la ID (11 letras/números)
    const regExp = /^.*(youtu.be\/|v\/|u\/\w\/|embed\/|watch\?v=|&v=)([^#\&\?]*).*/;
    const match = url.match(regExp);
    return (match && match[2].length === 11) ? match[2] : null;
}

function updateThumbnail(url) {
    const imgEl = document.getElementById('thumbnail-image');
    const emptyEl = document.getElementById('empty-state-preview');
    const videoId = extractYouTubeID(url);

    if (videoId) {
        // Usamos hqdefault.jpg porque funciona siempre, incluso en vídeos antiguos
        imgEl.src = `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;
        imgEl.style.display = 'block';
        emptyEl.style.display = 'none';
    } else {
        // Si no hay enlace o está mal escrito, volvemos a la imagen rota
        imgEl.src = '';
        imgEl.style.display = 'none';
        emptyEl.style.display = 'flex';
    }
}

// ==========================================
// ACCIONES: DESPLEGABLE DE AÑADIR CANCIONES
// ==========================================
const dropdownAddSong = document.getElementById('dropdown-add-song');

// 1. Abrir/Cerrar el desplegable al darle al "+"
document.getElementById('btn-add-song').addEventListener('click', e => {
    e.stopPropagation();
    dropdownAddSong.style.display = dropdownAddSong.style.display === 'flex' ? 'none' : 'flex';
});

// Cerrar si clicamos fuera
document.addEventListener('click', e => {
    if (dropdownAddSong.style.display === 'flex' && !dropdownAddSong.contains(e.target)) {
        dropdownAddSong.style.display = 'none';
    }
});

// 2. OPCIÓN A: Añadir UNA sola canción
document.getElementById('btn-add-single-song').addEventListener('click', () => {
    dropdownAddSong.style.display = 'none';

    let currentPlaylistName = "LA LISTA";
    const selectedItem = document.querySelector('.playlist-item.selected .pl-title');
    if (selectedItem) currentPlaylistName = selectedItem.innerText.toUpperCase();

    const content = `
        <div class="input-group" style="text-align: left;">
            <label>YOUTUBE URL</label>
            <input type="text" id="input-new-song-url" placeholder="Ejemplo: https://www.youtube.com/watch?v=Z9MF6zxNCag" required>
            <p id="error-msg-add-song" style="color: var(--danger); font-size: 10px; font-weight: 600; margin-top: 6px; display: none;">
                <iconify-icon icon="mdi:alert-circle" style="vertical-align: middle; font-size: 12px;"></iconify-icon> 
                Esta canción ya existe en esta lista de reproducción.
            </p>
        </div>
        <div class="modal-actions" style="margin-top: 15px;">
            <button type="button" class="btn btn-solid" id="btn-confirm-add-song">AGREGAR CANCIÓN A "${currentPlaylistName}"</button>
        </div>
    `;

    showDynamicModal('mdi:music-note-plus', 'AÑADIR CANCIÓN', 'Pega el enlace del vídeo de YouTube', content);
    setTimeout(() => document.getElementById('input-new-song-url').focus(), 100);

    document.getElementById('btn-confirm-add-song').addEventListener('click', async () => {
        const urlInput = document.getElementById('input-new-song-url');
        const rawUrl = urlInput.value.trim();
        const errorMsg = document.getElementById('error-msg-add-song');
        const videoId = extractYouTubeID(rawUrl);

        urlInput.style.borderColor = 'var(--border-color)';
        errorMsg.style.display = 'none';

        if (rawUrl === "" || !videoId) {
            urlInput.style.borderColor = 'var(--danger)';
            setTimeout(() => urlInput.style.borderColor = 'var(--border-color)', 1000);
            return;
        }

        // 🚨 MAGIA: Limpiamos la URL para dejar solo la ID del vídeo. 
        // Así, venga de donde venga, la base de datos siempre verá la misma URL.
        const cleanUrl = "https://www.youtube.com/watch?v=" + videoId;

        const btn = document.getElementById('btn-confirm-add-song');
        btn.innerText = "VERIFICANDO EN BASE DE DATOS...";
        btn.style.opacity = "0.7";
        btn.style.pointerEvents = "none";

        let songTitle = "Canción Desconocida";
        let songAuthor = "Autor Desconocido";

        try {
            const res = await fetch(`https://noembed.com/embed?dataType=json&url=${encodeURIComponent(cleanUrl)}`);
            const data = await res.json();
            if (data.title) songTitle = data.title;
            if (data.author_name) songAuthor = data.author_name;
        } catch (e) { }

        // Enviamos la URL limpia a Lua
        fetchToLua('addSongToPlaylist', {
            playlistId: currentSelectedPlaylistId,
            url: cleanUrl,
            title: songTitle,
            author: songAuthor
        });
    });
});

// 3. OPCIÓN B: Importar lista de YT a la lista actual
document.getElementById('btn-import-yt-to-list').addEventListener('click', () => {
    dropdownAddSong.style.display = 'none';

    let currentPlaylistName = "LA LISTA";
    const selectedItem = document.querySelector('.playlist-item.selected .pl-title');
    if (selectedItem) currentPlaylistName = selectedItem.innerText.toUpperCase();

    const content = `
        <div class="input-group" style="text-align: left;">
            <label>URL DE LA LISTA DE YOUTUBE</label>
            <input type="text" id="input-yt-to-list-url" placeholder="Ejemplo: https://youtube.com/playlist?list=PLhDolX..." required>
        </div>
        <div class="modal-actions" style="margin-top: 15px;">
            <button type="button" class="btn btn-solid" id="btn-confirm-yt-import-existing">INYECTAR CANCIONES A "${currentPlaylistName}"</button>
        </div>
    `;

    showDynamicModal('logos:youtube-icon', 'IMPORTAR MULTITUD', 'Añade un máximo de 50 canciones de golpe a tu lista', content);
    setTimeout(() => document.getElementById('input-yt-to-list-url').focus(), 100);

    document.getElementById('btn-confirm-yt-import-existing').addEventListener('click', () => {
        const input = document.getElementById('input-yt-to-list-url');
        const url = input.value.trim();

        const listRegex = /[?&]list=([^#\&\?]+)/;
        const match = url.match(listRegex);

        if (!match || !match[1]) {
            input.style.borderColor = 'var(--danger)';
            setTimeout(() => input.style.borderColor = 'var(--border-color)', 1000);
            return;
        }

        const btn = document.getElementById('btn-confirm-yt-import-existing');
        btn.innerText = "DESCARGANDO DATOS (PUEDE TARDAR)...";
        btn.style.opacity = "0.7";
        btn.style.pointerEvents = "none";

        // IMPORTANTE: Le pasamos también la ID de la playlist que tenemos abierta en pantalla
        fetchToLua('importYouTubeToExistingPlaylist', {
            ytPlaylistId: match[1],
            playlistId: currentSelectedPlaylistId
        });
    });
});

// Función que ejecuta lo que Lua (Base de Datos) responda
function handleAddSongResult(status) {
    const btn = document.getElementById('btn-confirm-add-song');
    const urlInput = document.getElementById('input-new-song-url');
    const errorMsg = document.getElementById('error-msg-add-song');

    if (!btn) return; // Por si el modal se cerró con el fondo oscuro

    if (status === "duplicate") {
        // La Base de Datos dice que ya existe. Mostramos error rojo y restauramos botón.
        urlInput.style.borderColor = 'var(--danger)';
        errorMsg.style.display = 'block';

        let currentPlaylistName = "LA LISTA";
        const selectedItem = document.querySelector('.playlist-item.selected .pl-title');
        if (selectedItem) currentPlaylistName = selectedItem.innerText.toUpperCase();

        btn.innerText = `AGREGAR CANCIÓN A "${currentPlaylistName}"`;
        btn.style.opacity = "1";
        btn.style.pointerEvents = "auto";
    } else if (status === "success") {
        // La Base de Datos la guardó. Cerramos el modal.
        document.getElementById('modal-overlay').style.display = 'none';
    }
}

// ==========================================
// 🔀 BOTONES EXTRA: BUCLE Y ALEATORIO
// ==========================================
// BUCLE NORMAL (TODA LA LISTA)
document.getElementById('btn-toggle-loop').addEventListener('click', function () {
    isLoopEnabled = !isLoopEnabled;
    localStorage.setItem('DPBoombox_Loop', isLoopEnabled);
    this.classList.toggle('active-state', isLoopEnabled);

    // Si encendemos este, apagamos el de "1 Canción" obligatoriamente
    if (isLoopEnabled && isLoopSingleEnabled) {
        isLoopSingleEnabled = false;
        localStorage.setItem('DPBoombox_LoopSingle', false);
        document.getElementById('btn-toggle-loop-single').classList.remove('active-state');
    }
});

// BUCLE ÚNICO (UNA SOLA CANCIÓN)
document.getElementById('btn-toggle-loop-single').addEventListener('click', function () {
    isLoopSingleEnabled = !isLoopSingleEnabled;
    localStorage.setItem('DPBoombox_LoopSingle', isLoopSingleEnabled);
    this.classList.toggle('active-state', isLoopSingleEnabled);

    // Si encendemos este, apagamos el "Normal" obligatoriamente
    if (isLoopSingleEnabled && isLoopEnabled) {
        isLoopEnabled = false;
        localStorage.setItem('DPBoombox_Loop', false);
        document.getElementById('btn-toggle-loop').classList.remove('active-state');
    }
});

document.getElementById('btn-toggle-shuffle').addEventListener('click', function () {
    isShuffleEnabled = !isShuffleEnabled;
    localStorage.setItem('DPBoombox_Shuffle', isShuffleEnabled);
    this.classList.toggle('active-state', isShuffleEnabled);

    // Si lo acabamos de encender, generamos la lista aleatoria instantáneamente
    if (isShuffleEnabled) {
        const currentIdx = currentPlaylistSongs.findIndex(song => song.url === currentPlayingUrl);
        generateShuffleQueue(currentIdx);
    }
});

// MOTOR MATEMÁTICO: Genera una cola aleatoria perfecta (Fisher-Yates)
function generateShuffleQueue(currentPlayingIndex = -1) {
    if (!currentPlaylistSongs || currentPlaylistSongs.length === 0) return;

    let indices = currentPlaylistSongs.map((_, i) => i);

    // Si está sonando una, la sacamos temporalmente
    if (currentPlayingIndex !== -1) {
        indices = indices.filter(i => i !== currentPlayingIndex);
    }

    // Barajamos el resto
    for (let i = indices.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [indices[i], indices[j]] = [indices[j], indices[i]];
    }

    // Volvemos a meter la que suena en la posición 0 de la cola
    if (currentPlayingIndex !== -1) {
        indices.unshift(currentPlayingIndex);
        currentShuffleIndex = 0;
    } else {
        currentShuffleIndex = -1;
    }
    shuffleQueue = indices;
}

// ==========================================
// CONTROLES DE ANTERIOR / SIGUIENTE (INTELIGENTES)
// ==========================================
document.getElementById('btn-prev-song').addEventListener('click', playPreviousSong);
document.getElementById('btn-next-song').addEventListener('click', () => playNextSong(false));

// 🚨 NUEVA FUNCIÓN: Fuerza a Lua a destruir y recrear la MISMA canción desde cero
function forceRestartCurrentSong() {
    isBufferingNewSong = true;
    document.getElementById('input-progress').value = 0;
    document.getElementById('current-time').innerText = "00:00";
    clearTimeout(bufferingTimeout);
    bufferingTimeout = setTimeout(() => { isBufferingNewSong = false; }, 8000);

    fetchToLua('playerAction', {
        id: currentRadioId,
        url: currentPlayingUrl,
        volume: document.getElementById('input-volume').value,
        title: document.getElementById('now-playing-title').innerText,
        action: "play"  // Al mandar "play" en vez de "resume", obligamos a Lua a limpiarla
    });
    currentState = "reproduciendo";
    updatePlayButton();
}

function playNextSong(isAutoEnd = false) {
    // 🚨 1. BUCLE DE UNA SOLA CANCIÓN (Solo actúa si la canción terminó sola)
    if (isAutoEnd && isLoopSingleEnabled) {
        forceRestartCurrentSong();
        return;
    }

    // 2. Caso: Canción suelta o lista de 1 sola canción
    if (!currentPlaylistSongs || currentPlaylistSongs.length <= 1) {
        if (isLoopEnabled || (isAutoEnd && isLoopSingleEnabled)) {
            forceRestartCurrentSong();
        } else {
            currentState = "pausado";
            updatePlayButton();
        }
        return;
    }

    const currentIdx = currentPlaylistSongs.findIndex(song => song.url === currentPlayingUrl);

    // 3. MODO ALEATORIO (SHUFFLE)
    if (isShuffleEnabled) {
        if (shuffleQueue.length === 0 || shuffleQueue[currentShuffleIndex] !== currentIdx) {
            generateShuffleQueue(currentIdx);
        }

        if (currentShuffleIndex >= shuffleQueue.length - 1) {
            // Se acabó el ciclo de la lista
            if (isLoopEnabled) {
                const lastSongIdx = shuffleQueue[shuffleQueue.length - 1];
                generateShuffleQueue(-1);
                if (shuffleQueue[0] === lastSongIdx) {
                    [shuffleQueue[0], shuffleQueue[1]] = [shuffleQueue[1], shuffleQueue[0]];
                }
                currentShuffleIndex = 0;
                const nextSong = currentPlaylistSongs[shuffleQueue[currentShuffleIndex]];
                toggleSongPlay(nextSong.url, nextSong.label.replace(/'/g, "\\'"));
            } else {
                currentState = "pausado";
                updatePlayButton();
            }
        } else {
            currentShuffleIndex++;
            const nextSong = currentPlaylistSongs[shuffleQueue[currentShuffleIndex]];
            toggleSongPlay(nextSong.url, nextSong.label.replace(/'/g, "\\'"));
        }
        return;
    }

    // 4. MODO NORMAL (LINEAL)
    if (currentIdx !== -1) {
        let nextIndex = currentIdx + 1;
        if (nextIndex >= currentPlaylistSongs.length) {
            if (isLoopEnabled) {
                nextIndex = 0; // Bucle al principio
            } else {
                currentState = "pausado";
                updatePlayButton();
                return;
            }
        }
        const nextSong = currentPlaylistSongs[nextIndex];
        toggleSongPlay(nextSong.url, nextSong.label.replace(/'/g, "\\'"));
    }
}

function playPreviousSong() {
    const progressInput = document.getElementById('input-progress');
    const currentTime = parseInt(progressInput.value) || 0;

    // Si lleva más de 3 seg o es canción suelta, reinicia la canción actual
    if (currentTime > 3 || !currentPlaylistSongs || currentPlaylistSongs.length <= 1) {
        // Si estaba pausada por haber terminado, forzamos inicio limpio. Si está sonando, rebobinamos rápido.
        if (currentState !== "reproduciendo") {
            forceRestartCurrentSong();
        } else {
            fetchToLua('seekTime', { id: currentRadioId, time: 0 });
        }
        return;
    }

    const currentIdx = currentPlaylistSongs.findIndex(song => song.url === currentPlayingUrl);

    // MODO ALEATORIO (SHUFFLE)
    if (isShuffleEnabled) {
        if (shuffleQueue.length === 0 || shuffleQueue[currentShuffleIndex] !== currentIdx) {
            generateShuffleQueue(currentIdx);
        }
        if (currentShuffleIndex > 0) {
            currentShuffleIndex--;
            const prevSong = currentPlaylistSongs[shuffleQueue[currentShuffleIndex]];
            toggleSongPlay(prevSong.url, prevSong.label.replace(/'/g, "\\'"));
        } else {
            fetchToLua('seekTime', { id: currentRadioId, time: 0 }); // Tope atrás
        }
        return;
    }

    // MODO NORMAL (LINEAL)
    if (currentIdx !== -1) {
        let prevIndex = currentIdx - 1;
        if (prevIndex < 0) {
            if (isLoopEnabled) {
                prevIndex = currentPlaylistSongs.length - 1; // Salto a la última
            } else {
                fetchToLua('seekTime', { id: currentRadioId, time: 0 }); // Tope atrás
                return;
            }
        }
        const prevSong = currentPlaylistSongs[prevIndex];
        toggleSongPlay(prevSong.url, prevSong.label.replace(/'/g, "\\'"));
    }
}

// ==========================================
// 🗑️ ELIMINAR CANCIÓN DE LA LISTA
// ==========================================
function deleteSongFromList(songId, playlistId) {
    // Mandamos la orden directamente al servidor de Lua
    fetchToLua('removeSongFromPlaylist', {
        songId: songId,
        playlistId: playlistId
    });
}

// ==========================================
// ⚙️ PANEL DE AJUSTES
// ==========================================

// BOTÓN: BORRAR TODO (Zona de Peligro)
document.getElementById('setting-delete-all').addEventListener('click', function () {
    // 1. Guardamos el icono original y ponemos uno de carga
    const originalIcon = this.innerHTML;
    this.innerHTML = '<iconify-icon icon="bx:loader-alt"></iconify-icon>';
    this.style.opacity = "0.5";
    this.style.pointerEvents = "none";

    // 2. Mandamos la orden letal a Lua
    fetchToLua('wipeUserData');

    // 3. Limpiamos la memoria del panel (por si tenía listas abiertas)
    currentSelectedPlaylistId = null;
    currentPlaylistSongs = [];
    document.getElementById('songs-section-title').innerText = "SELECCIONA UNA LISTA PARA VER EL CONTENIDO";
    document.getElementById('songs-list-content').innerHTML = `
        <div class="empty-state">
            <iconify-icon icon="mdi:playlist-music-outline"></iconify-icon>
            <p>Haz clic en una lista de arriba para ver sus canciones.</p>
        </div>`;
    document.getElementById('btn-add-song').style.display = 'none';

    // 4. Lo devolvemos a la pestaña principal del reproductor
    setTimeout(() => {
        switchToTab('page-player');

        // Restauramos el botón a su icono original de la papelera
        this.innerHTML = originalIcon;
        this.style.opacity = "1";
        this.style.pointerEvents = "auto";
    }, 800);
});

// SWITCH: MOVER PERSONAJE CON UI ABIERTA (AHORA POR BASE DE DATOS)
document.getElementById('setting-move-ped').addEventListener('change', function (e) {
    moveWhileOpen = e.target.checked;
    fetchToLua('updateMovePref', { status: moveWhileOpen }); // Avisamos a Lua para que actualice la BD
});