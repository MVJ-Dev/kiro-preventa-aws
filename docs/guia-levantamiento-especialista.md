# Guía: Levantamiento de Nivel Especialista

Cómo usar Kiro para generar preguntas de reunión que realmente sirven. El objetivo es corregir el problema de **"pregunto mucho pero mal"**: muchas preguntas genéricas de checklist no aportan, mientras que los especialistas hacen pocas preguntas quirúrgicas que anticipan dónde se rompe el diseño.

**La cantidad NO es calidad. Menos preguntas, pero que cada una duela.**

---

## La regla de oro: DISEÑAR primero, PREGUNTAR después

NUNCA generar preguntas recorriendo la lista de dominios. El orden correcto es:

1. **Diseñar mentalmente la solución destino** con la info que ya se tiene (arquitectura AWS probable, servicios, flujos).
2. **Detectar los puntos de quiebre** — ¿dónde se rompe este diseño? ¿qué límite de servicio lo mata? ¿qué trampa del origen aplica?
3. **De cada punto de quiebre nace UNA pregunta** que resuelve esa incertidumbre específica.
4. Recién al final, completar con las preguntas de dominio que falten y que sí tengan consecuencia.

Las preguntas salen del **diseño y sus riesgos**, no del checklist.

---

## Test de las 4 propiedades

Antes de incluir una pregunta, verificar que tenga las 4. Si le falta una, se descarta:

1. **Anticipa un punto de quiebre** — nace de "¿dónde se rompe esto?", no de "¿qué tienen?".
2. **Tiene consecuencia de diseño/costo explícita** — anotar SIEMPRE "→ bloqueante para: [arquitectura/calculadora/estrategia]". Si la respuesta no cambia NADA → eliminarla.
3. **Conecta un dato del cliente con un límite/trampa técnica real** — payload 256KB de Step Functions, versión de PG para Aurora Global, RLS con `auth.uid()` en Cognito, licenciamiento SQL Server, logical replication, timeout 15min de Lambda, etc.
4. **Ofrece opciones con trade-offs cuantificados cuando aplica** — no "¿qué RTO quieren?" sino "RTO <15min = infra activa 24/7 ~$3-4k/mes; 1-4h = réplica + IaC ~$500-1k/mes; >4h = solo IaC ~$50/mes. ¿Cuál?".

---

## Ejemplos: genérica (MAL) vs especialista (BIEN)

| ❌ Genérica (recita dominio) | ✅ Especialista (anticipa quiebre + consecuencia) |
|---|---|
| ¿Usan Redis y para qué? | ¿Redis guarda solo caché, o también sesiones/colas? → si hay colas, ElastiCache no basta, hay que evaluar SQS y eso cambia la arquitectura |
| ¿Qué versión de Postgres usan? | ¿Están en RDS estándar o Aurora, y qué versión de PG? → Aurora Global Database (para su DR) solo soporta versiones específicas; si no, se descarta esa topología |
| ¿Tienen RLS? | ¿Sus políticas RLS usan `auth.uid()`/`auth.jwt()`? → esas funciones mueren con Cognito; hay que reescribir authz en la app (esfuerzo real, va en HH) |
| ¿Cómo manejan la autenticación? | ¿El backend lee el schema `auth` de Supabase directo (Prisma `schemas=["auth"]`)? → si sí, el acoplamiento es de esquema, no de SDK — migración de auth mucho más cara |
| ¿Qué RTO necesitan? | Si la región primaria cae, ¿en cuántos minutos deben operar? <15min=~$3-4k/mes; 1-4h=~$500-1k/mes; >4h=~$50/mes |
| ¿Procesan trabajos async? | ¿El payload entre pasos del workflow supera 256KB? → si sí, Step Functions falla y hay que pasar por S3; cambia el diseño |

---

## Estructura de entrega de las preguntas

1. **Agrupar por decisión que habilitan**, no solo por dominio (ej: "Bloqueantes para la arquitectura de DR", "Bloqueantes para la calculadora").
2. Cada pregunta lleva su **"→ bloqueante para: X"** visible.
3. Marcar el **mínimo indispensable** al final: "sin estos N datos no se puede diseñar/cotizar".
4. Ordenar por impacto: primero las que descartan/definen arquitecturas completas, después el detalle.

---

## Autovalidación antes de entregar

- [ ] ¿Diseñé la solución mentalmente ANTES de escribir las preguntas?
- [ ] ¿Cada pregunta pasa el test de las 4 propiedades?
- [ ] ¿Eliminé las que no cambian el diseño, costo ni plan?
- [ ] ¿Conecté datos del cliente con límites/trampas técnicas reales de este caso?
- [ ] ¿Marqué el mínimo indispensable y ordené por impacto?
- [ ] Si tengo 40 preguntas, ¿cuántas son realmente quirúrgicas? Preferir 12 excelentes a 40 de relleno.

---

## Prompt tipo para pedirle esto a Kiro

> "Aquí está el contexto del cliente [pega inventario/notas]. Diseña mentalmente la arquitectura AWS destino, detecta los puntos de quiebre, y dame las preguntas de nivel especialista para la reunión, agrupadas por decisión que habilitan y con el bloqueante de cada una marcado. Prefiere pocas preguntas quirúrgicas a un checklist largo."

---

## Fases del flujo de levantamiento

`discover → clarify → design → estimate → generate`

En **clarify**, preguntar por dominio SOLO lo que los artefactos no revelan (extract before ask: si el Terraform / billing / código ya lo responde, presentarlo como asunción a confirmar). Aplicar la metodología de preguntas de especialista. Dominios de clarify: región, compliance, disponibilidad, ventana de mantenimiento, compute, database, networking, y AI si aplica.
