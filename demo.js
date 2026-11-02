// Este archivo se ejecuta conectado al router mongos.
const demoDB = db.getSiblingDB("tienda");

// La colección se crea vacía; MongoDB podrá crear el índice de shard key.
if (!demoDB.getCollectionNames().includes("usuarios")) {
  demoDB.createCollection("usuarios");
}

// Distribuye por hash del userId. Si ya está configurada, se ignora ese error.
try {
  sh.shardCollection("tienda.usuarios", { userId: "hashed" });
} catch (error) {
  if (!String(error).includes("already sharded")) {
    throw error;
  }
}

// Permite volver a ejecutar la demostración sin acumular duplicados.
demoDB.usuarios.deleteMany({});

// Inserta datos de prueba en lotes para no construir un arreglo enorme.
for (let start = 1; start <= 20000; start += 1000) {
  const batch = [];
  for (let userId = start; userId < start + 1000; userId++) {
    batch.push({
      userId,
      nombre: `Usuario ${userId}`,
      provincia: ["San José", "Alajuela", "Cartago", "Heredia"][userId % 4]
    });
  }
  demoDB.usuarios.insertMany(batch, { ordered: false });
}

print("Documentos insertados:", demoDB.usuarios.countDocuments());
print("Distribución por shard:");
printjson(demoDB.usuarios.getShardDistribution());
