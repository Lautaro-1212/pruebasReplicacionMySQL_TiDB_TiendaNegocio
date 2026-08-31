## Requisitos

- Docker version 29.6.1, build 8900f1d

- node v22.21.0

- npm 10.9.4

- npx 10.9.4

- TiDB cluster v8.5.8 

## Objetivo 

- Conseguir un sistema de replicacion usando TiDB.

## ¿ Que objetivo tiene cada prueba ? 

- Prueba1: Conectarse con 'mysql2' a un cliente TiDB y hacer consultar que lleguen a un TiKV.

- Prueba2: Crear un cluster con 3 nodos TiKV y verificar que los datos escritos en el Leader sean replicados a los Followers.
##
<span style="font-size: 30px">**Como probar cada prueba:**</span>

<span style="font-size: 20px">**ACLARACIONES:**</span>

1) Para ejecutar cualquier comando que este relacionado con Docker, te tenes que para pruebaX/config/

##

<span style="font-size: 25px">**Prueba1:**</span>

Ir hacia la prueba

```bash
cd prueba1
```

Instalar las dependencias:

```bash
npm i
```

Iniciar el Clubster TiDB con docker compose: 

```bash
docker compose up
```

En otra terminar levantar el servidor de Express para poder mandar las consultas:

```bash
cd js/apps
node database.js
```

En otra terminal primero crea la tabla con curl o Postman:

```bash
curl http://localhost:3010/create
```

Hacer un INSERT: 

```bash
curl -X POST http://localhost:3010/insert \
  -H "Content-Type: application/json" \
  -d '{"producto":"prueba1-ejemplo"}'
```

Hacer un GET:
```bash
curl http://localhost:3010/products
```

Hacer un DELETE:

```bash
curl -X DELETE http://localhost:3010/empty
```


