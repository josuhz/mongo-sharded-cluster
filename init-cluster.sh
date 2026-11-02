#!/usr/bin/env bash
set -euo pipefail

wait_for_mongo() {
  local service="$1"
  printf 'Esperando a %s...\n' "$service"
  until docker compose exec -T "$service" mongosh --quiet --eval 'quit(db.adminCommand({ ping: 1 }).ok ? 0 : 1)' >/dev/null 2>&1; do
    sleep 2
  done
}

wait_for_primary() {
  local service="$1"
  printf 'Esperando que %s elija un PRIMARY...\n' "$service"
  until docker compose exec -T "$service" mongosh --quiet --eval 'quit(db.hello().isWritablePrimary ? 0 : 1)' >/dev/null 2>&1; do
    sleep 2
  done
}

docker compose up -d cfg1 cfg2 cfg3 shard1a shard1b shard1c shard2a shard2b shard2c

for service in cfg1 cfg2 cfg3 shard1a shard1b shard1c shard2a shard2b shard2c; do
  wait_for_mongo "$service"
done

docker compose exec -T cfg1 mongosh --quiet --eval '
  try {
    rs.status();
    print("cfgRS ya estaba iniciado");
  } catch (error) {
    rs.initiate({
      _id: "cfgRS",
      configsvr: true,
      members: [
        { _id: 0, host: "cfg1:27017" },
        { _id: 1, host: "cfg2:27017" },
        { _id: 2, host: "cfg3:27017" }
      ]
    });
  }
'

docker compose exec -T shard1a mongosh --quiet --eval '
  try {
    rs.status();
    print("shard1RS ya estaba iniciado");
  } catch (error) {
    rs.initiate({
      _id: "shard1RS",
      members: [
        { _id: 0, host: "shard1a:27017" },
        { _id: 1, host: "shard1b:27017" },
        { _id: 2, host: "shard1c:27017" }
      ]
    });
  }
'

docker compose exec -T shard2a mongosh --quiet --eval '
  try {
    rs.status();
    print("shard2RS ya estaba iniciado");
  } catch (error) {
    rs.initiate({
      _id: "shard2RS",
      members: [
        { _id: 0, host: "shard2a:27017" },
        { _id: 1, host: "shard2b:27017" },
        { _id: 2, host: "shard2c:27017" }
      ]
    });
  }
'

wait_for_primary cfg1
wait_for_primary shard1a
wait_for_primary shard2a

docker compose up -d mongos
wait_for_mongo mongos

docker compose exec -T mongos mongosh --quiet --eval '
  const current = db.adminCommand({ listShards: 1 }).shards.map(shard => shard._id);
  if (!current.includes("shard1RS")) {
    sh.addShard("shard1RS/shard1a:27017,shard1b:27017,shard1c:27017");
  }
  if (!current.includes("shard2RS")) {
    sh.addShard("shard2RS/shard2a:27017,shard2b:27017,shard2c:27017");
  }
  sh.status();
'

printf '\nClúster listo. Conéctate con: mongosh mongodb://localhost:27017\n'
