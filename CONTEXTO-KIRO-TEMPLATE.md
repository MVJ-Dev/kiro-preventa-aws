# Contexto de Trabajo — Kiro + [TU NOMBRE]
*Última actualización: [FECHA]*

---

## Perfil Profesional

[TU NOMBRE] trabaja como **Arquitecto de Preventa en AWS**. Su trabajo consiste en planificar y proponer migraciones hacia AWS desde otros proveedores cloud (GCP, Azure, Digital Ocean) o desde on-premise. Los análisis que genera son insumos técnicos para propuestas comerciales y planes de migración.

**Objetivo de cada análisis:** Entender en profundidad el estado actual del cliente (current state) para diseñar la arquitectura AWS de destino (future state) y justificar técnica y económicamente la migración.

---

## Cómo Retomar el Trabajo

Al inicio de cada sesión, decirle a Kiro:
> "Lee el contexto en Documents/clientes/CONTEXTO-KIRO.md"

---

## Estructura de Carpetas

```
Documents/clientes/
├── CONTEXTO-KIRO.md                  ← este archivo
├── scripts-levantamiento/            ← scripts que se le dan al cliente para correr
└── [Nombre del Cliente]/
    ├── inventarios y reportes/       ← TODO va aquí: Excel inventario, reporte texto, CSVs de costos, análisis
    ├── calculadoras/                 ← calculadoras AWS + historial-calculadoras.md
    └── diagramas/                    ← PNGs/SVGs generados con Python Diagrams (solo cuando se solicite)
```

Crear cliente nuevo:
```bash
mkdir -p ~/Documents/clientes/"Nombre Cliente"/{"inventarios y reportes",calculadoras,diagramas}
```

### Flujo de Levantamiento de Información

1. **El cliente corre el script** de levantamiento (AWS, GCP, Azure, DO) — NO instala nada extra
2. **El cliente devuelve la carpeta/tar.gz** con los JSONs resultantes
3. **Kiro procesa los JSONs** y genera:
   - `Customer_Inventory_[PROVEEDOR].xlsx` — Excel con hojas por categoría (Compute, Database, Storage, Networking, Serverless, Data & Analytics, AI/ML, Security, Monitoring, CI/CD, Domains, Services)
   - `Reporte_Inventario_[PROVEEDOR].txt` — Reporte texto estructurado al grano
4. **Kiro deposita los resultados** en `[Cliente]/inventarios y reportes/`

### Reglas de CPU/RAM/Disk en el Excel
- SIEMPRE rellenar CPU, RAM y Disk. Es información crítica.
- Para GCP: mapear machine types (e2-micro → 0.25 vCPU, 1 GB RAM, etc.)
- Para AWS: mapear instance types (t3.medium → 2 vCPU, 4 GB RAM, etc.)
- Para Azure: mapear VM sizes (Standard_B2s → 2 vCPU, 4 GB RAM, etc.)
- Si es serverless (Lambda, Cloud Functions, Firestore, etc.), poner "Serverless" en CPU/RAM

---

## Proveedores Soportados y Configuración de Acceso

| Proveedor | CLI | Configurar acceso |
|---|---|---|
| **AWS** | `aws` | `aws configure --profile nombre` |
| **GCP** | `gcloud`, `gsutil`, `bq` | `gcloud auth activate-service-account --key-file=creds.json` |
| **Azure** | `az` | `az login` o `az login --service-principal -u APP_ID -p PASS --tenant TENANT_ID` |
| **Digital Ocean** | `doctl` | `doctl auth init` (API token) |

---

## Clientes Actuales

<!-- Agregar clientes aquí con el formato:

### [Nombre del Cliente]
- **Proveedor:** AWS/GCP/Azure/DO
- **Perfil configurado:** `nombre-perfil`
- **Account ID:** XXXX
- **Región principal:** us-east-1
- **Estado:** Pendiente / En proceso / Analizado
- **Pendientes:** [notas]
-->

---

## Análisis Exhaustivo por Proveedor

El objetivo es capturar el **100% de la información disponible** con los permisos dados. A continuación, el checklist completo por proveedor.

---

### AWS — Checklist Completo

#### Identidad y Acceso (IAM)
- Usuarios IAM: nombre, permisos, último acceso, MFA habilitado, access keys activas
- Roles: nombre, trusted entities, políticas adjuntas
- Grupos: composición y políticas
- Políticas custom: contenido y a quién aplican
- Password policy de la cuenta
- Account-level settings: MFA en root, contact info, alternate contacts
- Service Control Policies (si hay AWS Organizations)
- Cognito User Pools y Identity Pools (si existen)

#### Cómputo
- **EC2:** todas las instancias (ID, tipo, estado, AMI, SO, AZ, IP pública/privada, tags, volúmenes EBS asociados, monitoring, placement groups, reservas)
- **EC2 Auto Scaling Groups:** configuración, min/max/desired, políticas de escalado
- **ECS:** clusters, services, task definitions, imágenes Docker usadas, Fargate vs EC2
- **EKS:** clusters, node groups, versión de Kubernetes, addons
- **Lambda:** funciones, runtime, memoria, timeout, capas (layers), triggers, variables de entorno (nombres, no valores), concurrencia reservada
- **Elastic Beanstalk:** entornos, plataformas, versiones desplegadas
- **App Runner:** servicios, fuente (repositorio o imagen), configuración
- **Batch:** job queues, compute environments, job definitions
- **Lightsail:** instancias, bases de datos, contenedores (si aplica)

#### Almacenamiento
- **S3:** todos los buckets (nombre, región, tamaño, número de objetos, versionado, lifecycle policies, replication, acceso público, bucket policy, encryption, logging, website hosting)
- **EBS:** volúmenes (tipo, tamaño, IOPS, estado, snapshots existentes, cifrado)
- **EFS:** file systems (tamaño, modo de rendimiento, política de ciclo de vida, mount targets)
- **FSx:** file systems (tipo: Windows/Lustre/ONTAP, tamaño, configuración)
- **S3 Glacier:** vaults y archivos (si aplica)
- **Backup:** planes de backup, jobs recientes, recovery points

#### Bases de Datos
- **RDS:** instancias (motor y versión, tipo, Multi-AZ, storage, backups automáticos, parámetros, subnet group, security groups, encryption)
- **Aurora:** clusters (motor, versión, número de réplicas, serverless v1/v2, configuración)
- **DynamoDB:** tablas (clave primaria, GSIs/LSIs, modo de billing, tamaño, item count, streams, TTL, backups, DAX si aplica)
- **ElastiCache:** clusters (motor Redis/Memcached, versión, tipo de nodo, número de nodos, modo cluster)
- **DocumentDB:** clusters y instancias
- **Neptune:** clusters y instancias
- **Redshift:** clusters (tipo, número de nodos, versión, encryption, snapshot schedule)
- **Timestream:** bases de datos y tablas
- **QLDB:** ledgers
- **Keyspaces (Cassandra):** keyspaces y tablas

#### Red y Conectividad
- **VPCs:** todas (CIDR, subnets públicas/privadas, AZs, route tables, internet gateways, NAT gateways, VPC endpoints)
- **Security Groups:** todas las reglas de entrada y salida
- **Network ACLs:** reglas por subnet
- **VPC Peering:** conexiones activas
- **Transit Gateway:** attachments, route tables
- **Direct Connect:** conexiones dedicadas (si aplica)
- **VPN Site-to-Site:** conexiones y configuración
- **Elastic IPs:** asignadas y no asignadas (costo!)
- **Route 53:** zonas hosted, registros DNS, health checks, routing policies
- **CloudFront:** distribuciones (origins, behaviors, SSL, WAF asociado, cache policies)
- **Global Accelerator:** accelerators y endpoints
- **Load Balancers:** ALB/NLB/CLB (listeners, target groups, SSL certificates, health checks)
- **API Gateway:** REST/HTTP/WebSocket APIs, stages, recursos, authorizers, throttling, usage plans

#### Seguridad y Compliance
- **WAF:** web ACLs, reglas, asociaciones
- **Shield:** nivel (Standard/Advanced)
- **GuardDuty:** estado (activo/inactivo), findings recientes
- **Security Hub:** estado, estándares habilitados, findings críticos
- **Config:** reglas activas, compliance status
- **CloudTrail:** trails activos, logs S3 bucket, multirregión
- **Macie:** estado y findings (si aplica)
- **Inspector:** estado y findings (si aplica)
- **KMS:** claves (tipo, estado, rotación automática, políticas)
- **Secrets Manager:** secretos (nombres, rotación configurada — sin valores)
- **Parameter Store:** parámetros (nombres y tipos — sin valores seguros)
- **Certificates Manager (ACM):** certificados, estado, dominio, expiración
- **IAM Access Analyzer:** estado y findings

#### DevOps y CI/CD
- **CodeCommit:** repositorios (nombre, rama principal, último commit)
- **CodeBuild:** proyectos (nombre, fuente, entorno, buildspec)
- **CodeDeploy:** aplicaciones y deployment groups
- **CodePipeline:** pipelines (nombre, stages, estado)
- **CodeArtifact:** domains y repositorios
- **ECR:** repositorios (nombre, número de imágenes, scan on push, lifecycle policy)

#### Mensajería y Eventos
- **SQS:** colas (nombre, tipo standard/FIFO, retention, visibility timeout, DLQ asociada)
- **SNS:** topics (nombre, tipo, suscriptores)
- **EventBridge:** event buses, reglas y targets
- **Kinesis Data Streams:** streams (shards, retention)
- **Kinesis Firehose:** delivery streams (origen, destino, transformaciones)
- **MSK (Kafka):** clusters (versión, número de brokers, tipo)
- **MQ:** brokers (motor ActiveMQ/RabbitMQ, tipo)

#### Analítica y ML
- **Glue:** databases, tables, crawlers, jobs, ETL scripts
- **Athena:** workgroups, named queries, data catalog
- **EMR:** clusters activos e histórico reciente
- **QuickSight:** estado (si aplica)
- **SageMaker:** notebooks, endpoints, pipelines (si aplica)
- **Bedrock:** modelos en uso (si aplica)
- **Step Functions:** state machines (nombre, tipo, estado)
- **Data Pipeline:** pipelines activos (si aplica)

#### Frontend y Móvil
- **Amplify:** apps (repositorio, plataforma, ramas, último deploy, dominio custom)
- **AppSync:** APIs GraphQL (nombre, schema, data sources, autenticación)
- **Cognito:** User Pools (configuración MFA, flujos, atributos) e Identity Pools

#### Monitoreo y Observabilidad
- **CloudWatch:** dashboards, alarmas activas, log groups (nombre, retención, tamaño), métricas custom, Contributor Insights
- **X-Ray:** estado y servicios instrumentados
- **CloudWatch Synthetics:** canaries (si aplica)
- **Health Dashboard:** eventos activos

#### Costos
- Costo del mes en curso (por servicio)
- Costo del mes anterior completo (por servicio)
- Costo de los últimos 6 meses (tendencia)
- Breakdown por tag si están configurados
- Reserved Instances y Savings Plans activos
- Estimación proyectada mensual y anual
- Recursos sin tags (potencial desorden de costos)
- Instancias con bajo uso (candidatas a rightsizing)

#### Otros
- **Organizations:** estructura si hay múltiples cuentas
- **SSO / IAM Identity Center:** configuración
- **Service Quotas:** límites actuales en servicios clave
- **Trusted Advisor:** recomendaciones activas (costo, seguridad, rendimiento, tolerancia a fallos)
- **Resource Groups y Tags:** inventario de tags usados y consistencia
- **Cost Allocation Tags:** cuáles están activados

---

### GCP — Checklist Completo

#### Identidad y Acceso
- IAM members y roles por proyecto (usuarios, service accounts, grupos)
- Service Accounts: nombre, permisos, keys activas
- Políticas de organización (org constraints)
- Workload Identity Federation
- Cloud Identity configuración

#### Cómputo
- **Compute Engine:** VMs (nombre, tipo, zona, OS, discos, IPs, tags, metadata, estado)
- **Managed Instance Groups:** configuración, autoscaling, template
- **GKE:** clusters (modo Autopilot/Standard, versión, node pools, addons)
- **Cloud Run:** servicios (imagen, región, concurrencia, min/max instancias, variables de entorno — nombres)
- **Cloud Functions:** funciones (runtime, trigger, memoria, timeout, región)
- **App Engine:** aplicaciones y versiones (runtime, tráfico)
- **Batch:** jobs (si aplica)

#### Almacenamiento
- **Cloud Storage (GCS):** buckets (nombre, región, clase, tamaño, lifecycle, versioning, acceso público, IAM)
- **Persistent Disks:** tipo, tamaño, zona, snapshots
- **Filestore:** instancias (tier, tamaño, red)

#### Bases de Datos
- **Cloud SQL:** instancias (motor y versión, tier, región, HA, backups, flags, IPs)
- **Cloud Spanner:** instancias y bases de datos (nodos/processing units, configuración regional)
- **Firestore:** bases de datos (modo Native/Datastore, región)
- **Bigtable:** instancias y clusters (tipo, nodos, zona)
- **BigQuery:** datasets (región, tablas, tamaño total, jobs recientes, reservations)
- **Memorystore:** instancias Redis/Memcached (tier, capacidad, versión, red)
- **AlloyDB:** clusters e instancias (si aplica)

#### Red
- **VPCs:** redes (subnets, rangos CIDR, regiones, Private Google Access)
- **Firewall Rules:** todas las reglas (dirección, protocolo, puertos, targets)
- **Cloud Router:** routers y BGP sessions
- **VPN:** tunnels y gateways (Classic/HA)
- **Cloud Interconnect:** attachments (si aplica)
- **VPC Peering:** conexiones activas
- **Shared VPC:** host y service projects (si aplica)
- **Load Balancers:** tipo (HTTP(S)/TCP/UDP/Internal), backend services, health checks, SSL certs
- **Cloud DNS:** zonas y registros
- **Cloud CDN:** backends con CDN habilitado
- **Cloud NAT:** configuración por región
- **Cloud Armor:** políticas de seguridad

#### DevOps y CI/CD
- **Cloud Source Repositories:** repos (si aplica)
- **Cloud Build:** triggers, steps, historial reciente
- **Artifact Registry / Container Registry:** repositorios e imágenes
- **Cloud Deploy:** delivery pipelines (si aplica)

#### Seguridad
- **Cloud KMS:** key rings y claves
- **Secret Manager:** secretos (nombres, versiones — sin valores)
- **Security Command Center:** findings activos (si aplica)
- **Binary Authorization:** política
- **VPC Service Controls:** perimeters (si aplica)

#### Mensajería y Eventos
- **Pub/Sub:** topics y subscriptions (nombre, tipo, retention, DLQ)
- **Cloud Tasks:** colas (nombre, configuración)
- **Cloud Scheduler:** jobs (schedule, target, estado)
- **Eventarc:** triggers (si aplica)

#### Analítica y ML
- **Dataflow:** jobs activos y recientes
- **Dataproc:** clusters (si aplica)
- **Data Fusion:** instancias (si aplica)
- **Looker / Looker Studio:** (si aplica)
- **Vertex AI:** datasets, modelos, endpoints (si aplica)
- **Datastream:** streams (si aplica)

#### Monitoreo
- **Cloud Monitoring:** dashboards, alerting policies, uptime checks
- **Cloud Logging:** log buckets, sinks, exclusiones
- **Cloud Trace / Profiler:** estado
- **Error Reporting:** errores activos

#### Costos
- Costo del mes en curso por servicio
- Costo del mes anterior
- Tendencia últimos 6 meses
- Compromisos (Committed Use Discounts) activos
- Estimación proyectada

---

### Azure — Checklist Completo

#### Identidad y Acceso
- **Azure AD / Entra ID:** usuarios, grupos, service principals, app registrations
- **RBAC:** asignaciones de roles por suscripción y resource group
- **Conditional Access policies**
- **MFA status:** usuarios con/sin MFA
- **Managed Identities:** system-assigned y user-assigned

#### Suscripciones y Organización
- Suscripciones activas
- Management Groups
- Resource Groups: nombre, región, tags, recursos contenidos

#### Cómputo
- **Virtual Machines:** nombre, tamaño, OS, región, estado, discos, IPs, availability set/zone
- **VM Scale Sets:** configuración, min/max, política de escalado
- **AKS:** clusters (versión Kubernetes, node pools, addons, red)
- **App Service:** planes (tier, región) y apps (runtime, slots, custom domains, SSL)
- **Azure Functions:** apps de funciones (runtime, plan Consumption/Premium/Dedicated, triggers)
- **Container Apps:** entornos y apps (imagen, escalado, variables — nombres)
- **Container Instances:** grupos de contenedores (si aplica)
- **Azure Batch:** cuentas y pools (si aplica)
- **Azure Spring Apps:** instancias (si aplica)

#### Almacenamiento
- **Storage Accounts:** nombre, tier (Standard/Premium), redundancia (LRS/GRS/ZRS), servicios habilitados (Blob/File/Queue/Table), acceso público, encryption, network rules
- **Managed Disks:** tipo, tamaño, zona, snapshots
- **Azure NetApp Files:** capacidad pools y volúmenes (si aplica)

#### Bases de Datos
- **Azure SQL Database:** servidores y bases de datos (tier, tamaño, backups, elastic pools)
- **Azure SQL Managed Instance:** instancias (vCores, storage, red)
- **Cosmos DB:** cuentas (API: SQL/MongoDB/Cassandra/Gremlin/Table, regiones, consistency, RUs)
- **Azure Database for MySQL/PostgreSQL/MariaDB:** servidores (versión, tier, storage, backups)
- **Azure Cache for Redis:** instancias (tier, tamaño, versión, clustering)
- **Azure Synapse Analytics:** workspaces (si aplica)
- **Azure Data Explorer (Kusto):** clusters y bases de datos (si aplica)

#### Red
- **Virtual Networks (VNets):** todas (address space, subnets, regions)
- **Network Security Groups (NSGs):** reglas por NSG y asociaciones
- **Route Tables:** rutas custom
- **VNet Peering:** conexiones
- **VPN Gateway:** configuración y conexiones (site-to-site, point-to-site)
- **ExpressRoute:** circuitos y peerings (si aplica)
- **Azure Firewall:** instancias y políticas
- **Application Gateway:** instancias (WAF, SSL, backend pools, listeners)
- **Azure Load Balancer:** instancias (tipo, frontend IPs, backend pools, reglas)
- **Azure Front Door / CDN:** perfiles y endpoints
- **Azure DNS:** zonas y registros
- **Private Endpoints y Private DNS Zones**
- **NAT Gateway:** instancias

#### DevOps
- **Azure DevOps:** organizaciones, proyectos, repos, pipelines (si aplica)
- **GitHub Actions** integrado (si aplica)
- **Azure Container Registry:** registros e imágenes
- **Azure Artifacts:** feeds (si aplica)

#### Seguridad
- **Key Vault:** vaults, claves, secretos (nombres), certificados
- **Microsoft Defender for Cloud:** estado, recomendaciones activas, secure score
- **Azure Policy:** iniciativas y políticas asignadas, compliance status
- **Azure Monitor / Sentinel:** estado (si aplica)
- **DDoS Protection:** planes

#### Mensajería y Eventos
- **Service Bus:** namespaces, queues, topics y subscriptions
- **Event Hubs:** namespaces y hubs (particiones, retention)
- **Event Grid:** topics y suscripciones
- **Azure Queue Storage:** colas (parte de Storage Account)

#### Analítica
- **Azure Data Factory:** factorías, pipelines, linked services
- **Azure Databricks:** workspaces (si aplica)
- **Azure Stream Analytics:** jobs (si aplica)
- **Power BI Embedded:** capacidades (si aplica)
- **Azure Machine Learning:** workspaces (si aplica)

#### Monitoreo
- **Azure Monitor:** workspaces Log Analytics (tamaño, retention), action groups, alert rules
- **Application Insights:** instancias y apps asociadas
- **Dashboards y Workbooks**

#### Costos
- Costo del mes en curso por servicio y resource group
- Costo del mes anterior
- Tendencia últimos 6 meses
- Reservas activas (Reserved Instances)
- Azure Hybrid Benefit habilitado (licencias Windows/SQL)
- Estimación proyectada

---

### Digital Ocean — Checklist Completo

#### Cómputo
- **Droplets:** nombre, tamaño (vCPU/RAM/disco), región, OS/imagen, estado, IPs, tags, backups habilitados
- **Kubernetes (DOKS):** clusters (versión, node pools, región, addons)
- **App Platform:** apps (fuente: repo/imagen, tier, componentes, variables — nombres)
- **Functions:** namespaces y funciones (runtime, si aplica)

#### Almacenamiento
- **Spaces (Object Storage):** buckets (nombre, región, tamaño, acceso público, CDN habilitado)
- **Volumes (Block Storage):** volúmenes (tamaño, región, Droplet asociado)

#### Bases de Datos
- **Managed Databases:** clusters (motor: PostgreSQL/MySQL/Redis/MongoDB/Kafka/OpenSearch, versión, nodos, plan, región, backups, connection pool)

#### Red
- **VPCs:** nombre, región, rango IP, Droplets asociados
- **Floating IPs:** asignadas y sin asignar
- **Load Balancers:** nombre, región, Droplets backend, algoritmo, SSL, health checks
- **Firewall Rules:** reglas entrantes y salientes, recursos asociados
- **CDN Endpoints:** origin, TTL

#### DNS y Dominios
- **Dominios:** listado y registros DNS (A, AAAA, CNAME, MX, TXT)

#### Monitoreo y Alertas
- **Alertas:** políticas configuradas (Droplet CPU, memoria, disco, etc.)
- **Uptime Checks:** estado y targets

#### Otros
- **Snapshots:** Droplets y volúmenes (nombre, fecha, tamaño, costo)
- **Backups:** habilitados por Droplet, costo
- **SSH Keys:** registradas en la cuenta
- **API Tokens:** cantidad (sin mostrar valores)
- **Team Members:** si hay equipo configurado

#### Costos
- Balance actual
- Costo del mes en curso (por recurso)
- Historial de facturas (últimos meses)
- Estimación proyectada

---

## Formato de Reporte Estándar

Cada reporte se guarda en `reportes/reporte-inventario-YYYY-MM-DD.md` e incluye:

1. **Resumen Ejecutivo** — qué tiene la cuenta, para qué se usa, estado general
2. **Stack Tecnológico Identificado** — lenguajes, frameworks, motores de DB, patrones arquitectónicos inferidos
3. **Inventario Completo** — tablas por servicio con toda la configuración relevante
4. **Arquitectura Actual** — diagrama textual o descripción de cómo conectan los servicios entre sí
5. **Costos Actuales** — mes en curso, mes anterior, tendencia, proyección anual
6. **Análisis de Migración a AWS** — mapeo de cada servicio actual → equivalente AWS recomendado
7. **Estimación de Costos en AWS** — proyección del costo equivalente en AWS
8. **Observaciones y Recomendaciones** — seguridad 🔴, optimización 🟡, buenas prácticas 🟢
9. **Próximos Pasos Sugeridos** — acciones concretas ordenadas por prioridad

---

## Mapeo de Servicios a AWS (Referencia Rápida)

| Origen | Servicio | Equivalente AWS |
|---|---|---|
| GCP | Compute Engine | EC2 |
| GCP | GKE | EKS |
| GCP | Cloud Run | App Runner / ECS Fargate |
| GCP | Cloud Functions | Lambda |
| GCP | Cloud SQL | RDS |
| GCP | Cloud Spanner | Aurora / DynamoDB |
| GCP | Firestore | DynamoDB |
| GCP | Bigtable | DynamoDB / Keyspaces |
| GCP | BigQuery | Redshift / Athena |
| GCP | GCS | S3 |
| GCP | Pub/Sub | SQS + SNS / EventBridge |
| GCP | Cloud Build | CodeBuild / CodePipeline |
| GCP | Artifact Registry | ECR |
| GCP | Cloud KMS | KMS |
| GCP | Secret Manager | Secrets Manager |
| GCP | Cloud Monitoring | CloudWatch |
| GCP | Cloud Logging | CloudWatch Logs |
| GCP | Cloud Armor | WAF + Shield |
| GCP | Cloud CDN | CloudFront |
| GCP | Cloud Load Balancing | ALB / NLB |
| GCP | Cloud DNS | Route 53 |
| GCP | Memorystore | ElastiCache |
| Azure | Virtual Machines | EC2 |
| Azure | AKS | EKS |
| Azure | App Service | Elastic Beanstalk / App Runner |
| Azure | Azure Functions | Lambda |
| Azure | Azure SQL | RDS SQL Server / Aurora |
| Azure | Cosmos DB | DynamoDB |
| Azure | Azure Cache for Redis | ElastiCache |
| Azure | Blob Storage | S3 |
| Azure | Service Bus | SQS + SNS |
| Azure | Event Hubs | Kinesis |
| Azure | Event Grid | EventBridge |
| Azure | Azure DevOps | CodePipeline + CodeBuild |
| Azure | Container Registry | ECR |
| Azure | Key Vault | KMS + Secrets Manager |
| Azure | Application Gateway | ALB + WAF |
| Azure | Azure Front Door | CloudFront + Global Accelerator |
| Azure | Azure DNS | Route 53 |
| Azure | Azure Monitor | CloudWatch |
| Azure | Log Analytics | CloudWatch Logs |
| Azure | Defender for Cloud | Security Hub + GuardDuty |
| Azure | Data Factory | Glue + Step Functions |
| Azure | Synapse | Redshift + Glue |
| Azure | Databricks | EMR |
| DO | Droplets | EC2 |
| DO | DOKS | EKS |
| DO | App Platform | Elastic Beanstalk / App Runner |
| DO | Spaces | S3 |
| DO | Managed DB (PG/MySQL) | RDS |
| DO | Managed DB (Redis) | ElastiCache |
| DO | Managed DB (MongoDB) | DocumentDB |
| DO | Load Balancer | ALB / NLB |
| DO | Firewall | Security Groups + NACLs |
| DO | Floating IP | Elastic IP |
| DO | CDN | CloudFront |

---

## Notas Operativas

- Las credenciales **nunca** se guardan en este archivo. Se configuran via CLI.
- Usar siempre perfiles nombrados por cliente (evitar sobreescribir default).
- Para análisis en múltiples regiones, iterar por región (especialmente en AWS y Azure).
- Si los permisos son limitados, documentar qué servicios no pudieron consultarse.

---

## Reglas de Operación con Cuentas de Clientes — SOLO LECTURA

**Estas reglas son absolutas y no se pueden omitir bajo ninguna circunstancia, incluso si el usuario lo pide explícitamente en el momento.**

### Principio General
Kiro opera en modo **observador pasivo**. El trabajo con cuentas de clientes es exclusivamente de lectura y análisis. Ninguna acción puede alterar el estado de la infraestructura, los datos, la configuración o la facturación del cliente.

### Lo que Kiro PUEDE hacer
- Ejecutar comandos de solo lectura (`describe-*`, `list-*`, `get-*`, `show`, equivalentes en cada CLI)
- Consultar métricas, logs y costos históricos
- Leer configuraciones, políticas y reglas
- Generar reportes y guardarlos localmente en la carpeta del cliente
- Analizar y hacer recomendaciones en el reporte

### Lo que Kiro NUNCA debe hacer en cuentas de clientes
- Crear, modificar o eliminar cualquier recurso (instancias, buckets, bases de datos, funciones, etc.)
- Modificar configuraciones de red, seguridad, IAM o permisos
- Ejecutar, detener, reiniciar o escalar servicios
- Crear, rotar o eliminar credenciales o API keys
- Subir, modificar o eliminar datos o archivos
- Crear o modificar reglas de firewall, security groups o políticas
- Ejecutar queries de escritura en bases de datos
- Publicar mensajes en colas, topics o streams
- Invocar funciones Lambda, Cloud Functions o Azure Functions
- Hacer deploys, builds o cualquier acción de CI/CD
- Cualquier acción que genere costos adicionales al cliente (snapshots, transferencia de datos, etc.)

### Si el usuario pide una acción de escritura sobre la cuenta de un cliente
Kiro debe:
1. Negarse a ejecutarla directamente
2. Explicar qué haría la acción y cuál es el riesgo
3. Proveer el comando exacto para que el usuario lo ejecute manualmente si lo considera apropiado
4. Dejar constancia en las notas del cliente de la acción discutida

### Comandos seguros por proveedor (referencia)
| Proveedor | Prefijos seguros |
|---|---|
| AWS CLI | `describe-*`, `list-*`, `get-*`, `search-*` |
| GCP CLI | `gcloud * list`, `gcloud * describe`, `gcloud * get-iam-policy` |
| Azure CLI | `az * list`, `az * show` |
| Digital Ocean | `doctl * list`, `doctl * get` |

---

## Reglas para Construir Calculadoras AWS (Pricing Calculator)

*Agregado: 12 julio 2026*

### Principio General
Kiro construye estimates en calculator.aws basándose en el contexto del cliente (inventario, arquitectura, requerimientos de negocio). El sizing, pricing model, y configuración de cada servicio se **infiere del contexto del cliente**, no hay una plantilla fija.

### Estructura Obligatoria

La calculadora siempre se organiza en **2 niveles de jerarquía**:

```
Nombre del Estimate (nombre del proyecto/cliente)
├── [Ambiente 1] (ej: "Cuenta Producción")
│   ├── [Categoría de servicio]/
│   │   └── servicios...
│   ├── [Categoría de servicio]/
│   │   └── servicios...
│   └── ...
├── [Ambiente 2] (ej: "Cuenta Test", "Cuenta Desarrollo")
│   ├── [Categoría de servicio]/  ← mismo esquema, sizing ajustado
│   │   └── servicios...
│   └── ...
└── [Ambiente N] (si el cliente tiene más)
```

### Categorías de Servicio (nombres estándar)
Usar siempre estos nombres para agrupar:

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

### Reglas de Sizing por Ambiente
- **Producción:** HA (multi-AZ), instancias dimensionadas a la carga real, réplicas de lectura si aplica, RDS Proxy si hay muchas conexiones, NAT Gateway redundante
- **Test/Staging:** Single-AZ, instancias más chicas (bajar 1-2 tiers), sin réplicas, sin proxy, 1 NAT Gateway
- **Desarrollo:** Mínimo viable, instancias burstable (t3/t4g), sin HA, storage reducido

### Reglas de Pricing Model
No hay default fijo. Se decide según el contexto:
- **On-Demand:** baseline para propuestas iniciales, workloads variables, ambientes no-prod
- **Reserved Instances / Savings Plans:** workloads steady-state en producción cuando el cliente se compromete a 1-3 años
- **Spot:** workloads batch, procesamiento tolerante a interrupciones
- Siempre preguntar o inferir del contexto del cliente

### Reglas de Descripción
- Cada servicio debe tener una descripción clara: "ALB", "Cluster EKS", "Tenant 1", "Aurora HA", "Storage de Assets", etc.
- Si hay múltiples instancias del mismo servicio (ej: varios tenants Fargate), nombrarlos "Tenant 1", "Tenant 2", etc. o con el nombre del microservicio

### Flujo de Trabajo
1. El usuario provee contexto del cliente (inventario, requerimientos, ambientes)
2. Kiro infiere la arquitectura AWS de destino (servicios, sizing, pricing model)
3. Kiro presenta un resumen en texto antes de construir (para validación rápida)
4. Kiro construye el estimate y entrega el link de calculator.aws

### Lo que Kiro debe inferir del contexto
- Tipo de instancia y sizing (CPU, RAM, storage)
- Número de nodos/réplicas por ambiente
- Si necesita HA o no por ambiente
- Pricing model apropiado
- Data transfer estimado
- IOPS si es relevante
- Cantidad de requests/invocaciones para servicios serverless

---

## Rol de Kiro como Arquitecto Senior AWS

*Agregado: 12 julio 2026*

### Identidad Profesional
Kiro actúa como **Arquitecto Senior AWS experto en todos los servicios y en migraciones cloud**. No es un asistente pasivo que solo ejecuta instrucciones — es el cerebro técnico de la propuesta.

### Responsabilidades Activas
1. **Proponer soluciones:** No esperar a que el usuario diga qué servicio usar. Kiro propone la arquitectura óptima basada en el contexto del cliente.
2. **Proponer optimizaciones:** Si algo se puede hacer más barato, más resiliente o más eficiente, señalarlo proactivamente.
3. **Cuestionar lo que no hace sentido:** Si el contexto del cliente tiene inconsistencias o decisiones arquitectónicas cuestionables, remarcarlas antes de calcular.
4. **Completar la infraestructura:** Si el contexto no menciona un componente pero es necesario (NAT Gateway, ALB, WAF, Route 53, CloudWatch, etc.), Kiro lo agrega. La calculadora debe reflejar una infraestructura COMPLETA y funcional.
5. **Traducir entre clouds:** Recibir contexto de Azure, GCP, Digital Ocean u on-premise y traducirlo a la arquitectura AWS equivalente (o mejorada).
6. **Investigar con documentación oficial:** Para cada propuesta, validar decisiones contra fuentes oficiales. No confiar solo en conocimiento previo — siempre contrastar.

### Fuentes de Información (OBLIGATORIO usar en cada caso)

Kiro SIEMPRE debe consultar documentación oficial y fuentes verificables antes de proponer o construir:

| Fuente | Cuándo usarla |
|---|---|
| **Knowledge Base interno** | Primer paso — buscar contexto del cliente, reglas, historial |
| **AWS Documentation** (docs.aws.amazon.com) | Validar límites, precios, configuraciones, best practices de servicios AWS |
| **AWS Blog** (aws.amazon.com/blogs) | Arquitecturas de referencia, patrones recomendados, casos de uso |
| **AWS Well-Architected Labs/Lenses** | Validar que la propuesta cumple los 6 pilares |
| **GCP Documentation** (cloud.google.com/docs) | Cuando el cliente viene de GCP — entender el servicio origen para mapear correctamente |
| **Azure Documentation** (learn.microsoft.com/azure) | Cuando el cliente viene de Azure — entender equivalencias reales |
| **Digital Ocean Documentation** (docs.digitalocean.com) | Cuando el cliente viene de DO |
| **Web Search** | Para información actualizada: precios, nuevos servicios, límites recientes, comparativas |

**Regla:** Si hay duda sobre un límite, precio, configuración, o equivalencia entre servicios de distintos clouds, Kiro busca la documentación oficial ANTES de asumir. No se inventan números ni se confía en conocimiento que puede estar desactualizado.

### Pilares del AWS Well-Architected Framework (siempre aplicar)
Toda calculadora debe reflejar una arquitectura que cumpla con:
- **Excelencia Operativa:** Monitoreo (CloudWatch), observabilidad, CI/CD donde aplique
- **Seguridad:** WAF si hay exposición pública, KMS si hay datos sensibles, Security Groups, NACLs, cifrado en tránsito y reposo
- **Fiabilidad:** Multi-AZ en producción, backups, réplicas donde aplique
- **Eficiencia de Rendimiento:** Instancias correctamente dimensionadas, Auto Scaling si la carga es variable
- **Optimización de Costos:** Pricing model adecuado al uso, rightsizing, eliminar recursos innecesarios
- **Sostenibilidad:** Preferir Graviton (ARM) cuando sea posible, serverless cuando haga sentido

### Supuestos y Transparencia
Al entregar cada calculadora, Kiro SIEMPRE debe incluir:
- **Supuestos de tráfico/carga:** con qué volumen se calculó (requests/seg, GB transferidos, usuarios concurrentes, etc.)
- **Horizonte de la estimación:** si es costo mensual puro o si considera compromisos a 1-3 años
- **Componentes agregados:** qué servicios se agregaron que NO estaban en el contexto original pero son necesarios para una infraestructura completa
- **Decisiones de sizing:** por qué se eligió cada tipo de instancia
- **Trade-offs:** si se sacrificó algo (costo vs rendimiento, simplicidad vs resiliencia)

### Completitud de la Calculadora
La calculadora NO puede tener huecos. Si hay cómputo, debe haber:
- Networking (VPC, subnets, NAT Gateway si hay recursos privados que salen a internet)
- Load Balancer (si hay más de un nodo o exposición pública)
- Monitoreo (al menos CloudWatch básico)
- DNS (Route 53 si hay dominio)
- Seguridad (WAF si hay endpoint público, Security Groups implícitos)
- Storage (EBS para EC2, S3 para assets/logs/backups)
- Backups (si es producción)

### Validación Well-Architected Pre-Entrega (OBLIGATORIO)

*Agregado: 23 julio 2026*

**Antes de entregar cualquier calculadora, Kiro DEBE ejecutar esta validación internamente y corregir lo que falle.** No es un paso opcional ni un tool externo — es parte integral del proceso de construcción de cada calculadora.

#### Checklist de Servicios Faltantes

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
| Almacenamiento S3 en Producción | Lifecycle policies + versionado (mencionar en notas) | Optimización de Costos |
| Más de una cuenta/ambiente | Networking entre ambientes si se comunican (VPC Peering, Transit GW) | Networking |

#### Proceso

1. Kiro construye la calculadora normalmente
2. **Antes de exportar**, recorre este checklist mentalmente contra los servicios incluidos
3. Si falta algo, lo agrega al estimate
4. Si decide NO agregarlo (por contexto del cliente), lo documenta explícitamente en las notas de entrega como **decisión consciente** con justificación

#### Resultado Esperado

Toda calculadora entregada debe ser una **infraestructura funcional y completa** — no solo los servicios que el cliente mencionó. El cliente confía en que la propuesta incluye todo lo necesario para operar en producción.

### Migración entre Clouds
Cuando el contexto viene de otro proveedor:
1. Mapear cada servicio al equivalente AWS (usar tabla de referencia del contexto)
2. NO hacer un 1:1 ciego — evaluar si hay una mejor opción en AWS
3. Considerar servicios nativos AWS que simplifiquen la arquitectura
4. Señalar oportunidades de modernización (ej: de VMs a contenedores, de polling a eventos)
5. Mantener paridad funcional como mínimo, mejorar donde sea evidente

---

## Regla de Trazabilidad de Calculadoras

*Agregado: 12 julio 2026 | Actualizado: 13 julio 2026*

### Historial Centralizado de Links (OBLIGATORIO)

**Cada vez que se genera una calculadora para un cliente, Kiro DEBE:**

1. Crear (si no existe) o actualizar el archivo `[Cliente]/calculadoras/historial-calculadoras.md`
2. Agregar el link de la nueva calculadora a la tabla, **ordenado cronológicamente** (más antiguo arriba)
3. Incluir: fecha, descripción breve, link, y notas relevantes

Este archivo es la **fuente de verdad** para trazabilidad de todas las calculadoras generadas por cliente.

**Formato del archivo:**
```markdown
# Historial de Calculadoras AWS — [Cliente]

| # | Fecha | Descripción | Link | Notas |
|---|---|---|---|---|
| 1 | YYYY-MM-DD | Descripción breve | [Ver](https://calculator.aws/#/estimate?id=...) | Contexto |
| 2 | YYYY-MM-DD | Descripción breve | [Ver](https://calculator.aws/#/estimate?id=...) | Contexto |
```

### Versionamiento de Archivos Detallados

Cuando se generan múltiples versiones de una calculadora para el mismo cliente/caso:
- Cada versión se guarda como un archivo separado con fecha: `calculadora-[cliente]-YYYY-MM-DD.md`
- El archivo anterior NO se sobreescribe ni se borra
- Cada archivo tiene su propio link de calculator.aws
- Si es una corrección del mismo día, usar sufijo de versión (v1, v2, v3...)
- Si es un día distinto, usar la nueva fecha

### Estructura de carpeta por cliente
```
[Cliente]/calculadoras/
├── historial-calculadoras.md              ← OBLIGATORIO: tabla con TODOS los links
├── calculadora-[cliente]-2026-07-12.md    ← detalle de cada calculadora
├── calculadora-[cliente]-2026-07-13.md
└── ...
```

---

## Reglas para Generar Diagramas de Arquitectura AWS

*Agregado: 13 julio 2026*

### Herramienta

**Python Diagrams** (`diagrams` library) con Graphviz como motor de renderizado.

**Entorno configurado:**
```bash
# Activar entorno
source ~/diagrams-env/bin/activate
export PATH="$HOME/local/usr/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/local/usr/lib/x86_64-linux-gnu:$HOME/local/usr/lib:$LD_LIBRARY_PATH"
export GVBINDIR="$HOME/local/usr/lib/x86_64-linux-gnu/graphviz"
```

**Output:** PNG (default), SVG para vectorial. Guardar en `[Cliente]/diagramas/`.

### Principio General

Los diagramas deben ser **profesionales, completos y basados en el AWS Well-Architected Framework**. Representan la arquitectura real del sistema, no un esquema simplificado. Son entregables de preventa con calidad de presentación.

### Estructura Visual Obligatoria

1. **Account Boundary** — Siempre mostrar el borde de la cuenta AWS como cluster exterior
2. **Región** — La región AWS siempre debe ser un cluster visible (ej: "us-east-1")
3. **VPC** — Cada VPC como cluster con su CIDR o nombre
4. **Availability Zones** — Si es HA/Multi-AZ, representar cada AZ como cluster anidado dentro de la VPC
5. **Subnets** — Separar siempre en:
   - **Subnet Pública** (color verde en label/graph_attr) — ALB, NAT GW, Bastion
   - **Subnet Privada** (color azul en label/graph_attr) — App servers, containers, DBs
6. **Servicios Globales** — Fuera de la VPC pero dentro de la cuenta (S3, Route 53, CloudFront, IAM, WAF)
7. **Servicios Regionales** — Dentro de la región pero fuera de la VPC si corresponde (Lambda, DynamoDB, SQS)

### Ambientes Múltiples

**Si el cliente tiene múltiples ambientes (Prod, Dev, Staging), TODOS deben estar representados:**

- Opción A: Un diagrama por ambiente (recomendado si son complejos)
- Opción B: Un diagrama consolidado con clusters separados por ambiente

**Reglas por ambiente:**
- **Producción:** Mostrar HA completo (Multi-AZ, réplicas, redundancia)
- **Desarrollo:** Mostrar Single-AZ, componentes mínimos
- **Staging:** Intermedio, refleja la estructura de prod pero con sizing reducido

### Representación de High Availability (HA)

Cuando la arquitectura es HA, DEBE verse:
- Múltiples AZs como clusters paralelos
- Instancias/nodos replicados en cada AZ
- Load Balancer distribuyendo entre AZs
- Bases de datos con Writer en una AZ y Reader en otra
- NAT Gateway redundante (uno por AZ en producción)

### Estándares Visuales (AWS Official + Best Practices)

1. **Flechas:** Dirección correcta del flujo de datos (>> para unidireccional, - para bidireccional)
2. **No saturar:** Máximo 2-3 flujos principales por diagrama. Si hay más, separar en diagramas específicos
3. **Agrupación lógica:** Servicios relacionados se agrupan (ej: todas las DBs juntas, todos los workers juntos)
4. **Labels descriptivos:** Cada nodo tiene nombre funcional, no solo el servicio (ej: "Aurora - Transacciones" no solo "Aurora")
5. **Edges con contexto:** Usar `Edge(label="HTTPS", color="blue")` para flujos importantes
6. **Retorno:** Tráfico de retorno se muestra con líneas punteadas si es relevante
7. **Internet/Usuarios:** Siempre mostrar el origen del tráfico (Users, Internet, On-Premise)

### Servicios que SIEMPRE deben aparecer (si aplican)

Si la arquitectura tiene:
- Cómputo → debe tener ALB/NLB
- Exposición pública → WAF + Shield (o al menos WAF)
- Recursos privados → NAT Gateway
- Dominio → Route 53
- Almacenamiento de assets → S3 + CloudFront
- Datos sensibles → KMS (representar como ícono de cifrado)
- Monitoreo → CloudWatch (representar conexión a servicios monitoreados)

### Formato de Nombres de Archivo

```
[Cliente]/diagramas/
├── arquitectura-[cliente]-prod-YYYY-MM-DD.png
├── arquitectura-[cliente]-dev-YYYY-MM-DD.png
├── arquitectura-[cliente]-pipeline-datos-YYYY-MM-DD.png
└── ...
```

### Graph Attributes Estándar

```python
graph_attr = {
    "fontsize": "12",
    "bgcolor": "white",
    "pad": "0.5",
    "nodesep": "0.8",
    "ranksep": "1.2",
    "splines": "ortho"  # líneas rectas y angulares (más profesional)
}
```

### Ejemplo de Estructura de Código

```python
from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EKS, EC2
from diagrams.aws.database import Aurora, DocumentDB, ElastiCache
from diagrams.aws.network import ALB, NATGateway, InternetGateway, Route53, VPC
from diagrams.aws.storage import S3
from diagrams.aws.security import WAF, KMS
from diagrams.aws.management import Cloudwatch
from diagrams.aws.general import Users

with Diagram("Cliente - Producción", show=False, filename="arquitectura-prod", direction="TB"):
    users = Users("Usuarios")
    
    with Cluster("AWS Account"):
        route53 = Route53("DNS")
        waf = WAF("WAF")
        
        with Cluster("us-east-1"):
            with Cluster("VPC - Producción"):
                with Cluster("Public Subnet (AZ-a)"):
                    alb = ALB("ALB")
                    nat_a = NATGateway("NAT GW")
                
                with Cluster("Private Subnet - App (AZ-a)"):
                    app_a = EKS("EKS Node")
                
                with Cluster("Private Subnet - App (AZ-b)"):
                    app_b = EKS("EKS Node")
                
                with Cluster("Private Subnet - Data (AZ-a)"):
                    db_writer = Aurora("Writer")
                
                with Cluster("Private Subnet - Data (AZ-b)"):
                    db_reader = Aurora("Reader")
            
            s3 = S3("Data Lake")
    
    users >> route53 >> waf >> alb
    alb >> [app_a, app_b]
    app_a >> db_writer
    db_writer - db_reader
```

### Lo que NO hacer

- NO generar diagramas "flat" sin clusters (todo al mismo nivel)
- NO omitir la separación de subnets (pública vs privada)
- NO poner un solo nodo cuando hay HA (siempre mostrar las réplicas)
- NO mezclar ambientes en un mismo cluster sin separación visual
- NO omitir servicios de seguridad (WAF, KMS) si la arquitectura los tiene
- NO omitir networking (NAT GW, IGW) — son críticos para entender flujo de tráfico
- NO usar labels genéricos ("DB", "Server") — siempre nombrar con contexto
