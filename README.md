# Laboratorio: clúster sharded de MongoDB con Docker

Este laboratorio crea una arquitectura completa para practicar **replicación** y **sharding**:

- `cfgRS`: tres nodos que guardan los metadatos del clúster.
- `shard1RS`: primer shard, replicado en tres nodos.
- `shard2RS`: segundo shard, replicado en tres nodos.
- `mongos`: router al que se conectan las aplicaciones.

En total se ejecutan nueve procesos `mongod` y un router `mongos`. Cada shard tiene un factor de replicación de 3. Es una configuración educativa local, sin autenticación; no debe exponerse a Internet.

## 1. Levantar los contenedores

Desde esta carpeta:

```bash
docker compose up -d cfg1 cfg2 cfg3 shard1a shard1b shard1c shard2a shard2b shard2c
docker compose ps
```

La primera descarga puede tardar porque se utiliza la imagen `mongo:8.0.32-noble`.

## 2. Iniciar el replica set de configuración

```bash
docker compose exec cfg1 mongosh
```

Dentro de `mongosh`:

```javascript
rs.initiate({
  _id: "cfgRS",
  configsvr: true,
  members: [
    { _id: 0, host: "cfg1:27017" },
    { _id: 1, host: "cfg2:27017" },
    { _id: 2, host: "cfg3:27017" }
  ]
})
```

Comprueba la elección del nodo primario:

```javascript
rs.status()
```

Luego sal:

```javascript
exit
```

## 3. Iniciar el primer shard replicado

```bash
docker compose exec shard1a mongosh
```

```javascript
rs.initiate({
  _id: "shard1RS",
  members: [
    { _id: 0, host: "shard1a:27017" },
    { _id: 1, host: "shard1b:27017" },
    { _id: 2, host: "shard1c:27017" }
  ]
})

rs.status()
exit
```

## 4. Iniciar el segundo shard replicado

```bash
docker compose exec shard2a mongosh
```

```javascript
rs.initiate({
  _id: "shard2RS",
  members: [
    { _id: 0, host: "shard2a:27017" },
    { _id: 1, host: "shard2b:27017" },
    { _id: 2, host: "shard2c:27017" }
  ]
})

rs.status()
exit
```

## 5. Iniciar el router `mongos`

```bash
docker compose up -d mongos
docker compose exec mongos mongosh
```

Agrega ambos replica sets como shards:

```javascript
sh.addShard("shard1RS/shard1a:27017,shard1b:27017,shard1c:27017")
sh.addShard("shard2RS/shard2a:27017,shard2b:27017,shard2c:27017")
sh.status()
```

Todas las operaciones de la aplicación deben pasar por `mongos`. Desde la computadora anfitriona, la URI es:

```text
mongodb://localhost:27017
```

## 6. Crear y shardear una colección de ejemplo

Todavía dentro de la consola conectada a `mongos`:

```javascript
use tienda

db.createCollection("usuarios")

sh.shardCollection(
  "tienda.usuarios",
  { userId: "hashed" }
)
```

`userId` es la shard key. El valor `"hashed"` indica que MongoDB aplicará una función hash para repartir usuarios entre los shards. Como la colección está vacía, MongoDB crea automáticamente el índice que necesita la shard key.

Inserta 20 000 usuarios:

```javascript
for (let start = 1; start <= 20000; start += 1000) {
  const batch = [];

  for (let userId = start; userId < start + 1000; userId++) {
    batch.push({
      userId,
      nombre: `Usuario ${userId}`,
      provincia: ["San José", "Alajuela", "Cartago", "Heredia"][userId % 4]
    });
  }

  db.usuarios.insertMany(batch)
}
```

Revisa la configuración y distribución:

```javascript
sh.status()
db.usuarios.getShardDistribution()
db.usuarios.getIndexes()
db.usuarios.find({ userId: 5000 }).explain("executionStats")
```

El balanceador puede tardar un poco en mover los chunks. Puedes volver a ejecutar `getShardDistribution()` después de unos segundos.

## 7. Verificar la replicación y probar un fallo

Muestra cuál miembro del primer shard es primario:

```bash
docker compose exec shard1a mongosh --quiet --eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))'
```

Detén una réplica secundaria que aparezca como `SECONDARY`, por ejemplo:

```bash
docker compose stop shard1b
```

La consulta por medio de `mongos` debe seguir funcionando:

```bash
docker compose exec mongos mongosh --quiet --eval 'db.getSiblingDB("tienda").usuarios.findOne({ userId: 5000 })'
```

Vuelve a levantar el nodo:

```bash
docker compose start shard1b
```

Si deseas probar una elección automática, identifica el `PRIMARY`, detén ese contenedor y observa cómo uno de los secundarios pasa a ser primario. No detengas dos miembros del mismo replica set, porque se perdería la mayoría de 2 sobre 3 y el shard ya no podría aceptar escrituras.

## 8. Inicialización automática opcional

En Linux, macOS o Git Bash:

```bash
chmod +x init-cluster.sh
./init-cluster.sh
```

Después puedes cargar los datos de ejemplo automáticamente:

```bash
docker compose exec -T mongos mongosh --quiet < demo.js
```

## 9. Detener o reiniciar

Detener sin borrar datos:

```bash
docker compose down
```

Volver a iniciar conservando datos:

```bash
docker compose up -d
```

Borrar contenedores y datos del laboratorio:

```bash
docker compose down -v
```

El último comando elimina los volúmenes; úsalo solamente cuando quieras empezar completamente desde cero.

## Explicación del `compose.yaml`

### Encabezado y configuración compartida

| Línea o bloque | Explicación sencilla |
|---|---|
| `name: mongo-sharded-lab` | Define el nombre visible del proyecto en Docker Compose. |
| `x-mongo-common:` | Crea un bloque auxiliar reutilizable; no levanta ningún contenedor. |
| `&mongo-common` | Asigna el nombre `mongo-common` al bloque para reutilizarlo después. |
| `image: mongo:8.0.32-noble` | Usa una versión fija de MongoDB 8.0 sobre Ubuntu Noble. Fijar la versión evita cambios inesperados de `latest`. |
| `restart: unless-stopped` | Reinicia un contenedor que falle, excepto cuando tú lo detienes expresamente. |
| `networks: - mongo-cluster` | Conecta cada contenedor a la red privada del laboratorio. |
| `healthcheck:` | Le enseña a Docker cómo comprobar si MongoDB ya responde. |
| `test: ... ping ...` | Ejecuta un `ping` administrativo dentro del contenedor. |
| `interval: 5s` | Repite la prueba cada cinco segundos. |
| `timeout: 3s` | Considera fallida una prueba que tarde más de tres segundos. |
| `retries: 30` | Tolera hasta 30 fallos antes de marcar el contenedor como no saludable. |
| `start_period: 10s` | Da diez segundos iniciales para arrancar antes de contar fallos. |

### Servicios `cfg1`, `cfg2` y `cfg3`

| Línea o bloque | Explicación sencilla |
|---|---|
| `services:` | A partir de aquí se declaran los contenedores. |
| `cfg1:` | Nombre que Docker y los demás contenedores usan para encontrar este nodo. |
| `<<: *mongo-common` | Copia dentro del servicio la configuración compartida anterior. |
| `hostname: cfg1` | Establece el nombre interno del equipo dentro del contenedor. |
| `command: ["mongod", ...]` | Sustituye el comando normal de la imagen y arranca el servidor MongoDB. |
| `--configsvr` | Indica que el nodo guardará metadatos del clúster sharded. |
| `--replSet cfgRS` | Declara que pertenece al replica set llamado `cfgRS`. |
| `--port 27017` | Hace que MongoDB escuche en su puerto estándar. |
| `--bind_ip_all` | Permite conexiones desde otros contenedores de la red Docker. |
| `volumes: - cfg1-data:/data/db` | Guarda los archivos de MongoDB en un volumen persistente. |

`cfg2` y `cfg3` repiten la misma configuración, pero cada uno tiene un nombre y volumen distintos. Los tres forman el replica set `cfgRS` cuando se ejecuta `rs.initiate()`.

### Servicios de los shards

| Línea o bloque | Explicación sencilla |
|---|---|
| `shard1a`, `shard1b`, `shard1c` | Son las tres copias del primer shard. |
| `--shardsvr` | Indica que el proceso almacenará datos de aplicación como parte de un shard. |
| `--replSet shard1RS` | Agrupa los tres nodos dentro del mismo replica set. |
| `shard1a-data:/data/db` | Cada nodo recibe su propio almacenamiento; no deben compartir el mismo volumen. |
| `shard2a`, `shard2b`, `shard2c` | Son las tres copias del segundo shard. |
| `--replSet shard2RS` | Agrupa esos nodos en el segundo replica set. |

Las letras `a`, `b` y `c` identifican réplicas del mismo shard. Los números `1` y `2` identifican conjuntos de datos diferentes.

### Router `mongos`

| Línea o bloque | Explicación sencilla |
|---|---|
| `mongos:` | Declara el router del clúster. No almacena los documentos de la aplicación. |
| `command: - mongos` | Ejecuta el proceso router en vez del servidor `mongod`. |
| `--configdb` | Le indica dónde consultar los metadatos del clúster. |
| `cfgRS/cfg1:27017,...` | Especifica el nombre del replica set de configuración y sus tres miembros. |
| `depends_on:` | Retrasa el inicio del router hasta que los tres config servers respondan al healthcheck. |
| `condition: service_healthy` | Exige que cada config server figure como saludable. |
| `127.0.0.1:27017:27017` | Publica el router únicamente en la computadora local. Izquierda: host; derecha: contenedor. |

### Red y volúmenes

| Línea o bloque | Explicación sencilla |
|---|---|
| `networks:` | Declara las redes administradas por Compose. |
| `driver: bridge` | Crea una red privada virtual dentro de Docker. |
| `volumes:` | Declara los almacenamientos persistentes usados anteriormente. |
| Cada nombre terminado en `-data` | Representa el disco independiente de un nodo MongoDB. |

## Ideas importantes

- **Shard no significa nodo:** cada shard de este laboratorio es un replica set de tres nodos.
- **Sharding distribuye datos distintos:** una parte queda en `shard1RS` y otra en `shard2RS`.
- **Replicación copia cada parte:** los tres miembros de cada replica set guardan copias de los datos asignados a su shard.
- **La aplicación usa `mongos`:** el router sabe qué shard consultar.
- **`cfgRS` no guarda los usuarios:** guarda el mapa que permite a `mongos` encontrar cada parte.
