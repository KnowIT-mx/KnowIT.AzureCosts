---
Module Name: KnowIT.AzureCosts
Module Guid: abc91076-c63c-418c-b713-4e7ff5363fbd
Help Version: 0.2.0
Locale: es-MX
---

# Módulo KnowIT.AzureCosts

Consulta y analiza costos de Azure por suscripción, resource group, recurso y tag, con la
Cost Details API y Azure Resource Graph, y un caché local para no repetir consultas.

Los comandos devuelven objetos de PowerShell; para exportarlos se usan los comandos nativos
(`Export-Csv`, `ConvertTo-Json`, `Group-Object`…). El módulo solo lee: no crea ni modifica
nada en Azure.

## Inventario

| Cmdlet | Descripción |
|---|---|
| [Get-KnowITAzCostsResourceInventory](Get-KnowITAzCostsResourceInventory.md) | Obtiene los recursos de Azure de una o varias suscripciones, con sus tags de hoy. |

## Costos

| Cmdlet | Descripción |
|---|---|
| [Get-KnowITAzCostsDetail](Get-KnowITAzCostsDetail.md) | Obtiene el costo por recurso y por mes de una o varias suscripciones. |
| [Export-KnowITAzCostsRaw](Export-KnowITAzCostsRaw.md) | Exporta a CSV el detalle diario por recurso tal como lo entrega la Cost Details API, con los tags en columnas. |

## Caché

| Cmdlet | Descripción |
|---|---|
| [Clear-KnowITAzCostsCache](Clear-KnowITAzCostsCache.md) | Borra el caché local de detalle de costos e inventario. |

## Conceptos

| Tema | Descripción |
|---|---|
| [about_KnowIT.AzureCosts](about_KnowIT.AzureCosts.md) | Permisos, caché, periodos, tags y límites de la Cost Details API. |
