# Kiro Preventa AWS — Toolkit para el Equipo

Toolkit compartido para usar [Kiro CLI](https://kiro.dev) como **arquitecto senior de preventa AWS**. Incluye templates, steering rules, scripts de levantamiento, y guías para que todo el equipo trabaje con el mismo estándar: levantamiento de reuniones, migraciones, calculadoras y diagramas de arquitectura.

## Qué incluye

```
kiro-preventa-aws/
├── CONTEXTO-KIRO-TEMPLATE.md         ← Template del archivo de contexto (personalizar y copiar)
├── FLUJO-DE-TRABAJO.md               ← Cómo se trabaja con Kiro en el día a día
├── docs/                             ← Guías detalladas
│   ├── guia-calculadoras-aws.md      ← MCPs de pricing + reglas de calculadoras + troubleshooting
│   ├── guia-diagramas-lucid.md       ← Diagramas editables en Lucidchart (Lucid MCP + AWS 2024)
│   ├── guia-levantamiento-especialista.md  ← Cómo generar preguntas quirúrgicas para reuniones
│   ├── guia-migracion-scorecard.md   ← Migración a AWS + Migration Readiness Scorecard + 7 R
│   └── buenas-practicas-y-errores.md ← Lecciones aprendidas (generalizadas)
├── scripts-levantamiento/            ← Scripts para que los clientes levanten su infra
│   ├── aws/levantamiento-aws.sh
│   ├── azure/levantamiento-azure.sh
│   ├── gcp/levantamiento-gcp.sh
│   ├── digitalocean/levantamiento-do.sh
│   ├── codigo/analisis-codigo.sh
│   └── PLANTILLA-Migration-Readiness-Scorecard.md
└── steering/                         ← Reglas que Kiro carga automáticamente en cada sesión
    ├── convenciones-mo.md
    ├── contexto-obligatorio.md
    ├── levantamiento-clientes.md
    ├── mcp-servers.md
    ├── migracion-aws-conocimiento.md
    └── propuestas-morris-opazo.md   ← Formato de propuesta M&O (15 secciones) — cortesía de Nicolás Delgado
```

## Setup Inicial (una sola vez)

### 1. Instalar Kiro CLI
Seguir instrucciones en https://kiro.dev

### 2. Habilitar Knowledge Base
```bash
kiro-cli settings chat.enableKnowledge true
```

### 3. Crear estructura de carpetas
```bash
mkdir -p ~/Documents/clientes/scripts-levantamiento
```

### 4. Copiar y personalizar el template de contexto
```bash
cp CONTEXTO-KIRO-TEMPLATE.md ~/Documents/clientes/CONTEXTO-KIRO.md
```
Editar `~/Documents/clientes/CONTEXTO-KIRO.md` y reemplazar `[TU NOMBRE]`, `[FECHA]`, y agregar tus clientes.

### 5. Copiar scripts de levantamiento
```bash
cp -r scripts-levantamiento/* ~/Documents/clientes/scripts-levantamiento/
```

### 6. Instalar steering files (recomendado)
Los steering files son instrucciones que Kiro carga automáticamente en cada sesión:
```bash
mkdir -p ~/.kiro/steering/
cp steering/*.md ~/.kiro/steering/
```

### 7. Configurar los MCP Servers
Crear/editar `~/.kiro/settings/mcp.json`:
```json
{
  "mcpServers": {
    "aws-pricing-calculator-mcp-server": {
      "command": "npx",
      "args": ["-y", "sample-aws-pricing-calculator-mcp@latest"]
    },
    "aws-pricing-mcp-server": {
      "command": "uvx",
      "args": ["--from", "awslabs-aws-pricing-mcp-server", "awslabs.aws-pricing-mcp-server"]
    },
    "Lucid Software": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://mcp.lucid.app/mcp"]
    }
  }
}
```

| MCP | Para qué | Requiere |
|---|---|---|
| **aws-pricing-calculator-mcp-server** | Crear calculadoras en calculator.aws con link | Node.js 18+ |
| **aws-pricing-mcp-server** | Consultar precios reales en tiempo real (Pricing API) | `uv`/`uvx` + credenciales AWS |
| **Lucid Software** | Diagramas de arquitectura editables en Lucidchart | OAuth (navegador, 1ª vez) |

Detalles y troubleshooting: ver [docs/guia-calculadoras-aws.md](docs/guia-calculadoras-aws.md) y [docs/guia-diagramas-lucid.md](docs/guia-diagramas-lucid.md).

## Uso Diario

### Iniciar sesión de trabajo
Al abrir Kiro CLI:
> "Lee el contexto en Documents/clientes/CONTEXTO-KIRO.md"

### Agregar un cliente nuevo
> "Agrega un nuevo cliente llamado [Nombre]. Proveedor: [AWS/GCP/Azure/DO]"

### Levantar inventario
1. Enviar al cliente el script correspondiente de `scripts-levantamiento/`
2. El cliente lo corre y devuelve los JSONs
3. > "Procesa el inventario de [Cliente] que está en [ruta]"

### Preparar preguntas para una reunión
> "Aquí está el contexto del cliente. Diseña la arquitectura destino, detecta los quiebres, y dame las preguntas de nivel especialista agrupadas por decisión que habilitan."

### Generar calculadora AWS
> "Arma la calculadora AWS para [Cliente] en [región]. [Detalles del sizing/ambientes]"

### Generar diagrama de arquitectura (Lucidchart)
> "Genera el diagrama de arquitectura de [Cliente] en Lucid, vista de producción con Multi-AZ."

Ver el detalle del proceso completo en [FLUJO-DE-TRABAJO.md](FLUJO-DE-TRABAJO.md).

## Reglas Importantes

1. **NUNCA subir datos de clientes a este repo** — solo templates y herramientas genéricas
2. **NUNCA ejecutar comandos de escritura** en cuentas de clientes (modo solo lectura)
3. **NUNCA incluir credentials/tokens** en ningún archivo
4. Las carpetas de clientes son locales y confidenciales
5. **Verificar precios reales** antes de cotizar; **verificar el total** antes de entregar una calculadora
6. **No simplificar** diagramas omitiendo servicios

## Qué puede hacer Kiro con este toolkit

- Procesar inventarios de AWS, GCP, Azure, Digital Ocean
- Generar reportes de infraestructura estructurados
- Preparar preguntas de nivel especialista para reuniones de levantamiento
- Armar calculadoras AWS con pricing real verificado
- Generar diagramas de arquitectura editables en Lucidchart
- Proponer arquitecturas de migración con el Migration Readiness Scorecard y las 7 R
- Analizar costos y optimizaciones
- Actuar como arquitecto senior en reuniones técnicas

## Contribuir

Si mejoras un script, agregas un proveedor, o encuentras una mejor forma de hacer algo:
1. Crea un branch con tu cambio
2. Haz PR al main
3. **No incluir datos de clientes** en el PR

## Créditos

- **Nicolás Delgado** (equipo Morris & Opazo) — autor original del agente interno `MO-Proposals`, del cual
  provienen `steering/propuestas-morris-opazo.md` (plantilla de propuesta de 15 secciones, reglas de
  redacción de criterios y alcances, coherencia numérica y estructura de cierre) y los comportamientos
  verificados del MCP de la calculadora AWS documentados en `steering/mcp-servers.md`. Todo el mérito de
  esa metodología es suyo; aquí se generaliza como estándar compartido del equipo, reutilizando la forma
  y nunca los datos de un cliente.
