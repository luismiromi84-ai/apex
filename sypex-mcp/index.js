
const { McpServer } = require("@modelcontextprotocol/sdk/server/mcp.js");
const { StdioServerTransport } = require("@modelcontextprotocol/sdk/server/stdio.js");

// Instancia de trabajo: Sypex_SQL (GFD7E2575D251AE_SYPEXSQL).
// SypexSystem (GFD7E2575D251AE_SYPEXSYSTEM) es el respaldo de solo lectura: este
// servidor NO debe consultarlo nunca, ni siquiera para "comprobar conexion".
const HOST_TRABAJO = "gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com";

const ENDPOINT =
  process.env.SYPEX_CLIENTES_URL ||
  `https://${HOST_TRABAJO}/ords/sypexws/sypex/clientes/`;

// Candado: si el endpoint apunta a otra instancia, no se inicia el servidor.
(function validarEndpoint() {
  let host = "";
  try {
    host = new URL(ENDPOINT).host.toLowerCase();
  } catch (error) {
    console.error(`SYPEX_CLIENTES_URL no es una URL válida: ${ENDPOINT}`);
    process.exit(1);
  }

  if (!host.includes("sypexsql")) {
    console.error(
      `SYPEX_CLIENTES_URL apunta a "${host}". La instancia de trabajo es Sypex_SQL ` +
      `(${HOST_TRABAJO}). SypexSystem es respaldo de solo lectura: corrige opencode.json.`
    );
    process.exit(1);
  }
})();

const server = new McpServer({
  name: "sypex-mcp",
  version: "1.0.0"
});

async function consultarAPI() {
  const response = await fetch(ENDPOINT, {
    method: "GET",
    headers: {
      Accept: "application/json"
    },
    signal: AbortSignal.timeout(15000)
  });

  if (!response.ok) {
    if (response.status === 404) {
      throw new Error(
        `el módulo ORDS ${new URL(ENDPOINT).pathname} no existe en Sypex_SQL (HTTP 404). ` +
        "Hay que crearlo en la instancia de trabajo; no se consulta SypexSystem."
      );
    }
    throw new Error(`ORDS respondió HTTP ${response.status}`);
  }

  const contentType = response.headers.get("content-type") || "";

  if (!contentType.includes("application/json")) {
    throw new Error("ORDS no devolvió contenido JSON");
  }

  return await response.json();
}

server.registerTool(
  "sypex_estado_api",
  {
    description: "Comprueba la disponibilidad del servicio REST de clientes SYPEX."
  },
  async () => {
    try {
      const data = await consultarAPI();

      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            disponible: true,
            registros: data.count,
            hasMore: data.hasMore
          }, null, 2)
        }]
      };
    } catch (error) {
      return {
        content: [{
          type: "text",
          text: `Error consultando SYPEX: ${error.message}`
        }],
        isError: true
      };
    }
  }
);

server.registerTool(
  "sypex_listar_clientes",
  {
    description: "Consulta los clientes publicados por SYPEX mediante Oracle ORDS."
  },
  async () => {
    try {
      const data = await consultarAPI();

      return {
        content: [{
          type: "text",
          text: JSON.stringify(data, null, 2)
        }]
      };
    } catch (error) {
      return {
        content: [{
          type: "text",
          text: `Error consultando clientes: ${error.message}`
        }],
        isError: true
      };
    }
  }
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch(error => {
  console.error("Error iniciando SYPEX-MCP:", error);
  process.exit(1);
});
