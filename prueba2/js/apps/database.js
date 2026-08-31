import { pool } from '../dbs/mysql2.js'
import express from 'express';

const app = express();
const port = 3010;
let contador = 0

const insertProducts = async (producto) => {
  try{
    const result = await pool.query("INSERT INTO productos(nombre) " + "VALUES (?)", [producto]);
    //console.table(result)
    console.log("Los productos se insertaron correctamente")
  } catch(error){
    console.error(error)
  }
}

const createTableProductos = async () => {
  try{
    const [result] = await pool.query(`
      CREATE TABLE productos (
        id INT AUTO_INCREMENT PRIMARY KEY,
        nombre VARCHAR(100) NOT NULL
      )
    `);

    //console.table(result)
    console.log("La tabla se creo exitosamente")
  } catch (error) {
    console.error(error)
  }
}

const getProducts = async () => {
  try{
  const [result] = await pool.query(`SELECT nombre FROM productos`);
    console.table(result);
  } catch(error){
    console.error(error)
  }
}

const emptyTable = async () => {
  try{
    const [result] = await pool.query(`DELETE FROM productos`)
    //console.table(result);
    console.log("La tabla se vacio exitosamente")
  } catch(error){
    console.error(error)
  }
}

createTableProductos();

app.use(express.json());

app.post('/insert', async (req, res) => {
  const producto = req.body.producto;
  contador++;
  await insertProducts(producto);
  console.log('contador:', contador);
  res.send(`Producto insertado correctamente ${producto}, contador: ${contador}`);
});

app.get('/products', async (req, res) => {
  const products = await getProducts();
  res.send(`Productos obtenidos correctamente, contador: ${contador}`)  ;
});

app.delete('/empty', async (req, res) => {
  await emptyTable();
  contador = 0;
  res.send('Tabla vaciada correctamente');
});


app.listen(port, () => {
  console.log(`Servidor escuchando en http://localhost:${port}`);
});