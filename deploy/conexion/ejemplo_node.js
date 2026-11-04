// Conexión TLS a Sypex_SQL (Autonomous Database, tipo de carga APEX) sin cartera.
// SypexSystem es la base original y solo se usa como respaldo de lectura: no conectar ahí.
//
// Modo "thin": no requiere Instant Client, ni ORACLE_HOME, ni wallet.
// Requiere node-oracledb 6 o superior:  npm install oracledb
//
// Variables de entorno:
//   DB_USER            obligatorio. El esquema dueño de las tablas: WKSP_SYPEXWS
//   DB_PASSWORD        obligatorio. Contraseña de ESE esquema (la del workspace APEX)
//   DB_CONNECT_STRING  opcional. Si se omite, se usa la cadena de abajo.
//
// No pongas credenciales en este archivo ni lo ejecutes desde un repo con historial
// público. Usa variables de entorno.
//
// Uso en PowerShell:
//   $env:DB_USER="WKSP_SYPEXWS"; $env:DB_PASSWORD="..."; node deploy/conexion/ejemplo_node.js

const oracledb = require('oracledb');

oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT;

// El SERVICE_NAME se arma con el DB_NAME (GFD...), NO con el display name (Sypex_SQL).
// Dominio del servicio: adb.oraclecloud.com (sin subdominio de región); la región va en el HOST.
// _low está confirmado en esta instancia; _high es el patrón equivalente.
const CONNECT_STRING =
  process.env.DB_CONNECT_STRING ||
  `(DESCRIPTION=
     (RETRY_COUNT=20)(RETRY_DELAY=3)
     (ADDRESS=(PROTOCOL=TCPS)(PORT=1521)(HOST=adb.mx-monterrey-1.oraclecloud.com))
     (CONNECT_DATA=(SERVICE_NAME=GFD7E2575D251AE_SYPEXSQL_high.adb.oraclecloud.com))
     (SECURITY=(SSL_SERVER_DN_MATCH=YES)))`;

async function main() {
  if (!process.env.DB_USER || !process.env.DB_PASSWORD) {
    console.error('Faltan DB_USER y/o DB_PASSWORD en el entorno.');
    console.error('PowerShell: $env:DB_USER="WKSP_SYPEXWS"; $env:DB_PASSWORD="..."');
    process.exitCode = 1;
    return;
  }

  console.log(`node-oracledb ${oracledb.versionString} (thin: ${oracledb.thin})`);
  console.log(`Conectando como ${process.env.DB_USER} ...`);

  let connection;
  try {
    connection = await oracledb.getConnection({
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      connectString: CONNECT_STRING,
    });

    const resultado = await connection.execute(
      `select sysdate                                as fecha,
              user                                   as usuario_sesion,
              sys_context('userenv','current_schema') as esquema_actual,
              sys_context('userenv','service_name')   as servicio,
              sys_context('userenv','db_name')        as base_datos
         from dual`
    );

    console.log('Conexión exitosa a Sypex_SQL:');
    console.log(resultado.rows[0]);
  } catch (error) {
    // Diagnóstico rápido:
    //   ORA-01017 -> usuario/contraseña del esquema. NO es la cadena de conexión.
    //   ORA-28000 / ORA-28001 -> cuenta bloqueada o contraseña expirada.
    //   ORA-12506 -> ACL de la instancia: la IP pública del equipo no está autorizada.
    //               Se arregla en la consola OCI (Network -> Access control list), no en la cadena.
    //   ORA-12560 -> protocolo o puerto incorrectos (TCPS en 1521/1522, nunca TCP).
    //   ORA-29024 -> validación del certificado del servidor.
    //   NJS-xxx -> versión de node-oracledb o parámetro mal armado.
    console.error('Error de conexión:', error.message);
    process.exitCode = 1;
  } finally {
    if (connection) {
      await connection.close();
    }
  }
}

main();
