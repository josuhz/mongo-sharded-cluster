# MongoDB Sharded Cluster with Docker

Laboratorio académico de Bases de Datos II para practicar cómo trabajan juntos el sharding y la replicación en MongoDB.

## Qué incluye

- Un replica set de configuración (`cfgRS`) con tres config servers.
- Dos shards (`shard1RS` y `shard2RS`).
- Tres réplicas por shard.
- Un router `mongos` como punto de conexión.
- Una colección `tienda.usuarios` distribuida por el hash de `userId`.

## Ejecutar

Requisitos: Docker y Docker Compose.

```bash
git clone https://github.com/josuhz/mongo-sharded-cluster.git
cd mongo-sharded-cluster
chmod +x init-cluster.sh
./init-cluster.sh