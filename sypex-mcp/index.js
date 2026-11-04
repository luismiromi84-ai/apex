
const { McpServer } = require("@modelcontextprotocol/sdk/server/mcp.js");
const { StdioServerTransport } = require("@modelcontextprotocol/sdk/server/stdio.js");

const ENDPOINT =
  process.env.SYPEX_CLIENTES_URL ||
  "https://gfd7e2575d251ae-sypexsystem.adb.mx-monterrey-1.oraclecloudapps.com/ords/sypexws/sypex/clientes/";

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
