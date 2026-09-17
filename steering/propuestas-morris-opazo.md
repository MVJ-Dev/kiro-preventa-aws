---
inclusion: always
---

# Formato de Propuesta Morris & Opazo — Plantilla, Redacción y Cierre

> **Créditos:** este material es un destilado del agente interno **`MO-Proposals`**, cuyo autor original
> es **Nicolás Delgado** (equipo Morris & Opazo). Nicolás construyó y afinó las ~198 reglas, la plantilla
> de 15 secciones, las reglas de redacción de criterios/alcances y los comportamientos verificados del MCP
> de la calculadora a lo largo de múltiples propuestas reales. Aquí se generaliza su trabajo como steering
> compartido del equipo, reutilizando la FORMA (estructura, rótulos, nivel de detalle, tono), nunca los datos
> de un cliente concreto. Todo el mérito de la metodología es de Nicolás.

Es el **formato institucional de la empresa**, por lo que aplica a toda propuesta comercial del equipo.
El campo `Prepared by` es el de quien prepara la propuesta, no un nombre fijo.

Trabaja este formato después de: levantamiento cerrado → arquitectura → calculadora verificada. La propuesta
es el artefacto que amarra todo y va a revisión técnica antes de presentarla al cliente.

---

## Estructura canónica de la salida completa (3 bloques, en este orden, nada más)

**Bloque 1 — Documento de propuesta (15 secciones).**
**Bloque 2 — Anexos** (A esfuerzo/HH, B dimensionamiento a nivel de máquinas, C calculadora).
**Bloque 3 — Fuera del formato** (1 fuentes, 2 peligros, 3 detalles de servicios con límites, 4 programas AWS).

## Las 15 secciones (orden y rótulos EXACTOS, no renombrar ni agregar/quitar)

Encabezado: `TÍTULO` · `Prepared by:` · `Prepared for:` · `Date:` · `Last Update:` +
aviso de copyright `Copyright © <año> MORRIS Y OPAZO Y CIA` + Índice con página.

1. **Contexto de la Propuesta** — un párrafo: cliente e industria, problema concreto, su consecuencia (riesgo/costo/indisponibilidad), solución en una frase, y la región AWS.
2. **Objetivo** — una frase orientada a resultado (qué se logra, sobre qué, para qué). No es lista de actividades ni de tecnologías.
3. **Antecedentes** — máximo 4, técnicos y breves (1-2 líneas), con datos duros. El 1º es el dolor del cliente. Prohibido repetir el contexto de la sección 1 y prohibido abrir describiendo servicios AWS.
4. **Criterios de Éxito** — máximo 2 (`Primer Criterio de Éxito:` / `Segundo Criterio de Éxito:`), cada uno con 3-5 ítems de checklist. Ver reglas de redacción abajo.
5. **Alcances** — rótulo `Alcances: máximo 5`, lista numerada. Son el CÓMO se logran los criterios.
6. **No Contempla** — rótulo `No contempla: máximo 5`, exclusiones genéricas y abarcantes (familias completas de temas), no listas puntuales.
7. **Principales Actividades Planificadas** — rótulo `Principales actividades planificadas: máximo 10`, lista numerada, agrupada por fase si el proyecto es fasado, transversales al final. Aquí se producen las evidencias que verifican los criterios (sección 4).
8. **Referencias de Arquitectura** — SOLO tres elementos: tabla `Servicio | Función | En Arquitectura | En Calculadora`, `URL Diagrama Lucidchart:` y `URL Imagen Arquitectura:`. Nada más.
9. **Planificación General** — `Total Semanas:` (desglose por fase si aplica), `Modalidad de los Servicios Profesionales:`, `Servicios Profesionales Cotizados:`, `Cantidad de Horas Hombres:`.
10. **Valores Comerciales** — SubTotal / Descuento AWS / Descuento M&O / Total = `Lo ve comercial`; `MRR:` = `Lo ve comercial` + consumo AWS estimado por fase.
11. **Referencias Económicas** — `URL Calculadora AWS:` y `URL Imagen Calculadora:`.
12. **Consideraciones Generales** — rótulo `Consideraciones Generales: máximo 10`, una línea cada una. Aquí van los **supuestos adoptados** (región, modelo de compra, utilización, disponibilidad Single/Multi-AZ, licenciamiento, estado de la cuenta AWS, compromisos del cliente, desviaciones/omisiones respecto del referente que fijó el cliente). No repetir alcances ni exclusiones.
13. **Equipo de Trabajo Morris & Opazo** — checklist completo de roles con `- [x]` solo en los que el alcance justifica: Project Manager, MLOps Engineer, DevOps Engineer, Cloud Architect, Data Engineer, Cloud Developer, Cloud Training Specialist, Cloud Migration Specialist, Data Scientist, Other: Software Analyst.
14. **Equipo de Trabajo Cliente** — checklist: Technical Leader, Business User, System Administrator, Other.
15. **Referencia Comercial Adicional** — URL Logo Cliente (`Lo ve comercial`) + formulario de referencia.

Reglas globales del documento: sin líneas horizontales (`---`) ni separadores gráficos ni emojis; campos
comerciales siempre `Lo ve comercial`; la implementación y el soporte van en **propuestas separadas** (la de
implementación excluye administración continua, 24x7 y SLA, y no los dimensiona).

---

## Cómo redactar CRITERIOS DE ÉXITO (lo más corregido del agente — emular)

- La sección es SOLO dos etiquetas y sus checklists. **Prohibida una línea de título o resumen** tras `Primer Criterio de Éxito:` — debajo del rótulo van directamente los ítems.
- Cada ítem es un **hecho verificable en tiempo presente**, estado alcanzado el día del cierre, respondible sí/no («opera», «coincide», «está respaldada», «no es alcanzable desde Internet»).
- Cada ítem **nombra su propio sujeto** y se entiende leído en aislamiento. Prohibido heredar el sujeto del ítem anterior.
- **Tercera persona impersonal.** Prohibida la primera persona («migramos», «configuramos», «dejamos»).
- Prohibidos verbos de actividad («migrar», «configurar», «implementar») y términos vagos («adecuado», «óptimo», «robusto», «debería», «se espera», «idealmente», «mejorar»).
- Prohibidas líneas de cierre tipo `Se valida con…`, `Evidencia:`, `Responsable:`. La evidencia se produce en las actividades (7); el validador está en la sección 14.
- Un hecho por viñeta; si tiene dos, se separa. Cantidades solo si están confirmadas; si no, anclar a un acuerdo verificable («las aplicaciones registradas en el acta de kickoff»).
- Nombrar el servicio AWS oficial, sin explicarlo (eso va en los alcances).

Ejemplo aprobado:
```
**Primer Criterio de Éxito:**
- [ ] La base de datos opera en Amazon RDS PostgreSQL 18 dentro de la cuenta AWS nueva y responde consultas de lectura y escritura.
- [ ] El conteo de tablas y de filas de la base de datos migrada coincide con el del origen.
- [ ] La base de datos tiene respaldo automático en AWS Backup y una restauración de prueba ejecutada con éxito.
```

## Cómo redactar ALCANCES (el "cómo")

- Rótulo `Alcances: máximo 5`, lista numerada. **Una a dos líneas** cada uno (si necesita tres, está mal delimitado).
- Tercera persona impersonal: «Se crea», «Se levantan», «Se migra», «Se cifran».
- Técnico y concreto: servicios AWS exactos + cantidades + **al menos un dato técnico duro** (clase de instancia, nº de AZs, nº de túneles, modo de replicación, protocolo). Brevedad no autoriza vaguedad.
- **Prohibida línea separada de `Límite:`** — el límite imprescindible va como frase corta dentro del punto («El CIDR y el equipo terminador los provee el cliente»).
- Prohibido glosar cada servicio por separado (una cláusula cubre un grupo). Prohibidas fórmulas huecas: «configuración de servicios», «soporte y acompañamiento», «buenas prácticas», categorías genéricas.
- Separar alcance de migración del de crecimiento/evolución cuando aplique.

## Trazabilidad y coherencia (verificar ANTES de entregar)

- **R-PROP-255:** cada criterio cubierto por ≥1 alcance, y cada alcance aporta a ≥1 criterio.
- **R-PROP-265 (coherencia numérica obligatoria):** la MISMA cantidad debe repetirse idéntica en criterios → alcances → actividades → arquitectura → calculadora. Verificarlo explícitamente.
- Cadena de coherencia completa: necesidad → objetivo → criterios → alcances → actividades → arquitectura → dimensionamiento → calculadora → planificación → equipo. Toda diferencia se corrige o se explica.
- Test de 4 preguntas por cada criterio y alcance antes de entregar: ¿qué se logra/hace?, ¿sobre qué objeto y cantidad?, ¿cómo se verifica o hasta dónde llega?, ¿lo entendería alguien no técnico? Si alguna falla, reescribir.

---

## Esfuerzo (HH y semanas) — Jefe de Proyecto = 10%

- Base fija: **30 HH por semana.** Semanas estimadas = redondeo hacia arriba de (Total HH ÷ 30); mostrar también el valor exacto.
- No inventar HH; si faltan antecedentes, marcarlas «(por confirmar)» y advertir que las semanas no pueden calcularse.
- Cada actividad del Excel corresponde a una actividad planificada (sección 7).
- El Excel de HH debe ser editable con fórmulas; el Jefe de Proyecto (JP) se calcula como **10% del total** de HH técnicas vía fórmula (recálculo automático al editar).
- Anexo A: tabla `N° | Actividad | Fase | Rol | HH` con total. Si es fasado, HH y semanas por fase, advirtiendo que **las semanas no se redondean por fase**.

## Anexos
- **Anexo B — Dimensionamiento a nivel de máquinas** (obligatorio si el cliente pide costo en términos de máquinas/servidores/instancias): `Componente | Ambiente | Clase o capacidad | vCPU | RAM | Almacenamiento | Disponibilidad | Utilización`. Si no usa EC2, declarar que el cómputo es administrado y **no hay SO que licenciar ni parchar**.
- **Anexo C — Calculadora**: enlace, región, modelo de compra, nº de líneas, costo por etapa si es fasado, desglose por componente, y observaciones (USD 0 justificados, valores aproximados, capas gratuitas no aplicadas).

## Bloque 3 — Fuera del formato (siempre, en este orden)
1. **Fuentes utilizadas** — enlace + qué respalda; documentación oficial de AWS primero; lo no verificado «(por confirmar)».
2. **Peligros de la propuesta** — cada riesgo con probabilidad (A/M/B), impacto (A/M/B), señal temprana, mitigación y responsable; ordenados por criticidad; distinguir los que asumimos de los del cliente/terceros.
3. **Detalles de los servicios utilizados** — por servicio: qué hace aquí, configuración (clase, versión, modo), límites y cuotas relevantes (soft/hard), impacto y mitigación.
4. **Programas o incentivos AWS** — MAP, OLA, MAP for Windows, créditos POC, AWS Activate, EDP según el dominio; estado (elegible / probablemente / requiere validación con account team o partner); fondo indicativo derivado de la calculadora. **Sin montos, porcentajes ni umbrales inventados.** Aquí se declaran también los alcances habilitantes (cuenta, red, seguridad).

---

## Estándar de presentación (para que salga lista sin retoques)

Títulos de sección numerados en negrita; etiquetas de campo en negrita seguidas de su valor
(`**Total Semanas:** 7`); en Antecedentes/Criterios/Alcances el rótulo en negrita y el contenido normal;
datos duros y nombres de servicios AWS en negrita la primera vez; viñetas de una idea; tablas solo donde
aportan; «(por confirmar)» siempre visible; sin líneas horizontales, sin emojis y sin abuso de negrita
(si todo está en negrita, nada destaca).

## Presentación oficial en PowerPoint (plantilla institucional)
- Existe una plantilla institucional M&O (`Presentación.pptx`) de **solo lectura**. Solo se AÑADE información; nunca se altera diseño, tipografía, colores, layouts, nº de slides ni orden.
- Trabajar siempre sobre una COPIA (`shutil.copy` → `Presentacion_<Cliente>.pptx`), con `python-pptx`. Localizar cada slide por su rótulo, no por índice. Rellenar los cuadros/runs existentes para heredar estilo; duplicar el párrafo modelo para listas.
- No tocar las slides institucionales (Acerca de M&O, ADN, Líderes, Equipo, partner AWS, etc.). Solo generar cuando el usuario confirme la presentación final.
