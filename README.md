<div align="center">
  <h1>DP-Boombox_v2</h1>
  <p>¡Un sistema avanzado de altavoces (boombox) para ESX y QBCore, rediseñado desde cero con una UI moderna y funciones colaborativas!</p>
</div>

<h2>🌟 Características Principales</h2>
<ul>
  <li><strong>Interfaz de Usuario (UI) Moderna:</strong> Panel interactivo con pestañas, control dinámico de volumen y previsualizaciones de miniaturas de YouTube.</li>
  <li><strong>Sincronización Perfecta:</strong> Utiliza <code>xsound</code> para reproducir música sincronizada entre todos los jugadores cercanos sin lag.</li>
  <li><strong>Listas de Reproducción Colaborativas:</strong> Crea listas, obtén un código de invitación alfanumérico aleatorio y compártelo para que tus amigos se unan.</li>
  <li><strong>Gestión Avanzada de Permisos:</strong> El dueño de la lista puede decidir quién puede añadir canciones, borrar, o renombrar la lista modificando los permisos en tiempo real.</li>
  <li><strong>Integración Nativa con YouTube API:</strong> ¡Importa listas completas de YouTube (hasta 50 canciones de golpe) directamente a tu base de datos mediante la API de Google!</li>
  <li><strong>Creación Automática de Base de Datos:</strong> Olvídate de importar archivos <code>.sql</code>. El script crea las 4 tablas necesarias (<code>dp_listas_repro</code>, <code>dp_canciones</code>, <code>dp_listas_jugadores</code>, <code>dp_listas_canciones</code>) automáticamente al arrancar.</li>
  <li><strong>Cero Dependencias de 'Target':</strong> Utiliza un sistema nativo y optimizado con TextUI (<code>DP-TextUI</code>) y detección de cercanía matemática.</li>
</ul>

<h2>🛠️ Requisitos</h2>
<ul>
  <li>Framework: <strong>ESX</strong> o <strong>QBCore</strong>.</li>
  <li>Base de datos: <strong>oxmysql</strong>.</li>
  <li>Audio: <strong>xsound</strong>.</li>
</ul>

<h2>📦 Instalación</h2>
<ol>
  <li>Descarga el script y colócalo en tu carpeta <code>resources</code>.</li>
  <li>Abre el archivo <code>config.lua</code> y pon tu <strong>YouTube API Key</strong> (es obligatorio para importar listas completas).</li>
  <li>Añade el ítem configurado en <code>Config.Radios</code> (por defecto <code>speaker</code>) a la base de datos o archivo <code>shared</code> de tu inventario.</li>
  <li>Asegúrate de tener tu recurso <code>DP-TextUI</code> funcionando para que se vean los avisos de las teclas en pantalla.</li>
  <li>Añade <code>ensure DP-Boombox_v2</code> a tu <code>server.cfg</code> (asegúrate de que arranca después de <code>oxmysql</code> y <code>xsound</code>).</li>
</ol>

<h2>🎮 Controles por Defecto</h2>
<ul>
  <li><strong>E</strong> - Abrir el menú del altavoz.</li>
  <li><strong>K</strong> - Coger el altavoz en la mano para llevártelo.</li>
  <li><strong>G</strong> - Recoger el altavoz y guardarlo en el inventario.</li>
</ul>













Ideas:
Ahora mismo el script SOLO funciona con la RADIO normal (Item boombox), para colocarlo en el suelo, bueno pues ahora vamos con lo siguiente, vamos a crear un item que se use/instale en vehiculos, se guarde en base de datos, y que el vehiculo CON RADIO pueda tener musica.
Quiero crear un item para el DP-Inventory/qb-core... que SOLO se pueda usar/instalar estando dentro de un vehiculo, tendra un prograssbar abajo (script progressbar) que una vez usado el item, se quiara, y en la base de datos se guardara una nueva tabla de VEHICULOS que tienen RADIO... como ira? pues no se, guardando matriculas o algo de eso, la verdad es que no tengo idea... lo importante es que NO podran usar una radio de vehiculo hasta que el jugador INSTALE LA RADIO en ese vehiculo!!!
Simplemente una vez instalado, ese vehiculo PARA SIEMPRE tendra radio y no se podra quitar a menos que lo haga el administrador/owner/dev del servidor desde la base de datos... la radio se abrira el panel con el comando '/carradio', indexarlo a un EXPORT así puedo ponerme en otros scripts directamente el export para que me abra la radio con un boton de otro script/menú por ejemplo.

Comprobar que estos funcionen a la perfección:
${generateToggleHTML('perm_rename', 'Renombrar Lista', 'Permitir cambiar el nombre')}
${generateToggleHTML('perm_delete', 'Eliminar Canciones', 'Permitir borrar temas')}
${generateToggleHTML('perm_add', 'Añadir Canciones', 'Permitir guardar nuevos temas')}
${generateToggleHTML('perm_reorder', 'Cambiar Orden', 'Permitir mover canciones')}
${generateToggleHTML('perm_manage', 'Gestionar Personas', 'Permitir editar permisos')}
${generateToggleHTML('perm_future1', 'Opción Futura 1', 'Reservado')}
${generateToggleHTML('perm_future2', 'Opción Futura 2', 'Reservado')}
