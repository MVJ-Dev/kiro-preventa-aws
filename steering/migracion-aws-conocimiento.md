---
inclusion: always
---

# Conocimiento de Migración a AWS — Mapeos, Decisiones y Trampas

Destilado del repo oficial `awslabs/startups` (skills `gcp-to-aws`, `heroku-to-aws`, `llm-to-bedrock`,
`agent-advisor`). Aplicar SIEMPRE en levantamientos y propuestas de migración.

**Principios rectores (de AWS Startups SA):**
- **Re-platform por defecto** (no lift&shift ciego, no reescritura): elegir el servicio AWS que calza con el tipo de workload.
- **Extract before ask:** si el Terraform / billing export / código ya responde una pregunta, NO volver a preguntarla — presentarla como asunción a confirmar. Preguntar solo lo que los artefactos no revelan.
- **Dev-sizing por defecto** (db.t4g.micro, single-AZ) salvo que el cliente indique producción. No inflar.
- **Sin costos de mano de obra humana** en la estimación de infra (las HH van en el Excel aparte, JP 10%).
- **Clarify cierra antes de diseñar/estimar.** No diseñar con dominios abiertos.

---

## Mapeo GCP → AWS (usar como punto de partida, verificar precio real antes de cotizar)

| GCP | AWS destino típico | Nota de decisión |
|---|---|---|
| Cloud Run | **Fargate** | Fast-path determinista. Lambda solo si stateless y <15 min |
| Cloud Functions | **Lambda** | Si event-driven + <15 min + runtime soportado; si always-on/long → Fargate |
| Compute Engine (VM) | **EC2** (o Fargate) | Always-on→EC2; batch→EC2 Auto Scaling; Windows→EC2 |
| GKE | **EKS** | Solo si K8s explícito; sin preferencia de K8s → Fargate |
| App Engine | **Elastic Beanstalk** (default) | O Fargate/Lambda/EKS según modelo operativo elegido |
| Cloud SQL PostgreSQL/MySQL | **RDS** o **Aurora** | La disponibilidad elige la familia, no el tamaño |
| Cloud SQL SQL Server | **RDS SQL Server** | Aurora NO soporta SQL Server |
| Spanner | **Aurora DSQL** (o DynamoDB si key-value) | Path de migración difiere mucho |
| Firestore | **DynamoDB** | Migración NoSQL |
| AlloyDB | **Aurora PostgreSQL** | Equivalente más cercano |
| Memorystore (Redis) | **ElastiCache Redis** | |
| **BigQuery** | **Deferido — especialista** | NO mapear a un servicio directo; derivar a account team / partner de datos |
| Cloud Storage (GCS) | **S3** | |
| Filestore | **EFS** | |
| VPC / Firewall / LB | **VPC / Security Groups / ALB-NLB** | |
| Cloud CDN / Cloud DNS | **CloudFront / Route 53** | |
| Cloud Armor | **AWS WAF** | |
| Cloud Interconnect | **Direct Connect** | |
| Pub/Sub | **SNS o SQS** | |
| Cloud Tasks | **SQS o EventBridge** | |
| Vertex AI (Gemini/LLM) / OpenAI | **Bedrock** | Ver trampas LLM→Bedrock abajo |
| Vertex AI (ML tradicional/pipelines) | **SageMaker / SageMaker Pipelines** | |
| Cloud Vision API | **Textract o Rekognition** | |
| Secret Manager | **Secrets Manager** | |
| Service Accounts | **IAM Roles** | |

## Mapeo Heroku → AWS

| Heroku | AWS destino | Nota |
|---|---|---|
| Dynos | **Elastic Beanstalk** (default, Docker AL2023) | Fargate para control directo o non-web escalado horizontal; EKS si hay expertise K8s |
| Heroku Postgres | **RDS / Aurora** | |
| Heroku Redis | **ElastiCache** | |
| Heroku Kafka | **MSK** | |

**Contexto Heroku:** está en sustaining engineering (KTLO), no vende a nuevos clientes → asumir salida completa
de la plataforma en ventana definida. **NO recomendar App Runner** (cerrado a nuevos clientes 30-abr-2026).

## Regla de decisión RDS vs Aurora (clave, no equivocarse)
- **La disponibilidad requerida elige la FAMILIA**, no el tamaño:
  - `single-az` → **RDS** single-AZ (dev-grade).
  - `multi-az` → **RDS Multi-AZ** (failover automático, ~2x costo del single-AZ).
  - `multi-az-ha` (misión crítica) → **Aurora** Multi-AZ.
  - `multi-region` → **Aurora Global Database**.
- El patrón de tráfico y el I/O afinan el sizing/storage DENTRO de la familia ya elegida — **nunca** suben un workload Inconvenient/Significant a Aurora.
- I/O: bajo/medio → gp3; alto → io2/Provisioned IOPS.
- Write-heavy o multi-región activo-activo → evaluar **Aurora DSQL** + flag de architecture review.
- Rápido crecimiento → headroom en instancia; **Aurora Serverless v2** para escalado elástico.
- Herramienta de migración de datos: `pg_dump`/`pgcopydb` vs DMS según tamaño (pgcopydb seguro a cualquier escala); la estrategia de cutover define el runbook y nunca se asume.

---

## Trampas técnicas verificadas (anticipar en la reunión, no en el diseño)

**Eliminadores duros de compute:**
- Cloud Run → Lambda: **>15 min de ejecución** lo bloquea → Fargate.
- Cloud Run → Fargate: **GPU, >16 vCPU o >120 GB RAM** → EC2.
- Cloud Functions → Lambda: runtime no soportado (ej. Python 2.7) → runtime custom en Fargate.
- App Runner: **cerrado a nuevos clientes (abr-2026)** — nunca destino para migraciones nuevas.

**Migración de datos:**
- **Heroku Postgres + DMS: NO hay CDC** (Heroku no otorga rol REPLICATION) → DMS solo carga única con ventana de cutover. Decirlo apenas aparezca Heroku Postgres.
- BigQuery: sin equivalente directo → especialista/partner de datos.

**LLM → Bedrock (retarget, "swap de modelo" nunca es trivial):**
- LangChain/LangGraph: usar interfaz estándar (`bind_tools()`, `ToolMessage`), no acceder al formato crudo de `tool_calls`. `with_structured_output` puede devolver objeto parcial en vez de error → validar siempre. Async de `ChatBedrock` envuelve boto3 en threads (no nativo) → riesgo de thread pool exhaustion en alta concurrencia (usar `ChatBedrockConverse`). No reanudar threads de LangGraph iniciados con otro proveedor.
- Converse API: **sin `n`, `logprobs`, `seed`, ni `response_format` json_schema** (usar tool use para output estructurado).
- **`tiktoken` no sirve** para modelos Bedrock (tokenizers distintos) → usar `usage.inputTokens/outputTokens` post-hoc.
- Mapeo de errores: OpenAI 429→`ThrottlingException`, 401→`AccessDeniedException`, 400→`ValidationException`; manejar `ModelNotReadyException`.
- Prompts optimizados para GPT-4o no rinden igual en Claude → probar los top prompts y ajustar.

---

## Clasificador de complejidad (para dimensionar, NO para emitir HH/semanas)

Evaluar de Large a Small; gana el primer tier que matchea. Registrar el input que "ató" el tier (`tier_bound_by`).

- **Large** — ANY de: ≥9 servicios · spend >$10k/mes · multi-región (2+ regiones) · hay compliance.
- **Medium** — no Large y ANY de: 4-8 servicios · spend $1k-$10k/mes · hay bases de datos · availability multi-az.
- **Small** — ≤3 servicios · <$1k/mes · sin BD/storage con replicación · single-az · sin compliance.

**Regla de aislamiento de IA:** la coexistencia de IA NUNCA sube el tier de infraestructura (se dimensiona aparte).

**Uso correcto:** el tier da estructura de etapas y "duration drivers" (qué hace que ESTE stack tarde más:
gap de discovery sin IaC, migración de BD, parallel-run, multi-región/compliance). **Son heurísticas NO
calibradas** — alimentan el dimensionamiento y la estructura de la propuesta, pero las HH se calculan con
la metodología del equipo (JP = 10%, Excel con fórmulas). Nunca convertir drivers en semanas/horas.

**Success criteria escalados por tier** (referencia para criterios de éxito de la propuesta):
performance dentro de 10-20% del origen · monitoreo intensivo 24/48h · observación post-migración 14/30/45 días ·
data integrity 100% · disponibilidad 99% (billing-only) a 99.9% (infra).

---

## Flujo de levantamiento que se debe seguir (fases)

`discover → clarify → design → estimate → generate`. En **clarify**, preguntar por dominio SOLO lo que los
artefactos no revelan, aplicando la metodología de preguntas de nivel especialista (diseñar primero, detectar
quiebres, una pregunta por quiebre, test de las 4 propiedades). Los dominios de clarify: región, compliance,
disponibilidad, ventana de mantenimiento, compute, database, networking, y AI si aplica.

## Agentes de IA — selección de runtime
Para "¿dónde corro mi agente?": AgentCore vs ECS vs EKS vs Lambda (y Lambda MicroVMs). Descomponer sistemas con
varios workloads en unidades, cada una con su veredicto. Runtime se decide con criterios (latencia, always-on,
escalado, control), no de memoria.

## Advertencia permanente
Estos mapeos y tiers son punto de partida verificado por AWS, NO verdad absoluta. Antes de cotizar: verificar
precio real (aws-pricing-mcp-server) e identificar las trampas propietarias del caso concreto.
