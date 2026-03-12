// ==========================================
// 1. VARIABLES GLOBALES
// ==========================================
let currentRadioId = null;
let currentState = "detenido";
let currentPlayingUrl = "";
let isDraggingProgress = false;

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

        case "updateTime":
            if (!isDraggingProgress) updateProgressBar(data);
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
    updateVolumeUI(50); // Sincronizamos el UI al abrir

    // QUE SE VEA LA FOTO NADA MÁS ABRIR EL MENÚ
    updateThumbnail(currentPlayingUrl);

    const titleBox = document.getElementById('now-playing-title');
    if ((currentState === "reproduciendo" || currentState === "pausado") && data.title) {
        titleBox.innerText = data.title;
        titleBox.style.color = 'var(--success)';
    } else {
        titleBox.innerText = 'SIN CANCIÓN';
        titleBox.style.color = 'var(--primary-color)';
    }

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
    // Aseguramos que solo busque DENTRO del botón circular de la barra multimedia
    const btn = document.querySelector('.media-center #btn-play-action');

    // Si por algún motivo el botón no existe en el DOM, no hacemos nada y evitamos el error
    if (!btn) return;

    const iconElement = btn.querySelector('iconify-icon');

    // Si no encuentra el icono dentro, tampoco hacemos nada
    if (!iconElement) return;

    // Cambiamos el icono según el estado
    if (currentState === "reproduciendo") {
        iconElement.setAttribute('icon', 'mdi:pause-circle');
    } else {
        iconElement.setAttribute('icon', 'mdi:play-circle');
    }

    // Bloqueamos el botón si el input de URL está vacío
    const urlInput = document.getElementById('input-url');
    if (urlInput) {
        btn.disabled = (urlInput.value.trim() === "");
    }
}

function updateProgressBar(data) {
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
    fetchToLua('seekTime', { id: currentRadioId, time: e.target.value });
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
        // Si es una URL nueva, preparamos el icono de Play
        iconElement.setAttribute('icon', 'mdi:play-circle');
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
    const url = document.getElementById('input-url').value;
    if (!url) return;

    let action = "play";
    if (url === currentPlayingUrl) {
        action = (currentState === "reproduciendo") ? "pause" : "resume";
    }

    let fetchedTitle = document.getElementById('now-playing-title').innerText;

    if (action === "play") {
        document.getElementById('now-playing-title').innerText = "CARGANDO...";
        document.getElementById('now-playing-title').style.color = 'var(--primary-color)';
        try {
            const res = await fetch(`https://noembed.com/embed?dataType=json&url=${encodeURIComponent(url)}`);
            const data = await res.json();
            fetchedTitle = data.title || "URL Personalizada";
        } catch { fetchedTitle = "URL Personalizada"; }

        document.getElementById('now-playing-title').innerText = fetchedTitle;
        document.getElementById('now-playing-title').style.color = 'var(--success)';
        currentPlayingUrl = url;
        currentState = "reproduciendo";
    } else {
        currentState = (action === "pause") ? "pausado" : "reproduciendo";
    }

    updatePlayButton();
    fetchToLua('playerAction', {
        id: currentRadioId, url: url, volume: document.getElementById('input-volume').value,
        title: fetchedTitle, action: action
    });
});

// ==========================================
// 5. SISTEMA DE TABS (PESTAÑAS)
// ==========================================
const tabTitles = {
    'page-player': { title: 'Altavoz', subtitle: 'Acciones e interacciones rápidas' },
    'page-saved-songs': { title: 'Tu biblioteca', subtitle: 'Gestiona tu música favorita' },
    'page-settings': { title: 'Ajustes', subtitle: 'Configuración avanzada' }
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

// RENDERIZAR PLAYLISTS AL RECIBIRLAS DE LUA
function renderPlaylists(listas) {
    const container = document.getElementById('library-content');
    container.innerHTML = '';

    if (!listas || listas.length === 0) {
        container.innerHTML = `
            <div class="empty-state">
                <iconify-icon icon="solar:playlist-minimalistic-broken"></iconify-icon>
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
            <div class="pl-cover"></div>
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
// NUEVO: LÓGICA DE CANCIONES Y SELECCIÓN
// ==========================================
function selectPlaylist(id, name) {
    currentSelectedPlaylistId = id;

    // 1. Efecto visual: Marcamos la lista seleccionada en verde
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
    const container = document.getElementById('songs-list-content');
    const title = document.getElementById('songs-section-title');

    title.innerText = `Canciones de "${playlistName}" (${songs.length})`;
    container.innerHTML = '';

    if (songs.length === 0) {
        container.innerHTML = `
            <div class="empty-state">
                <iconify-icon icon="mdi:playlist-music-outline"></iconify-icon>
                <p>Esta lista no tiene canciones.</p>
                <p style="color: var(--primary-color);">Dale al botón + de arriba para añadir</p>
            </div>`;
        return;
    }

    // Pintamos las canciones igual que las listas para que mantenga el diseño
    songs.forEach(song => {
        const div = document.createElement('div');
        div.className = 'playlist-item'; // Reutilizamos el estilo de tu CSS
        div.innerHTML = `
            <div class="pl-info">
                <span class="pl-title">${song.label}</span>
                <span class="pl-role">${song.author || 'Sin autor'}</span>
            </div>
            <div class="pl-actions">
                <button class="btn-icon" title="Reproducir" onclick="playSong('${song.url}')">
                    <iconify-icon icon="mdi:play"></iconify-icon>
                </button>
                <button class="btn-icon delete" title="Eliminar" onclick="deleteSongFromList(${song.id}, ${currentSelectedPlaylistId})">
                    <iconify-icon icon="mdi:trash-can"></iconify-icon>
                </button>
            </div>
        `;
        container.appendChild(div);
    });
}

// ACCIÓN: CREAR PLAYLIST (Pagar texto dinámico)
document.getElementById('btn-create-playlist').addEventListener('click', () => {
    dropdownAddPlaylist.style.display = 'none';

    // HTML dinámico usando clases CSS (input-group para textAlign:left, modal-actions para gap/margin)
    const content = `
        <div class="input-group">
            <label>NOMBRE DE LA LISTA</label>
            <input type="text" id="input-new-playlist" placeholder="Ej: Canciones de Rol..." required>
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
        this.innerHTML = '<iconify-icon icon="mdi:check-bold" style="color: var(--success);"></iconify-icon>';
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

    // Si puede renombrar, mostramos el input; si no, lo ocultamos guardando el valor.
    const renameHtml = canRename ? `
        <div class="input-group" style="text-align: left;">
            <label>RENOMBRAR LA LISTA</label>
            <input type="text" id="input-edit-name" value="${playlist.name}" required>
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
                btnConfirm.style.background = "var(--success)";
                btnConfirm.style.borderColor = "var(--success)";
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