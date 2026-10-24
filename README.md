# Seguimiento de Leads — Automatización con n8n

Proyecto del curso **Automatización inteligente de procesos con n8n** (EAM, periodo 2026 II), Corte 2.

Solución que recibe solicitudes de leads (formulario web o mensaje de Telegram), valida y clasifica su nivel de interés, define la acción comercial correspondiente y registra el resultado en una base de datos externa (Baserow), avisando al vendedor por Telegram.

## Integrantes

| Integrante | Responsabilidad en esta entrega |
| --- | --- |
| Javier | Repositorio, README y diagramas |
| Luis | Bitácora unificada y evidencias |
| Simon | Workflows finales en JSON y subworkflow |

> Pendiente: completar nombres completos antes de la entrega.

## Problema que resuelve

Los leads llegan por distintos canales (formulario web, WhatsApp, Telegram, teléfono) sin un proceso centralizado. No se sabe qué lead es prioritario y los de interés alto se enfrían antes de recibir respuesta. La solución automatiza la captura, la validación, la clasificación por interés y el registro del lead con una acción concreta de seguimiento.

## Alcance actual

**Disponible en esta versión:**

- Captura de leads por formulario n8n y por webhook de Telegram.
- Validación de campos obligatorios (nombre, correo, interés, mensaje, canal).
- Clasificación del correo como empresarial o no empresarial.
- Asignación de acción según el nivel de interés (ALTO / MEDIO / BAJO).
- Registro del lead en Baserow mediante `HTTP Request`.
- Confirmación al usuario por Telegram.

**Fuera de alcance:**

- Panel de reportes o métricas de conversión.
- Integración con WhatsApp Business API.
- Autenticación de usuarios finales.
- Notificaciones por correo o Slack.

## Arquitectura

```text
Formulario n8n ─┐
                ├─> Validación → Clasificación por interés → Acción → Baserow
Telegram (webhook) ─┘                                      └─> Aviso por Telegram
```

| Workflow | Responsabilidad |
| --- | --- |
| `Workflow_01_DatosValidacion.json` | Primer acercamiento: carga de campos de un lead y validación básica de correo e interés. |
| `Workflow_02_LogicaControlFlujo.json` | Lógica de control: filtros de campos, clasificación por interés, evaluación de correo empresarial y acciones. |
| `Workflow_03_Formulario.json` | Entrada real por `Form Trigger` (nombre, correo, interés, mensaje, canal). |
| `Workflow_04_API.json` | Persistencia del lead clasificado en Baserow mediante `HTTP Request`. |
| `Workflow_05_WebhookTelegram.json` | Entrada por webhook de Telegram: parseo del mensaje, validación, clasificación, guardado en Baserow y confirmación al chat. |
| Subworkflow | Reutilización de una responsabilidad concreta, con entradas y salidas definidas. *(En desarrollo.)* |

> Los diagramas de proceso manual y proceso automatizado se encuentran en `documentacion/diagramas/`.

## Requisitos

- **n8n** 2.35.7 (self-hosted).
- **Node.js** 24.x.
- **cloudflared** (solo para exponer n8n y registrar el webhook de Telegram).
- **Cuenta de Telegram** con un bot creado en `@BotFather` (token del bot).
- **Cuenta de Baserow** con un token de API y una tabla preparada.
- Credenciales de n8n: `Telegram account` (tipo `telegramApi`) y `Baserow Token account` (tipo `baserowTokenApi`).

## Configuración

1. **n8n**: instalar y arrancar con `n8n start` (por defecto en `http://localhost:5678`).
2. **Baserow**: crear una tabla con las columnas `nombre`, `correo`, `interes`, `mensaje`, `canal`, `submittedAt`, `formMode`, `es_empresarial` y `accion`. Los campos `interes`, `canal` y `formMode` son listas de selección: cargar como opciones los valores que envían los workflows (`ALTO`/`MEDIO`/`BAJO`, el canal de origen y el modo de entrada).
3. **Credenciales en n8n**: crear la credencial de Telegram con el token del bot y la de Baserow con un token de API con permiso de escritura sobre la tabla.
4. **Token del bot**: crear un archivo `.env` **local, fuera del repositorio**, junto al script del túnel, con `TG_TOKEN=<token>`. El archivo `.env` está excluido por `.gitignore` y no debe subirse.

> Este repositorio no contiene tokens, credenciales ni archivos de entorno con valores reales. Cada persona que replique el proyecto debe crear sus propias credenciales.

## Importación y conexiones

1. Importar los JSON de `workflows/` en n8n (menú *Import from File*).
2. Verificar el orden: importar primero el subworkflow y luego el workflow principal que lo invoca.
3. Reasignar las credenciales de Telegram y Baserow a los nodos `Aviso de formato al chat`, `Confirmar registro al chat` y `HTTP · Guardar fila Baserow1`.
4. Revisar el ID de la tabla de Baserow en la URL del nodo `HTTP Request`; debe apuntar a la tabla creada en la cuenta propia.
5. Si se usa un manejador de errores, asociarlo en la configuración del workflow.

## Ejecución

**Prueba con el formulario**

1. Abrir el workflow `Workflow_03_Formulario.json` y ejecutar el `Form Trigger`.
2. Completar el formulario con datos ficticios, por ejemplo:
   `Laura Gómez | laura@empresa.com | ALTO | Quiero agendar una visita`.
3. Verificar la ejecución en n8n y la fila creada en Baserow.

**Prueba con Telegram**

1. Activar `Workflow_05_WebhookTelegram.json` en n8n.
2. En otra terminal, ejecutar el script del túnel:
   ```bash
   ./iniciar_bot.sh
   ```
   El script levanta un túnel de `cloudflared`, detecta la URL pública y registra automáticamente el webhook en Telegram.
3. Esperar el mensaje `Telegram respondió: {"ok":true,...}`.
4. Escribir al bot con el formato:
   ```text
   Nombre | correo | ALTO, MEDIO o BAJO | mensaje
   ```
5. Verificar la confirmación en el chat y la fila creada en Baserow.

**Detener las pruebas**

- `Ctrl+C` en la terminal del túnel: cierra el túnel y el webhook deja de recibir mensajes.
- Desactivar el workflow en n8n para evitar ejecuciones automáticas.

> La URL del túnel es temporal: cambia en cada ejecución y deja de estar disponible al cerrar el proceso. Por eso el script vuelve a registrar el webhook cada vez.

## Manejo de errores

- **Entrada inválida por Telegram**: si falta un campo o el interés no es `ALTO`, `MEDIO` o `BAJO`, el flujo responde con un mensaje de formato al chat y no registra el lead.
- **Error técnico en Baserow** (por ejemplo, `ERROR_REQUEST_BODY_VALIDATION`): la ejecución se detiene en el nodo `HTTP Request` y queda registrada en n8n con el detalle de la respuesta. La recuperación consiste en corregir el dato u opción rechazada y volver a enviar el mensaje.
- **Duplicados**: cada Lead se envía una sola vez por el usuario; si se repite la ejecución con los mismos datos se crea una fila nueva, por lo que la recuperación debe revisar la fila previa antes de reintentar.

## Prueba de ejemplo

| Campo | Valor |
| --- | --- |
| Entrada | `Prueba Uno \| prueba@empresa.com \| ALTO \| Quiero una agenda de visita` |
| Pasos | Activar workflow 5 → ejecutar `iniciar_bot.sh` → enviar el mensaje al bot |
| Resultado esperado | Respuesta `Lead registrado: Prueba Uno \| Acción: Notificacion inmediata` y nueva fila en Baserow con `es_empresarial: true` |
| Resultado observado | *(Pendiente de completar con la evidencia de la prueba)* |

## Documentación y evidencias

- Bitácora unificada: `documentacion/Bitacora_Unificada_Proyecto.md` *(pendiente)*
- Presentación en PDF: `documentacion/Presentacion_Corte_2.pdf` *(pendiente)*
- Diagramas: `documentacion/diagramas/`
- Evidencias de pruebas: `documentacion/evidencias/`

## Estado del proyecto

| Clasificación | Elementos |
| --- | --- |
| **Implementado** | Formulario, webhook de Telegram, validaciones, clasificación por interés, guardado en Baserow, confirmación por Telegram. |
| **Simulado** | Datos de prueba enviados manualmente; no hay tráfico real de producción. |
| **Propuesto** | Subworkflow de responsabilidad única, manejador de errores con registro persistente, integración con WhatsApp Business API, panel de métricas. |
