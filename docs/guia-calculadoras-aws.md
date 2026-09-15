# Guía Completa: Calculadoras AWS con Kiro CLI

Esta guía explica cómo configurar y usar Kiro CLI para generar calculadoras de AWS Pricing Calculator de forma automatizada. Con esta configuración, Kiro puede crear estimates completos en calculator.aws y entregarte un link compartible — sin que toques la interfaz web.

---

## Requisitos Previos

- [Kiro CLI](https://kiro.dev) instalado y configurado
- Node.js 18+ (para ejecutar el MCP server via npx)
- Knowledge Base habilitada en Kiro (`kiro-cli settings chat.enableKnowledge true`)

---

## 0. Dos MCPs, un flujo (IMPORTANTE)

Para calculadoras se usan **dos** MCP servers complementarios:

| MCP | Para qué | Cuándo |
|---|---|---|
| **aws-pricing-mcp-server** (awslabs) | Consultar precios REALES en tiempo real desde la Pricing API | ANTES de armar la calculadora, para verificar costos |
| **aws-pricing-calculator-mcp-server** | Crear/exportar el estimate en calculator.aws con link compartible | Para construir la calculadora con precios ya validados |

**Flujo correcto:**
1. Consultar precios reales con `aws-pricing-mcp-server`
2. Armar la calculadora con `aws-pricing-calculator-mcp-server`
3. Exportar y verificar con `import_estimate` (markdown)
4. Solo entregar si el total tiene sentido

Configuración del segundo MCP (Pricing API en tiempo real):
```json
{
  "mcpServers": {
    "aws-pricing-mcp-server": {
      "command": "uvx",
      "args": ["--from", "awslabs-aws-pricing-mcp-server", "awslabs.aws-pricing-mcp-server"]
    }
  }
}
```
Requiere `uv`/`uvx` instalado y credenciales AWS (`aws configure`) con lectura en Pricing API (us-east-1).

---

## 1. Configuración del MCP Server (Calculadora)

### Qué es

El **AWS Pricing Calculator MCP Server** es un servidor [Model Context Protocol](https://modelcontextprotocol.io/) que le da a Kiro la capacidad de interactuar programáticamente con [calculator.aws](https://calculator.aws). Sin esto, Kiro no puede crear calculadoras reales.

- **Repo oficial:** https://github.com/aws-samples/sample-aws-pricing-calculator-mcp
- **Paquete npm:** `sample-aws-pricing-calculator-mcp`

### Instalación

No requiere instalación previa — se ejecuta automáticamente via `npx`. Solo necesitas configurar el archivo MCP de Kiro.

### Configuración

Editar (o crear) el archivo de configuración MCP de Kiro:

```bash
# La ubicación del archivo depende de tu instalación de Kiro CLI
# Opción 1: ~/.kiro/settings/mcp.json
# Opción 2: ~/.config/kiro-cli/mcp.json
# Verificar cuál usa tu instalación con: find ~ -name "mcp.json" -path "*kiro*"
```

Contenido del archivo `mcp.json`:

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

> **Nota:** El flag `-y` acepta automáticamente la instalación del paquete. `@latest` asegura que siempre uses la versión más reciente.

### Verificar que funciona

Después de configurar, inicia una nueva sesión de Kiro CLI y pídele:

> "Busca el servicio EC2 en la calculadora AWS"

Si responde con resultados de búsqueda del pricing calculator, el MCP server está funcionando correctamente.

---

## 2. Herramientas Disponibles

Una vez configurado, Kiro tiene acceso a estas herramientas:

| Herramienta | Qué hace |
|---|---|
| `search_services` | Buscar servicios disponibles en la calculadora |
| `get_service_fields` | Ver los campos de configuración de un servicio |
| `create_estimate` | Crear un estimate vacío |
| `add_service` | Agregar un servicio configurado al estimate |
| `build_estimate` | Todo en uno: crear + agregar servicios + exportar |
| `validate_estimate` | Validar que el estimate está bien antes de guardar |
| `export_estimate` | Guardar y obtener el link compartible |
| `import_estimate` | Importar un estimate existente para revisión o modificación |

### Particiones soportadas

- `aws` — Regiones comerciales estándar
- `aws-iso` — GovCloud ISO
- `aws-iso-b` — GovCloud ISO-B
- `aws-eusc` — European Sovereign Cloud

---

## 3. Cómo Usar las Calculadoras

### Flujo básico

1. **Provee contexto al Kiro:** Describe la infraestructura del cliente (servicios actuales, ambientes, sizing, carga esperada)
2. **Kiro propone la arquitectura:** Infiere servicios, sizing, pricing model
3. **Kiro presenta resumen:** Antes de construir, muestra un resumen para validación rápida
4. **Kiro construye:** Genera el estimate en calculator.aws y te da el link

### Ejemplo de prompt

> "Arma la calculadora para [Cliente] en us-east-1. Tienen un EKS con 3 nodos en producción (m5.xlarge), Aurora PostgreSQL Multi-AZ, y un ambiente de desarrollo con lo mínimo."

### Ejemplo de prompt con migración

> "El cliente viene de GCP con: 3 VMs e2-standard-4, Cloud SQL PostgreSQL con HA, un bucket de 500GB, y Cloud Run con 2M requests/mes. Arma la calculadora AWS equivalente en us-east-1."

---

## 4. Reglas de Estructura (para que todas las calculadoras sean consistentes)

### Jerarquía obligatoria

```
Nombre del Estimate (nombre del proyecto/cliente)
├── [Ambiente 1] (ej: "Cuenta Producción")
│   ├── [Categoría de servicio]/
│   │   └── servicios...
│   ├── [Categoría de servicio]/
│   │   └── servicios...
│   └── ...
├── [Ambiente 2] (ej: "Cuenta Test", "Cuenta Desarrollo")
│   ├── [Categoría de servicio]/
│   │   └── servicios...
│   └── ...
└── [Ambiente N] (si hay más)
```

### Categorías de servicio estándar

| Categoría | Servicios que incluye |
|---|---|
| **Cómputo** | EC2, ECS/Fargate, EKS, Lambda, App Runner, ALB/NLB, EFS |
| **Bases de Datos** | RDS, Aurora, DynamoDB, ElastiCache, DocumentDB, Redshift |
| **Almacenamiento** | S3, EBS (si es standalone), Glacier |
| **Networking** | VPC (NAT Gateways), WAF, CloudFront, Route 53, Transit Gateway, VPN |
| **CI/CD** | CodePipeline, CodeBuild, CodeDeploy, ECR, CodeArtifact |
| **Seguridad** | KMS, Secrets Manager, Shield Advanced, GuardDuty, Security Hub |
| **Mensajería** | SQS, SNS, EventBridge, Kinesis, MSK |
| **Monitoreo** | CloudWatch (logs, métricas, alarmas), X-Ray |
| **Analítica** | Athena, Glue, EMR, QuickSight, Redshift |
| **Frontend** | Amplify, CloudFront (si es para frontend), Cognito |

### Sizing por ambiente

- **Producción:** HA (multi-AZ), instancias dimensionadas a la carga real, réplicas de lectura si aplica, NAT Gateway redundante
- **Test/Staging:** Single-AZ, instancias más chicas (bajar 1-2 tiers), sin réplicas, 1 NAT Gateway
- **Desarrollo:** Mínimo viable, instancias burstable (t3/t4g), sin HA, storage reducido

### Pricing model

No hay default fijo. Se decide según el contexto:
- **On-Demand:** baseline para propuestas iniciales, workloads variables, ambientes no-prod
- **Reserved Instances / Savings Plans:** workloads steady-state en producción cuando el cliente se compromete a 1-3 años
- **Spot:** workloads batch, procesamiento tolerante a interrupciones

---

## 5. Completitud: Well-Architected Checklist

Toda calculadora debe reflejar una infraestructura **completa y funcional**. Antes de entregar, Kiro valida internamente:

| Si la calculadora tiene... | DEBE tener también... | Pilar WA |
|---|---|---|
| Cómputo (EC2, ECS, EKS) | ALB o NLB frente a los nodos | Fiabilidad |
| Exposición pública (ALB, API Gateway, CloudFront) | WAF | Seguridad |
| Ambiente de Producción | Multi-AZ en cómputo y bases de datos | Fiabilidad |
| Bases de datos en Producción | Backups automáticos + réplica de lectura si aplica | Fiabilidad |
| Recursos en subnets privadas que salen a internet | NAT Gateway (redundante en Prod) | Networking |
| Cualquier servicio | CloudWatch (al menos métricas y alarmas básicas) | Excelencia Operativa |
| Dominio o tráfico DNS | Route 53 | Completitud |
| Datos sensibles o regulados | KMS (cifrado en reposo) | Seguridad |
| Contenedores (ECS/EKS) | ECR para imágenes | Completitud |
| Lambda o servicios serverless | CloudWatch Logs (retención definida) | Excelencia Operativa |
| Almacenamiento S3 en Producción | Lifecycle policies + versionado (notas) | Optimización de Costos |
| Más de una cuenta/ambiente | Networking entre ambientes si se comunican | Networking |

---

## 6. Trazabilidad de Calculadoras

### Historial obligatorio por cliente

Cada vez que se genera una calculadora, registrarla en:
```
[Cliente]/calculadoras/historial-calculadoras.md
```

Formato:
```markdown
# Historial de Calculadoras AWS — [Cliente]

| # | Fecha | Descripción | Link | Notas |
|---|---|---|---|---|
| 1 | 2026-07-12 | Migración inicial - 3 ambientes | [Ver](https://calculator.aws/#/estimate?id=...) | Desde GCP |
| 2 | 2026-07-15 | Ajuste sizing producción | [Ver](https://calculator.aws/#/estimate?id=...) | +RDS Proxy |
```

### Versionamiento

- Cada versión es un archivo separado: `calculadora-[cliente]-YYYY-MM-DD.md`
- Si hay correcciones el mismo día: sufijo v1, v2, v3
- NUNCA sobreescribir versiones anteriores

### Estructura por cliente
```
[Cliente]/calculadoras/
├── historial-calculadoras.md              ← OBLIGATORIO: tabla con TODOS los links
├── calculadora-[cliente]-2026-07-12.md    ← detalle de cada calculadora
├── calculadora-[cliente]-2026-07-13.md
└── ...
```

---

## 7. Notas de Entrega

Al entregar cada calculadora, Kiro siempre incluye:

- **Supuestos de tráfico/carga:** con qué volumen se calculó
- **Horizonte de la estimación:** mensual puro o con compromisos a 1-3 años
- **Componentes agregados:** servicios que se agregaron para completitud (WAF, NAT, CloudWatch, etc.)
- **Decisiones de sizing:** por qué se eligió cada tipo de instancia
- **Trade-offs:** si se sacrificó algo (costo vs rendimiento, simplicidad vs resiliencia)

---

## 8. Migración entre Clouds

Cuando el contexto viene de otro proveedor:

1. Mapear cada servicio al equivalente AWS
2. NO hacer un 1:1 ciego — evaluar si hay mejor opción en AWS
3. Considerar servicios nativos AWS que simplifiquen la arquitectura
4. Señalar oportunidades de modernización (VMs → contenedores, polling → eventos)
5. Mantener paridad funcional como mínimo, mejorar donde sea evidente

### Tabla de equivalencias rápida

| Origen | Servicio | Equivalente AWS |
|---|---|---|
| GCP | Compute Engine | EC2 |
| GCP | GKE | EKS |
| GCP | Cloud Run | App Runner / ECS Fargate |
| GCP | Cloud Functions | Lambda |
| GCP | Cloud SQL | RDS |
| GCP | Cloud Spanner | Aurora / DynamoDB |
| GCP | BigQuery | Redshift / Athena |
| GCP | GCS | S3 |
| GCP | Pub/Sub | SQS + SNS / EventBridge |
| GCP | Memorystore | ElastiCache |
| Azure | Virtual Machines | EC2 |
| Azure | AKS | EKS |
| Azure | App Service | Elastic Beanstalk / App Runner |
| Azure | Azure Functions | Lambda |
| Azure | Azure SQL | RDS SQL Server / Aurora |
| Azure | Cosmos DB | DynamoDB |
| Azure | Blob Storage | S3 |
| Azure | Service Bus | SQS + SNS |
| Azure | Azure DevOps | CodePipeline + CodeBuild |
| DO | Droplets | EC2 |
| DO | Managed Kubernetes | EKS |
| DO | Managed Databases | RDS |
| DO | Spaces | S3 |
| DO | App Platform | App Runner |

---

## 9. Troubleshooting

### El MCP server no responde
```bash
# Verificar que Node.js está instalado
node --version  # Debe ser 18+

# Probar manualmente que npx puede ejecutar el paquete
npx -y sample-aws-pricing-calculator-mcp@latest --help

# Verificar que el archivo mcp.json está en la ubicación correcta
find ~ -name "mcp.json" -path "*kiro*"
```

### La calculadora se genera con $0
- Asegúrate de especificar la **región**. Sin región, muchos servicios no calculan precio.
- Para Lambda: necesita `sizeOfMemoryAllocated`, `storageAmountEphemeral`, y `architecture` para producir precio.
- Para EC2: necesita el instance type explícito.

### Servicios que el MCP NO maneja bien (quedan en $0) — LECCIÓN CRÍTICA
Los servicios con **`columnFormIPM`** (tabla de instancias) suelen quedar en **$0** al exportar vía MCP:
- **RDS** (`columnFormIPM`)
- **ElastiCache** (`columnFormIPMDT` + `columnFormIPM_dsp` + `columnFormIPM`)
- **SageMaker** (`columnFormIPM` dentro de subServices)
- **Fargate** con `taskDuration` en formato incorrecto → usar `{"value":"30","unit":"day"}`, NO `{"value":"720","unit":"hour"}`

**Regla:** NUNCA reconstruir una calculadora completa con el MCP si tiene RDS, ElastiCache o SageMaker — esos servicios son la mayoría del costo y quedan en $0. Lo correcto:
1. Investigar precios reales (aws-pricing-mcp-server o web AWS)
2. Calcular los incrementos con esos precios
3. Dar instrucciones EXACTAS de edición manual en calculator.aws
4. NO crear links rotos

**Servicios que el MCP SÍ maneja bien:** S3, Fargate (taskDuration en "day"), NLB, WAF, CloudWatch, Route 53, VPN, NAT Gateway, Data Transfer, Secrets Manager, ECR.

### Verificación obligatoria antes de entregar
**NUNCA entregar un link sin verificar el precio total primero:**
1. `export_estimate` → link
2. `import_estimate` (markdown) → verificar Total Monthly Cost
3. Si es $0 o muy bajo → NO entregar, diagnosticar, corregir
4. Solo entregar cuando el precio verificado coincida con lo esperado

### El estimate se guarda pero está "frozen" (no editable)
- Ejecutar `validate_estimate` antes de `export_estimate` para verificar que el payload es válido.
- Verificar que no hay campos con valores inválidos (IDs de dropdown que no existen, unidades incorrectas).

### Error "needs_field_grounding"
- Significa que Kiro intentó usar un servicio sin antes consultar sus campos con `get_service_fields`.
- Solución: pedir a Kiro que consulte los campos del servicio primero.

---

## 10. Tips para Mejores Resultados

1. **Sé específico con el sizing:** "3 nodos m5.xlarge" es mejor que "un cluster mediano"
2. **Menciona los ambientes:** Si no dices cuántos ambientes, Kiro asumirá solo producción
3. **Indica la región:** Si no la mencionas, Kiro te preguntará antes de proceder
4. **Provee contexto de carga:** requests/seg, GB almacenados, usuarios concurrentes ayudan a dimensionar
5. **Si vienes de otro cloud:** Comparte el inventario o describe qué tienes hoy — Kiro traduce
6. **Pide que valide antes de exportar:** "Valida el estimate antes de guardarlo" evita errores

---

## Referencia: Configuración completa del MCP Server

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

**Ubicación del archivo:** `~/.kiro/settings/mcp.json`

No requiere API keys, tokens, ni credenciales AWS. El MCP server interactúa directamente con la API pública de calculator.aws.
