# Guía: Migración a AWS y Migration Readiness Scorecard

Cómo abordar un proyecto de migración con Kiro como arquitecto senior de migraciones, y cómo saber con criterio objetivo cuándo el levantamiento tiene "toda la info" para diseñar y cotizar.

---

## 1. Migration Readiness Scorecard

**El problema que resuelve:** saber con criterio objetivo (no por intuición) cuándo el levantamiento está listo para diseñar y para cotizar, y qué riesgos revisar. Anclado a AWS Prescriptive Guidance.

**AWS define DOS niveles de completitud:**

| Nivel | Habilita | Exige (mínimo) |
|---|---|---|
| **Nivel 1 — Inventory & Prioritization** | Diseñar arquitectura + asignar 7 R + wave plan | Inventario apps+infra, dependencias, criticidad, entornos, mapeo app↔infra, licenciamiento, DR |
| **Nivel 2 — Detailed Business Case** | Cotizar con confianza (TCO, calculadora, HH) | Todo Nivel 1 + costos actuales + utilización (CPU/RAM pico y promedio) + esfuerzo por R + landing zone + data transfer |

**Reglas de uso:**
1. En CADA proyecto de migración, generar/actualizar el scorecard del cliente.
2. **No diseñar** arquitectura destino sin Nivel 1 en 🟢/🟡 razonable. **No cotizar** con confianza sin Nivel 2.
3. Cada aplicación DEBE tener una **estrategia 7 R asignada**. Si una app no tiene R, el assessment NO está cerrado.
4. Revisar SIEMPRE las trampas por origen (ver abajo).
5. Entregar el **veredicto de readiness** con %, lista accionable de gaps, y riesgos por severidad. Si no está listo → decirlo, no adivinar.

---

## 2. Las 7 R (estrategias de migración)

| R | Qué es | Cuándo |
|---|---|---|
| **Rehost** | Lift-and-shift (a EC2 vía MGN) | Migración rápida, sin cambios de código |
| **Replatform** | Ajustes menores (ej: DB gestionada a RDS) | Mejora sin rearquitecturar |
| **Repurchase** | Reemplazar por SaaS | Cuando existe un SaaS equivalente |
| **Refactor** | Rearquitecturar (a serverless, contenedores) | Modernización — **NO durante la migración**, después |
| **Retire** | Apagar lo que no se usa | Servidores zombie, apps obsoletas |
| **Retain** | Dejar en origen | Legacy, regulación, dependencias no migrables |
| **Relocate** | Mover VMware sin conversión | VMware Cloud on AWS |

Para migraciones grandes AWS recomienda **rehost/replatform/relocate/retire**. Refactor se hace después, no durante.

---

## 3. Dominios a cubrir en el levantamiento de migración

1. Contexto de negocio y motivación (driver, timeline, quién decide/opera)
2. Inventario de apps y servidores (CPU, RAM, disco, IOPS, throughput, utilización pico/promedio)
3. Bases de datos (motores, versiones exactas, HA, replicación, backups, RPO/RTO, licenciamiento)
4. Storage (tipos, volúmenes, acceso hot/warm/cold, lifecycle, crecimiento)
5. Networking (topología, DNS, conectividad híbrida, balanceadores, latencia, IPs fijas)
6. Seguridad e identidades (IAM/AD, SSO, compliance, licenciamiento, cifrado, certificados)
7. Operación (monitoreo, CI/CD, IaC, ambientes, quién opera)
8. Dependencias e integraciones (entre apps, con terceros, coexistencia, qué NO puede migrar)
9. Estrategia de migración (7 R, ventanas, downtime tolerable, DR día 1, big-bang vs fases, rollback)
10. Costos actuales e info para la calculadora (compute, DB, storage, data transfer, compromisos vigentes)
11. Landing zone y gobierno (Organizations, multi-account, Control Tower, SCPs, tagging)

---

## 4. Trampas por origen (revisar SIEMPRE)

**Supabase → AWS:** RLS con `auth.uid()`/`auth.jwt()` muere con Cognito → reescribir authz en la app (va en HH). Es un "debundle" services-first: Networking → Auth → Storage → Functions → Realtime → Database (al final).

**GCP → AWS:** Cloud Run >15min → Fargate (no Lambda). Cloud Run con GPU/>16vCPU/>120GB RAM → EC2. BigQuery sin equivalente directo → especialista de datos. Firestore → DynamoDB (rediseño NoSQL).

**Heroku → AWS:** Heroku Postgres + DMS **NO tiene CDC** (Heroku no da rol REPLICATION) → DMS solo carga única con ventana de cutover. App Runner cerrado a nuevos clientes → no es destino.

**Azure/On-prem → AWS:** licenciamiento SQL Server/Oracle (BYOL vs incluido). Aurora NO soporta SQL Server → RDS SQL Server. Stored procedures/triggers propietarios complican migración heterogénea (usar SCT + DMS o AWS Transform).

**Migración heterogénea de BD** (motor destino distinto al origen): AWS SCT (schema) + AWS DMS (datos), o AWS Transform para el flujo completo. Advertir sobre tipos de datos no portables y licenciamiento.

---

## 5. Herramientas AWS de migración (2026)

| Herramienta | Para qué | Estado |
|---|---|---|
| **AWS Transform** | Migración/modernización agéntica (infra, apps, código, .NET, VMware, DB) | Actual — reemplaza Migration Hub |
| **Application Discovery Service** | Discovery on-prem, dependencias, utilización | Actual |
| **Migration Evaluator** | Business case directional (TCO) | Actual |
| **DMS** | Migración de bases de datos | Actual |
| **SCT** | Conversión de schema entre motores | Actual |
| **MGN** | Lift-and-shift a EC2 | Actual |
| AWS Migration Hub | — | Cerrado a nuevos clientes desde 7-nov-2025 |

---

## 6. Clasificador de complejidad (para dimensionar, NO para emitir HH)

Evaluar de Large a Small; gana el primer tier que matchea:
- **Large** — ANY de: ≥9 servicios · spend >$10k/mes · multi-región · hay compliance.
- **Medium** — no Large y ANY de: 4-8 servicios · $1k-$10k/mes · hay BD · multi-az.
- **Small** — ≤3 servicios · <$1k/mes · sin BD/storage replicado · single-az · sin compliance.

**La coexistencia de IA NUNCA sube el tier de infraestructura** (se dimensiona aparte). El tier da estructura de etapas y "duration drivers" — las HH se calculan con la metodología del equipo (JP 10%, Excel con fórmulas), nunca convirtiendo drivers en semanas.

---

## 7. Plantilla del Scorecard

Copiar `scripts-levantamiento/PLANTILLA-Migration-Readiness-Scorecard.md` a la carpeta del cliente y llenarla.
