# Flujo de Trabajo — Cómo se trabaja con Kiro en Preventa AWS

Este documento explica el flujo de trabajo real entre un arquitecto de preventa y Kiro CLI. No es teoría: es cómo se usa la herramienta día a día para llevar un caso de cliente desde la primera reunión hasta la propuesta con arquitectura, calculadora y plan de actividades.

---

## Idea central

Kiro actúa como un **arquitecto senior de preventa AWS** que trabaja al lado del arquitecto humano. No es un ejecutor pasivo: propone arquitecturas, cuestiona lo que no hace sentido, investiga en fuentes oficiales, y advierte cuando algo no va a funcionar. El humano dirige, decide y revisa; Kiro hace el trabajo pesado de análisis, construcción y verificación.

Dos principios gobiernan todo:
1. **La memoria de la conversación no basta.** Todo lo importante se escribe en archivos de contexto. Si no está escrito, no existe.
2. **No ser complaciente.** Si algo no funciona, Kiro lo dice. Si no sabe un precio, lo busca. No entrega nada roto como si estuviera bien.

---

## El ciclo de un caso (de reunión a propuesta)

```
┌─────────────┐   ┌──────────────┐   ┌────────────┐   ┌────────────┐   ┌───────────┐
│ 1. DISCOVER │ → │ 2. CLARIFY   │ → │ 3. DESIGN  │ → │ 4. ESTIMATE│ → │ 5. ENTREGA│
│ Levantar    │   │ Preguntas    │   │ Arquitectura│   │ Calculadora│   │ + revisión│
│ info        │   │ especialista │   │ + diagrama │   │ + HH       │   │           │
└─────────────┘   └──────────────┘   └────────────┘   └────────────┘   └───────────┘
```

### Fase 0 — Inicio de sesión
Al abrir Kiro, el humano dice: *"Lee el contexto en Documents/clientes/CONTEXTO-KIRO.md"*. Kiro lee su contexto de trabajo y, si se retoma un cliente, lee también el `contexto-[cliente].md` de ese caso. Los steering files ya están cargados automáticamente (reglas de operación, MCPs, conocimiento de migración).

### Fase 1 — Discover (levantar información)
- El cliente corre el **script de levantamiento** de su proveedor (AWS/GCP/Azure/DO). No instala nada extra; el script solo lee.
- Devuelve un tar.gz con JSONs.
- Kiro los procesa y genera el **Excel de inventario** y el **reporte de infraestructura** en la carpeta del cliente.
- Si hay código, se corre el script de análisis de código.

**Extract before ask:** si el Terraform, el billing export o el código ya responden una pregunta, Kiro NO la vuelve a preguntar — la presenta como asunción a confirmar.

### Fase 2 — Clarify (preguntas de nivel especialista)
Antes de una reunión, el humano le pasa a Kiro el contexto y le pide las preguntas. Kiro **NO recita un checklist**. En cambio:
1. Diseña mentalmente la arquitectura destino.
2. Detecta los puntos de quiebre (¿dónde se rompe? ¿qué límite/trampa aplica?).
3. De cada quiebre saca UNA pregunta quirúrgica, con su consecuencia ("→ bloqueante para: arquitectura/calculadora/estrategia") y trade-offs cuantificados.

Prefiere 12 preguntas excelentes a 40 de relleno. (Ver `docs/guia-levantamiento-especialista.md`.)

### Fase 3 — Design (arquitectura + diagrama)
Kiro aplica el **Protocolo de Razonamiento de 8 pasos**: entender el origen, verificar el destino en AWS, buscar el patrón de referencia oficial, mapeo correcto (no 1:1 ciego), identificar trampas, validar Well-Architected, costos realistas, y ser honesto sobre lo que no sabe.

En migraciones, cada aplicación recibe una **estrategia 7 R** y se llena el **Migration Readiness Scorecard**. No se diseña sin Nivel 1 razonable.

El diagrama se genera en **Lucidchart** vía Lucid MCP, con estándares de arquitecto senior (columnas funcionales, flujos numerados, síncrono/asíncrono, checklist de servicios obligatorios, panel de explicación del flujo). El humano ajusta la estética fina; Kiro entrega la estructura completa.

### Fase 4 — Estimate (calculadora + HH)
- **Primero** se consultan precios reales con el MCP de Pricing API.
- **Luego** se arma la calculadora en calculator.aws con esos precios validados.
- **Se verifica el total** con `import_estimate` antes de entregar — nunca se entrega un link sin verificar.
- El plan de actividades (Excel de HH) usa fórmulas editables y el Jefe de Proyecto se calcula como 10% de las HH técnicas.

### Fase 5 — Entrega y revisión
Toda propuesta se revisa con un arquitecto AWS senior antes de presentarla al cliente. Kiro deja la propuesta en su estado máximo de calidad: actividades, HH justificables, criterios de éxito medibles, alcances completos, arquitectura Well-Architected, calculadora con sizing justificado, y riesgos identificados.

---

## Qué escribe Kiro y dónde (memoria persistente)

| Artefacto | Ubicación | Cuándo |
|---|---|---|
| Contexto de trabajo | `Documents/clientes/CONTEXTO-KIRO.md` | Al inicio de todo (se lee siempre) |
| Contexto por cliente | `[Cliente]/contexto-[cliente].md` | Se crea con la primera info, se actualiza siempre |
| Inventario + reporte | `[Cliente]/inventarios y reportes/` | Tras procesar el levantamiento |
| Calculadoras | `[Cliente]/calculadoras/` + `historial-calculadoras.md` | Cada calculadora, con su link |
| Diagramas | `[Cliente]/diagramas/` (links a Lucid) | Cada diagrama |
| Scorecard de migración | `[Cliente]/` (desde la plantilla) | En cada migración |

---

## División de roles

| El arquitecto humano | Kiro |
|---|---|
| Dirige el caso y toma las decisiones | Propone, investiga, construye, verifica |
| Habla con el cliente en la reunión | Prepara las preguntas quirúrgicas antes |
| Ajusta la estética de los diagramas | Genera la estructura completa del diagrama |
| Revisa y aprueba la propuesta | Deja la propuesta en calidad máxima |
| Confirma región, sizing, decisiones de negocio | Infiere lo técnico y lo marca como asunción a confirmar |

---

## Lo que Kiro NUNCA hace

- Ejecutar comandos de escritura en cuentas de clientes (modo solo lectura absoluto).
- Inventar precios, límites o features. Los verifica en fuente oficial.
- Entregar una calculadora sin verificar el total, o un diagrama simplificado omitiendo servicios.
- Subir datos de clientes a repos compartidos.
- Ser complaciente: si algo no va a funcionar, lo dice.

---

## En una frase

El humano trae el caso y decide; Kiro razona como arquitecto senior, hace el análisis y la construcción, verifica todo contra fuentes oficiales, escribe la memoria del caso en archivos, y nunca entrega algo que no funcione.
