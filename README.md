<p align="center">
<h1 align="center">🎵 [FiveM] ¡EL SISTEMA DE MÚSICA DEFINITIVO! | DP-Boombox_v2 🎵</h1>

<img width="960" height="auto" align="center" alt="DP-Boombox_v2" src="Images (Can Remove it if u want)/Miniaturas YT.png" />

</p>

<div align="center">

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![FiveM](https://img.shields.io/badge/FiveM-Script-important)](https://fivem.net/)
[![ESX](https://img.shields.io/badge/ESX-Framework-red)](https://github.com/esx-framework)
[![QBCore](https://img.shields.io/badge/QBCore-Framework-success)](https://github.com/qbcore-framework)

</div>

<h2 align="center"> 📝 Descripción General</h2>
¡Lleva la fiesta a cualquier rincón de tu servidor! <b>DP-Boombox_v2</b> es un sistema de música interactivo, avanzado y colaborativo diseñado por DP-Scripts. Con una interfaz moderna y sincronización perfecta, los jugadores podrán crear listas de reproducción, compartir códigos de invitación, importar canciones directamente desde YouTube, instalar radios en sus vehículos y gestionar permisos de DJ en tiempo real.

<details>
<summary><h2 align="center">¿Qué es y qué hace?</h2></summary>
Es el ecosistema musical definitivo para tus jugadores. Entre sus múltiples sistemas integrados destacan:
<br><br>
- <b>🎨 Interfaz de Usuario (UI) Moderna:</b> Panel interactivo con pestañas, previsualizaciones nativas de YouTube y un tooltip inteligente de volumen que sigue a tu ratón. <br>
- <b>🖼️ Mosaicos Dinámicos de Listas:</b> Las portadas de las playlists se generan automáticamente creando un collage estilo Spotify con hasta 5 miniaturas de las canciones que contienen. <br>
- <b>🔀 Controles Multimedia Avanzados:</b> Sistema de reproducción inteligente con opciones de <b>Aleatorio (Shuffle matemático)</b>, <b>Repetir Lista (Loop)</b> y <b>Repetir 1 Canción</b>, con salto automático. <br>
- <b>🚗 Sistema de Radio para Vehículos:</b> Permite a los mecánicos o jugadores instalar un ítem de radio en cualquier vehículo con una barra de progreso y animaciones, accesible después mediante un comando. <br>
- <b>🎧 Sincronización Perfecta (xsound):</b> Reproduce música sincronizada entre todos los jugadores cercanos sin lag ni cortes molestos, tanto en altavoces de suelo como en coches. <br>
- <b>🤝 Listas Colaborativas y Compartibles:</b> Crea listas, copia al portapapeles un código de invitación alfanumérico aleatorio y compártelo para que tus amigos se unan. <br>
- <b>👑 Gestión Avanzada de Permisos:</b> El dueño de la lista puede decidir quién puede añadir canciones, borrar o renombrar la lista, o traspasar la propiedad modificando los permisos al instante. <br>
- <b>🌐 Integración Nativa con YouTube API:</b> ¡Importa listas completas de YouTube (hasta 50 canciones de golpe) directamente a la boombox o inyéctalas a una lista existente mediante la API de Google! <br>
- <b>🖱️ Drag & Drop Anti-Colisión:</b> Modo edición premium para arrastrar la UI libremente. Incluye un sistema que detecta los bordes de la pantalla e invierte las pestañas laterales para evitar que el menú se salga o se oculte. <br>
- <b>🎯 Cero Dependencias de 'Target':</b> Utiliza un sistema nativo y optimizado con TextUI (`DP-TextUI`) y detección de cercanía matemática. <br>
</details>

<details>
<summary><h2 align="center">¿Cómo funciona?</h2></summary>
Una vez que el jugador utiliza el ítem del altavoz (por defecto <code>speaker</code>), este aparecerá en el mundo. Al acercarse, el sistema detecta la distancia matemáticamente y muestra las opciones en pantalla usando el <code>DP-TextUI</code>. También cuenta con soporte para radios de coche instalables (ítem <code>vehicle_radio</code>), accesibles mediante el comando <code>/carradio</code>.
<br><br>
El jugador puede interactuar con el altavoz usando teclas rápidas (<b>E</b> para abrir la interfaz, <b>K</b> para llevarlo en la mano, <b>G</b> para guardarlo). Dentro del menú interactivo, se pueden crear listas, generar códigos de invitación, importar playlists enteras con un link de YouTube y modificar los permisos de los oyentes. Además, el script guarda en base de datos las preferencias del usuario, como si prefiere moverse mientras el menú está abierto o la posición exacta de la interfaz en su pantalla.
</details>

<details>
<summary><h2 align="center">¿Qué te permite?</h2></summary>
✅ Reproducir música sincronizada en tiempo real sin lag en suelo o en vehículos 🎶.<br>
✅ Reproducir listas en modo Aleatorio (Shuffle) o Bucle (Loop) 🔀.<br>
✅ Visualizar portadas dinámicas en mosaico estilo Spotify 🖼️.<br>
✅ Importar de golpe hasta 50 canciones desde YouTube 📥.<br>
✅ Compartir la sesión como DJ con amigos mediante códigos secretos 🔑.<br>
✅ Gestionar permisos de quién añade o quita canciones 🛡️.<br>
✅ Traspasar la propiedad de una lista a otro jugador 👑.<br>
✅ Coger, mover y transportar el altavoz en la mano mientras suena 🚶‍♂️.<br>
✅ Arrastrar la UI libremente y guardar la posición (con sistema anti-colisión de bordes) 🖱️.<br>
✅ Función de borrado completo (Wipe) de datos y listas por usuario 🗑️.<br>
</details>
<br><br>
<h2 align="center"> 🚀 Instalación</h2>

<details>
<summary><h2 align="center">Requisitos previos</h2></summary>
- Servidor FiveM con <b>QBCore</b> o <b>ESX</b> instalado y actualizado.<br>
- Base de datos MySQL configurada (<b>oxmysql</b>).<br>
- Sistema de audio (<b>xsound</b>).<br>
- Sistema de notificaciones en pantalla (<b>DP-TextUI</b>).<br>
</details>

<details>
<summary><h2 align="center">Pasos de instalación</h2></summary>
1. **Descargar el script** y colocar la carpeta en tu servidor dentro del directorio `resources`.<br>
   - ⚠️ <i>Asegúrate de que el nombre de la carpeta sea exactamente `DP-Boombox_v2`.</i><br>
2. **Base de Datos (IMPORTANTE)**.<br>
   - Aunque las tablas principales se crean solas, **DEBES ejecutar el archivo `dp-boombox_v2.sql`** en tu base de datos para crear/actualizar la tabla `dp_preferences`, vital para guardar la posición de la UI y los ajustes de movimiento de los jugadores.<br>
3. **Configuración de la API**.<br>
   - Abre el archivo `config.lua` y pega tu <b>YouTube API Key</b> (obligatorio para la importación de listas de reproducción completas).<br>
4. **Configuración de los Ítems**.<br>
   - Añade el ítem del altavoz configurado en `Config.Radios` (por defecto `speaker`) y el de la radio del coche `Config.CarRadio.ItemInstall` (por defecto `vehicle_radio`) a la base de datos o al archivo `shared` de tu inventario.<br>
5. **Dependencias visuales**.<br>
   - Asegúrate de tener tu recurso `DP-TextUI` funcionando para que se vean los avisos de las teclas en pantalla.<br>
6. **Asegurar el recurso**.<br>
   - Añade `ensure DP-Boombox_v2` a tu `server.cfg`.<br>
   - ⚠️ <i>IMPORTANTE: Asegúrate de iniciarlo DESPUÉS de `oxmysql` y `xsound`.</i><br>
</details>
<br><br>

<h2 align="center"> 📂 Estructura del Script</h2>
<pre>
DP-Boombox_v2
├── 📁 client
│   ├── 📄 client.lua
│   └── 📄 functions.lua
├── 📁 server
│   └── 📄 server.lua
├── 📁 ui
│   ├── 🌐 index.html
│   ├── 📄 script.js
│   └── 🎨 style.css
├── 📝 README.md
├── 📄 config.lua
├── 📄 fxmanifest.lua
└── 💾 dp-boombox_v2.sql
</pre>
<br>

<h2 align="center"> 🎮 Controles por Defecto y Comandos</h2>
<div align="center">
  <b>[E]</b> - Abrir el menú del altavoz. <br>
  <b>[K]</b> - Coger el altavoz en la mano para llevártelo. <br>
  <b>[G]</b> - Recoger el altavoz y guardarlo en el inventario. <br>
  <b>/carradio</b> - Abrir el menú de la radio en un vehículo con radio instalada. <br>
</div>
<br><br>

<h2 align="center"> ⚙️ Dependencias</h2>
Este script está diseñado para funcionar nativamente con entornos QBCore y ESX.

<details>
<summary><h2 align="center">📦 Requisitos del Sistema</h2></summary>

| Recurso                                                                                 | Descripción / Estado |
| --------------------------------------------------------------------------------------- | -------------------- |
| <img src="https://placehold.co/20x20/555555/FFFFFF?text=FW" alt="FW"> **ESX / QB-Core** | 🔴 OBLIGATORIO       |
| <img src="https://placehold.co/20x20/555555/FFFFFF?text=SQL" alt="SQL"> **oxmysql**     | 🔴 OBLIGATORIO       |
| <img src="https://placehold.co/20x20/555555/FFFFFF?text=SND" alt="SND"> **xsound**      | 🔴 OBLIGATORIO       |
| <img src="https://placehold.co/20x20/555555/FFFFFF?text=DP" alt="DP"> **DP-TextUI**     | 🔴 OBLIGATORIO       |

</details>
<br><br>

<h2 align="center"> 🖼️ Vistas Previas</h2>
Explora el poder y el diseño de las distintas secciones del boombox.

<summary><h2>Reproductor Principal y Controles Avanzados</h2></summary>
<img width="350" height="auto" src="Images (Can Remove it if u want)/canción.png" />
<br><br>

<summary><h2>Biblioteca y Mosaicos Dinámicos</h2></summary>
<img width="350" height="auto" src="Images (Can Remove it if u want)/listas.png" />
<br><br>

<summary><h2>Gestión de Permisos en Tiempo Real</h2></summary>
<img width="350" height="auto" src="Images (Can Remove it if u want)/permisos.png" />
<br><br>

<summary><h2>Modo Edición Libre (Drag & Drop)</h2></summary>
<img width="350" height="auto" src="Images (Can Remove it if u want)/posicionamiento.png" />
<br><br>

<summary><h2>Ajustes y Zona de Peligro</h2></summary>
<img width="350" height="auto" src="Images (Can Remove it if u want)/ajustes.png" />
<br><br>

<h2 align="center"> 🎥 Video Demostrativo</h2>
<p align="center">
<summary><h2 align="center">Ver Funcionamiento</h2></summary>
<a href="https://youtu.be/i92WUuU7Pb4">
<img width="959" height="auto" alt="Video Demostrativo DP-Boombox_v2" src="Images (Can Remove it if u want)/Miniaturas YT.png" />
</a>
</p>
<br><br>

<h2 align="center"> 🔮 Posibles Mejoras Futuras</h2>
El script ya es increíblemente completo, pero siempre se puede ir a más.

<details>
<summary><h2 align="center">🚧 Roadmap y Sugerencias</h2></summary>

| IDEA                           | EXPLICACIÓN                                                                                              |
| ------------------------------ | -------------------------------------------------------------------------------------------------------- |
| **Soporte Spotify/Soundcloud** | Integración de APIs de otras plataformas de streaming de música populares.                               |
| **Más Modelos de Altavoces**   | Inclusión de props de boombox personalizados y radios antiguas para distintas vibras.                    |
| **Efectos Visuales (VFX)**     | Partículas o luces de neón en el prop que reaccionen a los graves de la música (Audio visualizer en 3D). |

</details>

---

<div align="center">
<b>Autor:</b> DP-Scripts<br>
<b>Versión:</b> 1.2.5
</div>
