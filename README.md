# Kiro Preventa AWS — Toolkit para el Equipo

Toolkit compartido para usar [Kiro CLI](https://kiro.dev) como arquitecto de preventa AWS. Incluye templates, scripts de levantamiento, y configuraciones para que todo el equipo trabaje con el mismo estándar.

## Qué incluye

```
kiro-preventa-aws/
├── CONTEXTO-KIRO-TEMPLATE.md         ← Template del archivo de contexto (personalizar)
├── docs/                             ← Guías detalladas
│   └── guia-calculadoras-aws.md      ← Configuración MCP server + reglas de calculadoras
├── scripts-levantamiento/            ← Scripts para que los clientes levanten su infra
│   ├── aws/levantamiento-aws.sh
│   ├── azure/levantamiento-azure.sh
│   ├── gcp/levantamiento-gcp.sh
│   ├── digitalocean/levantamiento-do.sh
│   └── codigo/analisis-codigo.sh
├── steering/                         ← Reglas que Kiro sigue automáticamente
│   └── convenciones-mo.md
└── ejemplos/                         ← Ejemplos de diagramas y scripts de referencia
    └── diagrama-ejemplo.py
```

## Setup Inicial (una sola vez)

### 1. Instalar Kiro CLI

```bash
# Seguir instrucciones en https://kiro.dev
```

### 2. Habilitar Knowledge Base

```bash
kiro-cli settings chat.enableKnowledge true
```

### 3. Crear estructura de carpetas

```bash
mkdir -p ~/Documents/clientes/scripts-levantamiento
```

### 4. Copiar el template de contexto

```bash
cp CONTEXTO-KIRO-TEMPLATE.md ~/Documents/clientes/CONTEXTO-KIRO.md
```

**Editar** `~/Documents/clientes/CONTEXTO-KIRO.md` y reemplazar:
- `[TU NOMBRE]` por tu nombre
- `[FECHA]` por la fecha actual
- Agregar tus clientes en la sección correspondiente

### 5. Copiar scripts de levantamiento

```bash
cp -r scripts-levantamiento/* ~/Documents/clientes/scripts-levantamiento/
```

### 6. Instalar steering files (opcional pero recomendado)

Los steering files son instrucciones que Kiro carga automáticamente en cada sesión:

```bash
mkdir -p ~/.kiro/steering/
cp steering/convenciones-mo.md ~/.kiro/steering/
```

### 7. Instalar dependencias para diagramas

Para generar diagramas de arquitectura con Python:

```bash
# Instalar la librería Python
pip install --break-system-packages diagrams

# Instalar Graphviz (el motor de renderizado)
# Ubuntu/Debian:
sudo apt-get install -y graphviz

# macOS:
brew install graphviz

# Si no tienes permisos root:
curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xvj -C /tmp bin/micromamba
/tmp/bin/micromamba create -y -p /tmp/gvenv -c conda-forge graphviz
# Luego usar: PATH="/tmp/gvenv/bin:$PATH" python3 diagrama.py
```

### 8. Configurar MCP Server de AWS Pricing Calculator (para calculadoras)

Este es el componente que permite a Kiro crear calculadoras reales en calculator.aws.

**Configuración rápida** — crear/editar `~/.kiro/settings/mcp.json`:

```json
{
  "mcpServers": {
    "aws-pricing-calculator-mcp-server": {
      "command": "npx",
      "args": ["-y", "sample-aws-pricing-calculator-mcp@latest"]
    }
  }
}
```

No requiere API keys ni credenciales AWS. Solo necesita Node.js 18+.

**Para la guía completa** con reglas de estructura, checklist Well-Architected, troubleshooting y todas las convenciones: ver [docs/guia-calculadoras-aws.md](docs/guia-calculadoras-aws.md).

## Uso Diario

### Iniciar sesión de trabajo

Al abrir Kiro CLI, decirle:

> "Lee el contexto en Documents/clientes/CONTEXTO-KIRO.md"

O si ya tienes la Knowledge Base indexada, Kiro lo encontrará automáticamente al buscar.

### Agregar un cliente nuevo

> "Agrega un nuevo cliente llamado [Nombre]. Proveedor: [AWS/GCP/Azure/DO]"

Kiro creará la estructura de carpetas y actualizará el contexto.

### Levantar inventario

1. Enviar al cliente el script correspondiente de `scripts-levantamiento/`
2. El cliente lo corre y devuelve los JSONs
3. Decirle a Kiro: "Procesa el inventario de [Cliente] que está en [ruta]"

### Generar calculadora AWS

> "Arma la calculadora AWS para [Cliente] en [región]. [Detalles del sizing/ambientes]"

Kiro genera el estimate en calculator.aws y guarda el link en `historial-calculadoras.md`.

### Generar diagrama de arquitectura

> "Genera la arquitectura de [Cliente] con el tema de Python"

Kiro genera el `.py` y el `.png` en la carpeta de diagramas del cliente.

## Reglas Importantes

1. **NUNCA subir datos de clientes a este repo** — solo templates y herramientas genéricas
2. **NUNCA ejecutar comandos de escritura** en cuentas de clientes
3. **NUNCA incluir credentials/tokens** en ningún archivo
4. Las carpetas de clientes son locales y confidenciales

## Qué puede hacer Kiro con este toolkit

- Procesar inventarios de AWS, GCP, Azure, Digital Ocean
- Generar reportes de infraestructura estructurados
- Armar calculadoras AWS con pricing real
- Generar diagramas de arquitectura profesionales
- Proponer arquitecturas de migración
- Analizar costos y optimizaciones
- Actuar como arquitecto senior en reuniones técnicas

## Contribuir

Si mejoras un script, agregas un nuevo proveedor, o encuentras una mejor forma de hacer algo:

1. Crea un branch con tu cambio
2. Haz PR al main
3. No incluir datos de clientes en el PR
