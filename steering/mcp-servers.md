---
inclusion: always
---

# MCP Servers Disponibles — Guía de Uso

Configurar en `~/.kiro/settings/mcp.json`. Ver `docs/guia-calculadoras-aws.md` y `docs/guia-diagramas-lucid.md` para el detalle de cada uno.

## MCPs Activos

### 1. aws-pricing-calculator-mcp-server
- **Comando:** `npx -y sample-aws-pricing-calculator-mcp@latest`
- **Para qué:** Crear, modificar y exportar calculadoras en calculator.aws con link compartible
- **Cuándo usar:** Cuando se pida una calculadora con link de calculator.aws
- **Limitaciones conocidas:** RDS y ElastiCache pueden quedar en $0 (columnFormIPM no se procesa bien). Siempre verificar precio después de exportar.
- **Comportamientos verificados del MCP** (destilados del agente `MO-Proposals` de **Nicolás Delgado** — evitan fallos de exportación):
  - Un lote de `add_service` se **revierte completo si una sola entrada falla** la validación. Enviar primero, en lote pequeño, las entradas de shape desconocido antes del lote grande.
  - `awsFargate` con `vcpuPerTask = 0.5` **exige** `memoryStandardFargateOnDemand` (fileSize en GB) y **rechaza** `smallMemory`.
  - `awsConfig` **no acepta 0** en `numberOfConformancePackEvaluations`; el mínimo es 1 y su impacto es despreciable.
  - `networkAddressTranslationNatGatewayVpc` no acepta 0 en los campos regionales; modelar con `regionalNatGatewayCount = 1` y `regionalNatGatewayAzCount = 1` (mismo precio/hora que un NAT Gateway estándar).
  - `awsCloudTrail` requiere los **cuatro** multiplicadores (`OpsMult`, `dataOpsMult`, `networkActivityOpsMult`, `eventMult`) o queda parcial.
  - AWS Backup para RDS se agrega con la clave `rdsBackup`; `amazonRdsBackup` es un subservicio sin envoltorio y **bloquea la exportación**.
  - El MCP no devuelve costos calculados: el desglose se arma con precios unitarios del price list público (`https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/<OfferCode>/current/<region>/index.csv`) y el enlace de la calculadora es la fuente autoritativa.

### 2. Lucid Software
- **Comando:** `npx -y mcp-remote https://mcp.lucid.app/mcp`
- **Para qué:** Crear diagramas editables en Lucidchart con shapes AWS 2024 nativos
- **Cuándo usar:** Cuando se pidan diagramas de arquitectura editables para el cliente
- **Limitaciones conocidas:** No se puede VER el resultado renderizado — se generan coordenadas a ciegas. Después de 2 intentos fallidos, dar guía textual para ajustar manualmente.
- **Carpeta de trabajo:** Trabajar solo en la carpeta de Lucid que el equipo designe para arquitecturas. No editar documentos ajenos.
- **Auth:** Si Lucid MCP no carga, verificar tokens en `~/.mcp-auth/mcp-remote-*/tokens.json` (ver troubleshooting en la guía de diagramas).

### 3. aws-pricing-mcp-server
- **Comando:** `uvx --from awslabs-aws-pricing-mcp-server awslabs.aws-pricing-mcp-server`
- **Para qué:** Consultar precios REALES de servicios AWS en tiempo real desde la Pricing API
- **Cuándo usar:** ANTES de armar calculadoras, para verificar que los costos estimados sean correctos. También para comparar precios entre regiones o entre servicios.
- **Cómo usar:** Invocar `get_pricing`, `get_pricing_service_codes`, `get_pricing_attribute_values` para obtener precios actualizados
- **Requiere:** Credenciales AWS configuradas (`aws configure`) con permisos de lectura en Pricing API (us-east-1)

## Flujo de trabajo CORRECTO para calculadoras:

1. Se pide la calculadora
2. **PRIMERO:** Usar `aws-pricing-mcp-server` para consultar precios reales de cada servicio
3. **SEGUNDO:** Usar `aws-pricing-calculator-mcp-server` para armar la calculadora con esos precios validados
4. **TERCERO:** Exportar y verificar con `import_estimate` en formato markdown
5. **CUARTO:** Solo entregar si el total tiene sentido

## Estrategia de diagramas con Lucid MCP:

1. Usar Lucid MCP para la ESTRUCTURA (componentes, flechas, labels)
2. Ajustar la ESTÉTICA manualmente en Lucid (layout, posiciones, labels que se superponen)
3. Máximo 2 intentos con Lucid MCP. Si no queda bien → dar guía textual completa del flujo
4. SIEMPRE incluir todos los componentes. NUNCA simplificar omitiendo servicios.

## Alternativa futura para diagramas: aws-diagram-as-code (awslabs/diagram-as-code)
- **Repo:** https://github.com/awslabs/diagram-as-code
- **Para qué:** Generar diagramas AWS como PNG/SVG con layout automático correcto e íconos oficiales
- **Ventaja vs Lucid:** Layout automático que funciona; no necesita ajustes manuales
- **Desventaja vs Lucid:** Imagen estática (no editable por el cliente en un editor web)
- **Requiere:** Go + `go install github.com/awslabs/diagram-as-code/cmd/awsdac-mcp-server@latest`

## Estándares de Arquitectura Senior (OBLIGATORIO en cada diagrama)

Antes de generar cualquier diagrama, aplicar los "Estándares de Arquitectura Senior" (ver `docs/guia-diagramas-lucid.md` y CONTEXTO-KIRO.md). Resumen inquebrantable:

- **A. Columnas funcionales fijas** izq→der: Usuarios → Edge/DNS → Public Subnet → App Layer → Data Layer. Ningún servicio se sale de su columna. Seguridad/observabilidad/CI-CD en banda inferior.
- **B. Flujos numerados** ①②③ con labels descriptivos en TODAS las flechas.
- **C. Síncrono = línea sólida / Asíncrono (SQS, SNS, EventBridge, DLQ) = línea punteada.**
- **D. Checklist de servicios obligatorios:** WAF+Shield+ACM en endpoints públicos, Cognito/IdC para auth, **VPC Endpoints** (el olvido #1), CloudWatch+X-Ray+CloudTrail, DLQ en async, NAT GW por AZ en Prod, KMS+Secrets Manager, Multi-AZ visible, ECR para contenedores.
- **E. Jerarquía completa:** AWS Cloud → Region → VPC → AZ → Subnet → servicio. No aplanar.
- **F. Presentación:** título+metadata, leyenda, origen de tráfico a la izquierda, Multi-AZ con réplicas reales.
- **I. Panel de explicación del flujo (OBLIGATORIO):** lista numerada ①②③ que explica el flujo paso a paso, ubicada LEJOS de la arquitectura (nunca encima), como texto separado para leer y entender.
- **Validación pre-entrega:** recorrer el checklist de 8 puntos antes de entregar.
