import express from "express";

const app = express();
const PORT = 3010;

app.use(express.json());

app.get("/", (req, res) => {
  res.json({
    success: true,
    message: "TiKV API funcionando"
  });
});


// ==========================================
// Registrar nodo TiKV
// ==========================================

app.post("/api/tikv/register", (req, res) => {

  const {
    hostname,
    ip,
    tikv_port,
    status_port,
    version
  } = req.body;


  // Validar datos obligatorios

  if (!hostname || !ip || !tikv_port || !status_port || !version) {
    return res.status(400).json({
      success: false,
      message: "Faltan datos del nodo TiKV"
    });
  }


  // Mostrar información recibida

  console.log("Nuevo nodo TiKV:");
  console.log({
    hostname,
    ip,
    tikv_port,
    status_port,
    version
  });


  // Configuración del cluster

  const pdHost = "192.168.0.47";
  const pdPort = 2379;


  // Respuesta

  res.json({
    success: true,

    cluster: {
      pd: `${pdHost}:${pdPort}`
    },

    node: {
      address: `${ip}:${tikv_port}`,
      status_address: `${ip}:${status_port}`
    }
  });
});




app.listen(PORT, () => {
  console.log(`API escuchando en http://localhost:${PORT}`);
});
