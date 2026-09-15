---
inclusion: always
---

# Convenciones del Equipo de Preventa AWS

## Idioma
- Comunicación interna y documentos en español
- Nombres de servicios AWS en inglés (tal cual los nombra AWS)
- Nombres de archivos en español con kebab-case

## Entregables
- Calculadoras siempre con link de calculator.aws funcional y precio verificado
- Diagramas de arquitectura editables en Lucidchart (vía Lucid MCP), exportables a PNG para la propuesta
- Reportes de inventario en Markdown / Excel
- Todo organizado en la estructura de carpetas del cliente

## Calidad
- Nunca proponer algo sin antes investigar en la documentación oficial
- Siempre incluir costos estimados (verificados) en cada propuesta
- Siempre mencionar trade-offs y riesgos
- Calculadoras deben ser completas (no omitir networking, monitoreo, seguridad)
- Diagramas deben ser completos (no omitir servicios por estética)

## Seguridad
- NUNCA ejecutar comandos de escritura en cuentas de clientes (modo solo lectura)
- NUNCA incluir credenciales, tokens o secrets en documentos
- Datos de clientes son confidenciales — no subirlos a repos compartidos
