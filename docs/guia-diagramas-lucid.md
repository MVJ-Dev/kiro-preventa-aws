# Guía: Diagramas de Arquitectura AWS con Lucid MCP

Desde agosto 2026 los diagramas de arquitectura se generan con el **Lucid MCP Server**, que crea diagramas **editables en Lucidchart** con shapes nativos **AWS 2024** (íconos oficiales). Reemplaza al enfoque anterior de Python Diagrams (graphviz), que generaba PNGs estáticos y feos.

**Ventajas:** editables por el cliente, íconos AWS reales, compartibles vía link, exportables a PNG para la propuesta.

---

## 1. Configuración del MCP

En `~/.kiro/settings/mcp.json`:
```json
{
  "mcpServers": {
    "Lucid Software": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://mcp.lucid.app/mcp"]
    }
  }
}
```

**Autenticación:** OAuth vía navegador (primera vez). Luego mantiene sesión.

### Troubleshooting de auth
`mcp-remote` guarda los tokens OAuth en carpetas versionadas en `~/.mcp-auth/`. Cuando npm actualiza la versión del paquete, la carpeta cambia de nombre (ej: `mcp-remote-0.2.1` → `mcp-remote-v1`) y los tokens NO se migran automáticamente → el MCP queda en "loading" eternamente.

**Solución:** copiar `tokens.json` de la carpeta vieja a la nueva:
```bash
cp ~/.mcp-auth/mcp-remote-0.2.1/tokens.json ~/.mcp-auth/mcp-remote-v1/tokens.json
```
Si no basta, matar procesos zombie de mcp-remote y reiniciar la sesión de Kiro.

---

## 2. Cómo se crean los diagramas

Se usa el formato **Lucid Standard Import JSON** con la AWS 2024 Library:

```json
// Servicio AWS (type: namedShape)
{
    "id": "ec2-1",
    "type": "namedShape",
    "className": "ArchAmazonEC2AWS2024",
    "boundingBox": {"x": 200, "y": 300, "w": 64, "h": 64},
    "text": "Web Server"
}

// Container (type: namedContainer) — VPC, Region, Subnet, etc.
{
    "id": "vpc-1",
    "type": "namedContainer",
    "className": "VirtualPrivateCloudVPCAWS2024",
    "boundingBox": {"x": 100, "y": 100, "w": 800, "h": 600},
    "text": "VPC - Producción (10.0.0.0/16)"
}
```

**Referencia completa de classNames:** https://developer.lucid.co/docs/aws-2024-library

---

## 3. ClassNames AWS 2024 — Referencia Rápida

**Containers (type: namedContainer):**
| className | Elemento |
|-----------|----------|
| `AWSCloudAWS2024` | AWS Cloud |
| `AWSAccountAWS2024` | AWS Account |
| `RegionAWS2024` | Region |
| `VirtualPrivateCloudVPCAWS2024` | VPC |
| `AvailabilityZoneAWS2024` | Availability Zone |
| `PublicSubnetAWS2024` | Public Subnet |
| `PrivateSubnetAWS2024` | Private Subnet |
| `SecurityGroupAWS2024` | Security Group |
| `AutoScalingGroupAWS2024` | Auto Scaling Group |

**Compute (type: namedShape):** `ArchAmazonEC2AWS2024` (EC2), `ArchAWSLambdaAWS2024` (Lambda), `ArchAWSFargateAWS2024` (Fargate), `ArchAWSBatchAWS2024` (Batch)

**Database:** `ArchAmazonRDSAWS2024` (RDS), `ArchAmazonAuroraAWS2024` (Aurora), `ArchAmazonDynamoDBAWS2024` (DynamoDB), `ArchAmazonElastiCacheAWS2024` (ElastiCache), `ArchAmazonRedshiftAWS2024` (Redshift)

**Networking:** `ArchAmazonRoute53AWS2024`, `ArchAmazonCloudFrontAWS2024`, `ArchAmazonAPIGatewayAWS2024`, `ResElasticLoadBalancingApplicationLoadBalancerAWS2024` (ALB), `ResElasticLoadBalancingNetworkLoadBalancerAWS2024` (NLB), `ResAmazonVPCNATGatewayAWS2024`, `ResAmazonVPCInternetGatewayAWS2024`

**Storage:** `ArchAmazonSimpleStorageServiceAWS2024` (S3), `ArchAmazonEFSAWS2024`, `ArchAWSBackupAWS2024`

**Security:** `ArchAWSWAFAWS2024`, `ArchAWSIdentityandAccessManagementAWS2024` (IAM), `ArchAWSCertificateManagerAWS2024` (ACM), `ArchAWSKeyManagementServiceAWS2024` (KMS), `ArchAWSSecretsManagerAWS2024`

**Messaging:** `ArchAmazonSimpleQueueServiceAWS2024` (SQS), `ArchAmazonSimpleNotificationServiceAWS2024` (SNS), `ArchAmazonEventBridgeAWS2024`

**Monitoring:** `ArchAmazonCloudWatchAWS2024`, `ArchAWSCloudTrailAWS2024`, `ArchAWSCloudFormationAWS2024`

**AI/ML:** `ArchAmazonBedrockAWS2024`, `ArchAmazonSageMakerAWS2024`

**Containers:** `ArchAmazonElasticContainerServiceAWS2024` (ECS), `ArchAmazonElasticKubernetesServiceAWS2024` (EKS), `ArchAmazonElasticContainerRegistryAWS2024` (ECR)

---

## 4. Estándares de Arquitectura Senior (OBLIGATORIO)

Todo diagrama debe cumplir estos estándares (nivel arquitecto AWS senior):

**A. Columnas funcionales fijas (swim lanes)** izq→der:
```
[Usuarios] → [Edge/DNS] → [Public Subnet] → [App Layer] → [Data Layer]
 x:0-200      x:300-650     x:750-1200       x:1300-1850    x:1950-2500
```
Fila inferior (y:1300+): seguridad + observabilidad + CI/CD (servicios que "tocan todo").

**B. Flujos numerados** ①②③ con label descriptivo en TODAS las flechas.

**C. Síncrono = línea sólida (grosor 3-4) / Asíncrono = línea punteada (grosor 2-3).**

**D. Checklist de servicios obligatorios** (agregar lo que falte): WAF+Shield+ACM en endpoints públicos · Cognito/IdC para auth · **VPC Endpoints** (el olvido #1) · CloudWatch+X-Ray+CloudTrail · DLQ en async · NAT GW por AZ en Prod · KMS+Secrets Manager · Multi-AZ visible · ECR para contenedores.

**E. Jerarquía completa (no aplanar):** AWS Cloud → Region → VPC → AZ → Subnet → servicio.

**F. Presentación:** título + metadata + fecha/versión · leyenda · origen del tráfico a la izquierda · Multi-AZ con réplicas reales.

**I. Panel de explicación del flujo (OBLIGATORIO):** lista numerada ①②③ que explica el flujo paso a paso, ubicada **LEJOS** de la arquitectura (nunca encima).

---

## 5. Reglas de Layout (CRÍTICAS — se generan coordenadas a ciegas)

| Elemento | Regla |
|----------|-------|
| Tamaño de íconos | 64x64 (consistencia) |
| Espacio entre centros | mín **250px** con labels largos, **180px** con labels cortos |
| Labels en el shape | CORTOS (2-3 palabras); detalle en annotation separada |
| Padding dentro de containers | mín 60px |
| Espacio entre filas | mín 200px |
| Canvas total | mín 2500x1500 para arquitecturas complejas |

**MAL:** "RDS PostgreSQL Multi-AZ + RDS Proxy" (se sobrepone)
**BIEN:** "RDS Multi-AZ" + annotation separada con el detalle

---

## 6. Limitaciones del MCP y proceso de 2 intentos

- **No se puede ver el resultado renderizado** — se generan coordenadas a ciegas.
- **Rol de Kiro:** generar la ESTRUCTURA correcta (todos los componentes, flechas, labels). Los ajustes finos de estética se hacen manualmente en Lucid.
- **Máximo 2 intentos a ciegas.** Si tras 2 intentos no queda bien → entregar la guía textual completa del flujo (columna por columna, flecha por flecha numerada) + lista de "ajustes manuales sugeridos".
- **UN solo documento** — no crear múltiples archivos de test.
- **No editar documentos ajenos** — el Lucid suele ser compartido. Trabajar solo en la carpeta designada por el equipo.

### Páginas múltiples (patrón recomendado)
- Página 1 "Assessment" — estado actual / arquitectura existente
- Página 2 "Diseño" — arquitectura propuesta detallada (VPC, subnets, AZs)
- Página 3 "Arquitectura" — vista conceptual limpia para presentación

---

## 7. Validación Pre-Entrega (ejecutar SIEMPRE)

1. ¿Flujos de izquierda a derecha en columnas fijas?
2. ¿Flechas numeradas y etiquetadas?
3. ¿Síncrono sólido y async punteado?
4. ¿Están TODOS los servicios del checklist? Especialmente VPC Endpoints
5. ¿Jerarquía de containers completa?
6. ¿Título, leyenda y origen de tráfico?
7. ¿Multi-AZ con réplicas reales en Prod?
8. ¿Panel de explicación del flujo, numerado y LEJOS de la arquitectura?

Si algo falla → corregir ANTES de entregar.

---

## 8. Alternativa futura: diagram-as-code (awslabs)

Para diagramas técnicos con **layout automático correcto** (PNG/SVG), existe [awslabs/diagram-as-code](https://github.com/awslabs/diagram-as-code):
- **Ventaja vs Lucid:** layout automático que funciona, no requiere ajustes manuales
- **Desventaja:** imagen estática (no editable por el cliente en un editor web)
- **Instalación:** Go + `go install github.com/awslabs/diagram-as-code/cmd/awsdac-mcp-server@latest`

Usar Lucid cuando el cliente necesita editar; diagram-as-code cuando se quiere un PNG técnico rápido y bien alineado.
