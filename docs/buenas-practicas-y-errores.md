# Buenas Prácticas y Errores Comunes — Trabajando con Kiro en Preventa AWS

Lecciones destiladas de casos reales (anonimizadas). El objetivo es que todo el equipo evite repetir los mismos errores. Cópialo como referencia y, si quieres que Kiro lo aplique automáticamente, ponlo en tu contexto local.

---

## Principio general: NO ser complaciente

- Si algo **no va a funcionar** → decirlo, no implementarlo "a ver si funciona".
- Si **no se sabe un precio** → buscarlo, no inventarlo.
- Si una herramienta/MCP tiene **limitaciones** → decirlo ANTES de intentar y fallar.
- NUNCA entregar algo roto como si estuviera bien.
- Antes de implementar algo pedido: ¿va a funcionar para lo que realmente se necesita? ¿hay costos/limitaciones ocultas que aparecerán después? ¿estoy siendo honesto o complaciente? ¿puedo probar que funciona antes de entregarlo?

---

## Error #1 — Implementar algo que se sabe que no va a funcionar

**Qué pasó:** se pidió usar una herramienta como backend para un caso de uso para el que era inviable (stateless, sin prompts custom, output no estructurado). En vez de decir "esto no funciona para lo que necesitas", se implementó igual y se perdió tiempo.

**Reglas derivadas:**
1. NO implementar algo con limitaciones fundamentales que lo hacen inviable. Decirlo directamente.
2. NO ofrecer opciones que no son viables. Solo presentar opciones que REALMENTE funcionan.
3. Ser directo con costos y limitaciones desde el diseño inicial, no cuando el usuario los descubre.
4. Validar antes de proponer.

---

## Error #2 — Calculadora entregada con costos en $0

**Qué pasó:** al reconstruir una calculadora desde cero con el MCP, los servicios complejos quedaron en $0 y se entregó un link roto sin verificar el total.

**Causa raíz técnica:** el MCP del pricing calculator tiene limitaciones con campos `columnFormIPM`:
- **RDS, ElastiCache, SageMaker** → quedan en **$0** al exportar vía MCP.
- **Fargate** con `taskDuration` en formato incorrecto → usar `{"value":"30","unit":"day"}`, NO `"720 hour"`.
- `import_estimate` en markdown muestra $0 cuando los servicios no calcularon precio.

**Servicios que el MCP SÍ maneja bien:** S3, Fargate (taskDuration en "day"), NLB, WAF, CloudWatch, Route 53, VPN, NAT Gateway, Data Transfer, Secrets Manager, ECR.

**Regla definitiva:**
- **NUNCA reconstruir una calculadora completa con el MCP si tiene RDS, ElastiCache o SageMaker** — son la mayoría del costo y siempre quedan en $0.
- Lo correcto: investigar precios reales → calcular incrementos → dar instrucciones EXACTAS de edición manual en calculator.aws → no crear links rotos.
- **Protocolo de verificación obligatorio antes de entregar:** exportar → `import_estimate` (markdown) → verificar Total Monthly Cost → si es $0 o muy bajo, NO entregar, diagnosticar y corregir.
- Al modificar una calculadora existente: **agregar solo los servicios nuevos**, no reconstruir desde cero.

---

## Error #3 — Decir "eso no se puede" sin investigar

**Qué pasó:** se afirmó repetidamente que no se podían generar diagramas AWS editables en Lucidchart. Un tercero dijo que SÍ se podía — y tenía razón. Lucid tiene MCP server oficial y la AWS 2024 Library está soportada en Standard Import con todos los íconos nativos.

**Regla derivada (OBLIGATORIA):**
- **NUNCA decir "eso no se puede" sin investigar primero** en documentación oficial, GitHub, comunidades, blogs.
- Si un ingeniero o tercero dice que algo es posible → probablemente tiene razón.
- Las herramientas MCP evolucionan rápido: lo que no se podía hace 3 meses puede existir hoy.
- El conocimiento de memoria puede estar desactualizado. Verificar contra fuente oficial antes de afirmar límites, precios, features o herramientas.

---

## Error #4 — Diagramas feos e ilegibles en Lucid

**Qué pasó:** primeros diagramas con servicios sin contexto, labels que se sobreponían, spacing insuficiente, sin VPC/subnets, flechas cruzadas, y múltiples documentos de test ensuciando el Lucid compartido.

**Reglas derivadas:**
1. Spacing mínimo **250px** entre centros de íconos con labels largos (180px con cortos).
2. Labels **CORTOS** en el shape (2-3 palabras); detalle en annotations separadas.
3. Canvas grande — mínimo 2500x1500 para arquitecturas complejas.
4. Servicios **con contexto** — cada ícono con propósito, cantidad, ubicación.
5. VPC/Subnets **visibles** en vista de producción.
6. **UN solo documento** — no crear múltiples archivos de test.
7. **No editar documentos ajenos** — el Lucid suele ser compartido.
8. Estudiar referencias ANTES de crear.

---

## Error #5 — Decir "MCP no disponible" en vez de diagnosticar

**Qué pasó:** el Lucid MCP mostraba "loading" tras actualizarse `mcp-remote` (los tokens OAuth quedaron en la carpeta de versión vieja). En vez de diagnosticar, se dijo "no tengo las herramientas" y se cambió de tarea.

**Reglas derivadas:**
1. Si Lucid MCP dice "loading" y ya se autorizó: verificar si `tokens.json` existe en la carpeta de la versión actual de mcp-remote en `~/.mcp-auth/`. Si no, copiar de la versión anterior.
2. Si las tools no aparecen: NO asumir "no disponible" y pasar a otra cosa. DIAGNOSTICAR (proceso corriendo, tokens, versión).
3. **NUNCA cambiar de tarea cuando se pide algo específico.** Si hay bloqueo, resolverlo o decir claramente "no puedo, necesito que hagas X".
4. Si no se puede resolver: decirlo en 1 mensaje, no en 5, con la instrucción exacta.

---

## Lección #6 — Protocolo de Validación Arquitectural (OBLIGATORIO)

Antes de entregar CUALQUIER arquitectura, diagrama o solución técnica, ejecutar internamente este checklist de 10 puntos:

1. **Completitud de componentes** — ¿Están TODOS los servicios? No simplificar por estética.
2. **Viabilidad de cada servicio** — ¿La funcionalidad que asumo REALMENTE existe? Investigar antes de afirmar (ej: verificar que una feature de una API externa exista).
3. **Límites de servicio** — payload, timeout, concurrencia, cuotas (Step Functions 256KB, Lambda 15min, SQS 256KB).
4. **Idempotencia y duplicados** — race conditions, distributed lock, el hash de idempotencia incluye executionId.
5. **Manejo de errores** — retry, fallback, timeout, notificación de falla.
6. **Multi-tenancy** — aislamiento entre clientes, partition keys correctas.
7. **Seguridad** — expiración/renovación de tokens, cifrado en reposo, least privilege IAM.
8. **Costos** — realistas, con el volumen real del caso.
9. **Compatibilidad con el cliente** — ¿compatible con lo que quieren y ya tienen? ¿mismas tecnologías (Terraform, GitHub Actions)?
10. **Well-Architected** — 6 pilares, especialmente operable, observable, seguro, resiliente.

**En diagramas:** nunca simplificar omitiendo componentes; flujos completos y entendibles; labels descriptivos en cada flecha; textos que no se superpongan.
**En calculadoras:** sin free tier salvo confirmación; precios verificados; región confirmada; todos los servicios del diagrama; volúmenes realistas (ej: no poner 100 tokens si los prompts son de 4000).

---

## Lección #7 — Limitaciones del MCP de diagramas: proceso de 2 intentos

El MCP de Lucid **no permite ver el resultado renderizado** — se generan coordenadas a ciegas.

1. Aceptar la limitación: los ajustes finos de layout se hacen manualmente.
2. Rol de Kiro: generar la ESTRUCTURA correcta (todos los componentes, flechas, labels). El humano ajusta la ESTÉTICA.
3. Dar siempre una lista de "ajustes manuales sugeridos".
4. **Máximo 2 intentos a ciegas.** Si no queda bien → guía textual completa del flujo.

---

## Lección #8 — Investigar Arquitecturas de Referencia ANTES de diseñar

Cuando se pida una arquitectura (y se solicite), buscar el patrón oficial de AWS primero:
- AWS Solutions Library `aws.amazon.com/solutions/`
- AWS Architecture Center `aws.amazon.com/architecture/`
- AWS Prescriptive Guidance `docs.aws.amazon.com/prescriptive-guidance/`
- AWS Blogs (ML, Compute, Architecture)

Usar esas arquitecturas para validar el diseño propio. Si difiere del patrón oficial, justificar por qué o ajustar. Entregar los links como referencia.

---

## Regla transversal de datos de clientes

- **NUNCA subir datos de clientes** a este repo (nombres, IDs, inventarios, links de documentos privados).
- Las lecciones se documentan **generalizadas**, sin identificar al cliente.
- Los detalles específicos de cada caso viven solo en la carpeta local del cliente.
