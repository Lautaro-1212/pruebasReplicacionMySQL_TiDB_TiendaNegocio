## Requisitos

- Docker version 29.6.1, build 8900f1d

- node v22.21.0

- npm 10.9.4

- npx 10.9.4

- TiDB cluster v8.5.8 

## Objetivo 

- Conseguir un sistema de replicacion usando TiDB, y viendo como implementa el Failover y el rejoin.

## ¿ Que objetivo tiene cada prueba ? 

- Prueba1: Conectarse con 'mysql2' a un cliente TiDB y hacer consultar que lleguen a un TiKV.

- Prueba2: Crear un cluster con 3 nodos TiKV y verificar que los datos escritos en el Leader sean replicados a los Followers.
##

<span style="font-size: 30px">**Como probar cada prueba:**</span>

<span style="font-size: 20px">**ACLARACIONES:**</span>

1) Para ejecutar cualquier comando que este relacionado con Docker, te tenes que para pruebaX/config/

2) Para hacer los consultas del CRUD siempre van a ser estos comando:

Crear la tabla:

```bash
curl http://localhost:3010/create
```

Hacer un INSERT:

```bash
curl -X POST http://localhost:3010/insert \
  -H "Content-Type: application/json" \
  -d '{"producto":"INSERT-ejemplo"}'
```

Hacer un GET: 

```bash
curl http://localhost:3010/products
```

Hacer un DELETE:

```bash
curl -X DELETE http://localhost:3010/empty
```

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

En otra terminal probar libremente las operaciones:

##

<span style="font-size: 25px">**Prueba1:**</span>

Ir hacia la prueba

```bash
cd prueba2
```

Hacer lo mismo que en la prueba1.

Para probar que la replicaciones existe hace un INSERT, hay tirar uno de los nodos y ver si sigue devolviendo los datos, si es asi levantarlo de nuevo y bajar el nodo restante:

```bash
docker compose stop tikv2

curl http://localhost:3010/products

docker compose start tikv2

docker compose stop tikv3

curl http://localhost:3010/products
```






