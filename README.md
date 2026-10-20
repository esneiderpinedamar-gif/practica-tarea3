# Práctica guiada · Tarea 3 (Gestión y Almacenamiento de Datos · 203008068)

Entorno 100 % en línea: **GitHub Codespaces** con MySQL 8.4, **CloudBeaver** (editor SQL web) y **Grafana**.

## Arranque (una sola vez)
1. Suba esta carpeta a un repositorio de GitHub (botón **Add file → Upload files**, incluida la carpeta `.devcontainer`).
   Si la carpeta `.devcontainer` no sube, use **Add file → Create new file**, escriba el nombre `.devcontainer/devcontainer.json` y pegue su contenido.
2. En el repositorio: **Code → Codespaces → Create codespace on main**. Espere 2–3 minutos.
3. Cuando la terminal diga *Entorno listo*, abra la pestaña **PORTS**: 8978 = CloudBeaver, 3000 = Grafana.
4. Arrastre `Anexo_3 - Database.csv` a la carpeta `datos/` del explorador.

## CloudBeaver (primera vez)
- Asistente inicial: cree el usuario administrador de CloudBeaver.
- Nueva conexión **MySQL**: Host `mysql` · Puerto `3306` · Usuario `root` · Clave `Clase_UNAD_2026`.
- En **Driver properties** agregue `allowPublicKeyRetrieval = true` y `useSSL = false` (si no, aparece *Public Key Retrieval is not allowed*).

## Terminal MySQL (para medir en los Pasos 2 y 3)
```
docker exec -it mysql_clase mysql -uroot -p taller_ventas
```

## Grafana
`admin` / `admin` la primera vez. Data Source MySQL: Host `mysql:3306`, base `taller_ventas`, usuario `grafana_ro`.

## Cuota gratuita
La cuenta gratuita de GitHub incluye 120 horas-núcleo al mes (60 h en una máquina de 2 núcleos). **Detenga el codespace al terminar**: en github.com/codespaces, junto al codespace, **… → Stop codespace**.

El script completo, paso a paso, está en `practica_tarea3.sql`.

## Clase modelo del docente (caso Movilidad Caribe)
El mismo codespace sirve para la clase modelo. Arrastre `movilidad_caribe.csv` a la carpeta `datos/` y siga `clase_modelo_movilidad.sql`
(base `demo_movilidad`, tabla `validaciones`; terminal: `docker exec -it mysql_clase mysql -uroot -p demo_movilidad`;
Grafana: usuario `grafana_demo`, clave `Lectura_Demo_2026`).
