## Requisitos

- Docker version 29.6.1, build 8900f1d

- node v22.21.0

- npm 10.9.4

- npx 10.9.4

- TiDB cluster v8.5.8 

- Multipass 1.16.3

## Objetivo 

- Conseguir un sistema de replicacion usando TiDB, y viendo como implementa el Failover y el rejoin.

## ¿ Que objetivo tiene cada prueba ? 

- Prueba1: Conectarse con 'mysql2' a un cliente TiDB y hacer consultar que lleguen a un TiKV.

- Prueba2: Crear un cluster con 3 nodos TiKV y verificar que los datos escritos en el Leader sean replicados a los Followers.

- Prueba2.1: Usar el mismo entorno de la prueba2, pero comprobar si el sistema de failover es eficaz.

- Prueba3: Agregar Prometheus y Grafana al Docker Compose, para que en el Dashboard de TiDB tenga mas graficos.

- Prueba4: Usando Multipass crear un nodo TiKV y conectarlo al Cluster de la PC original. 
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

<span style="font-size: 25px">**Prueba2:**</span>

Ir hacia la prueba:

```bash
cd prueba2
```

Hacer lo mismo que en la prueba1.

Para probar que la replicaciones funciona hace un INSERT, hay tirar uno de los nodos y ver si sigue devolviendo los datos, si es asi levantarlo de nuevo y bajar el nodo restante:

```bash
curl -X POST http://localhost:3010/insert \
  -H "Content-Type: application/json" \
  -d '{"producto":"INSERT-ejemplo"}'

docker compose stop tikv2

curl http://localhost:3010/products

docker compose start tikv2

docker compose stop tikv3

curl http://localhost:3010/products
```

##

<span style="font-size: 25px">**Prueba2.1:**</span>

Ir hacia la prueba:

```bash
cd prueba2
```

Hacer lo mismo que en la prueba1.

Para probar que el Failover funciona hace un INSERT, hay tirar uno de los nodos y ver si se sigue pudiendo hacer INSERTS, si es asi levantarlo de nuevo y bajar el nodo restante y probar hacer un INSERT:

```bash
docker compose stop tikv1

curl -X POST http://localhost:3010/insert \
  -H "Content-Type: application/json" \
  -d '{"producto":"INSERT-ejemplo"}'

docker compose start tikv1

docker compose stop tikv2

curl -X POST http://localhost:3010/insert \
  -H "Content-Type: application/json" \
  -d '{"producto":"INSERT-ejemplo"}'

docker compose start tikv2

docker compose stop tikv3

curl -X POST http://localhost:3010/insert \
  -H "Content-Type: application/json" \
  -d '{"producto":"INSERT-ejemplo"}'

curl http://localhost:3010/products       
```
##

<span style="font-size: 25px">**Prueba3:**</span>

Ir a la prueba:

```bash
cd prueba3
```

Levantar el Cluster de TiDB, Grafana y Prometheus.

```bash
docker compose up
```

Para entrar al Dashboard de TiDB entrar a esta URL:

<http://localhost:2379/dashboard/>

Ingresar escribiendo "root" en username.

Ir a la parte que dice: "Change Prometheus Addres".

Cambiar en "Service Endpoints" a "Use customized address" y poner de puerto "http://prometheus:9090".

Con eso ya tendrias la mayoria de los graficos del Dashboard de TiDB.

##

<span style="font-size: 25px">**Prueba4:**</span>

Ir a la prueba: 

```bash 
cd prueba4
```

Instalar las dependencias:

```bash
npm i
```

Crear una instania de Multipass:

```bash
multipass launch 26.04 --name tidb-vm1 --cpus 2 --memory 6G --disk 18G
```

Una vez creada la instancia, comproba si se instalo:

```bash
multipass list
```

Si la instancia no esta corriendo, podes iniciarla con:

```bash
multipass start tidb-vm1
```

Entrar a la instancia:

```bash
multipass shell tidb-vm1
```

Actualizar el sistema de la VM:

```bash
sudo apt update
sudo apt upgrade -y
```

Crear usuario y directorios para el TiKV:

```bash
sudo mkdir -p /opt/tikv/bin
sudo mkdir -p /var/lib/tikv
sudo mkdir -p /var/log/tikv

sudo useradd --system \
  --home /var/lib/tikv \
  --shell /usr/sbin/nologin \
  tikv
```

Dar permisos al usuario para acceder a esas carpetas:

```bash
sudo chown -R tikv:tikv /opt/tikv
sudo chown -R tikv:tikv /var/lib/tikv
sudo chown -R tikv:tikv /var/log/tikv
```

Descargar TiKV:

```bash
cd /tmp
wget https://tiup-mirrors.pingcap.com/tikv-v8.5.8-linux-amd64.tar.gz
```

Una vez descargado el modulo, descomprimir el archivo, moverlo a la carpeta que creamos y darle permisos:

```bash
tar -xzf tikv-v8.5.8-linux-amd64.tar.gz

sudo cp /tmp/tikv-server /opt/tikv/bin/

sudo chown tikv:tikv /opt/tikv/bin/tikv-server
sudo chmod +x /opt/tikv/bin/tikv-server
```

Para comprobar si se instalo correctamente verificaremos la version:

```bash
/opt/tikv/bin/tikv-server -V
```

Si devuelve la version, inicia el archivo de configuracion:

```bash
./setup.sh
```

En otra terminal en tu maquina, comproba si en el Cluster se agrego correctamente el nuevo TiKV:

```bash
source .env && curl -s "http://${MULTIPASS_IP}:2379/pd/api/v1/stores" | jq '.stores[] | {
  id: .store.id,
  address: .store.address,
  state: .store.state_name,
  regions: .status.region_count
}'
```

En la salida tendrias que ver dos objetos en la lista. 

ACLARACION:
 Si cuando ejecutas el script de configuracion te salta un error, se puede borrar tanto la configuracion del cluster y de la VM:
```bash
docker compose down -v

multipass exec tidb-vm1 -- sudo systemctl stop tikv
multipass exec tidb-vm1 -- sudo find /var/lib/tikv -mindepth 1 -delete
multipass exec tidb-vm1 -- sudo systemctl restart tikv
multipass exec tidb-vm1 -- sudo systemctl status tikv --no-pager
```

Y volver iniciar el script:

```bash
./setup.sh
```
