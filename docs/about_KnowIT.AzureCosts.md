---
Module Name: KnowIT.AzureCosts
schema: 2.0.0
---

[KnowIT.AzureCosts](README.md) › about_KnowIT.AzureCosts

# about_KnowIT.AzureCosts

## DESCRIPCIÓN BREVE

Conceptos del módulo KnowIT.AzureCosts: permisos, caché, periodos, tags y límites de la
Cost Details API.

## DESCRIPCIÓN LARGA

### Permisos

Los comandos usan la sesión de `Connect-AzAccount`, de un usuario o de una managed identity.
La identidad necesita estos roles sobre cada suscripción:

| Rol | Lo necesitan |
|---|---|
| **Cost Management Reader** (o Contributor) | [Get-KnowITAzCostsDetail](Get-KnowITAzCostsDetail.md), [Export-KnowITAzCostsRaw](Export-KnowITAzCostsRaw.md) |
| **Reader** | [Get-KnowITAzCostsResourceInventory](Get-KnowITAzCostsResourceInventory.md), [Get-KnowITAzCostsDetail](Get-KnowITAzCostsDetail.md) y `Export-KnowITAzCostsRaw -TagsFromInventory` |

Los dos roles son de solo lectura. Para asignarlos se necesita Owner o User Access
Administrator en la suscripción, y el permiso puede tardar hasta 30 minutos en aplicarse.

**Suscripciones CSP.** El partner debe activar la política de *cost visibility* para el
cliente; sin ella la Cost Details API responde 403. Los montos salen a precio retail de
pay-as-you-go, sin los descuentos ni créditos del partner, así que no cuadran contra la
factura del CSP.

**Azure Lighthouse.** Basta con iniciar sesión en el tenant que administra: el token sirve
para las suscripciones delegadas, siempre que la delegación incluya los roles de arriba.

**Tipos de suscripción.** La Cost Details API funciona con Enterprise Agreement y Microsoft
Customer Agreement (incluye CSP). Pay-as-you-go no está soportado.

### Caché

El caché vive en `~/.Azure/KnowIT.AzureCosts`, junto a los archivos de Az, con una carpeta
por suscripción. Cada usuario mantiene el suyo y sobrevive a reinicios.

```
~/.Azure/KnowIT.AzureCosts/<suscripción>/
    inventory-<yyyy-MM-dd>.json          inventario del día
    cost-<métrica>-<yyyy-MM>.json        manifiesto del mes
    cost-<métrica>-<yyyy-MM>-partN.csv   detalle tal como lo entrega la API
```

La Cost Details API no filtra por resource group ni por tag. Por eso, cuando falta un mes, se
descarga el detalle **completo** de la suscripción y todos los filtros se aplican
localmente: pedir otro resource group u otros tags del mismo mes no vuelve a consultar Azure.

| Dato | Vigencia |
|---|---|
| Detalle de un mes cerrado | Permanente, si se descargó al menos 5 días después del cierre |
| Detalle del mes en curso o recién cerrado | 24 horas |
| Inventario de recursos | Un archivo por día; al guardar uno nuevo se borran los anteriores |
| Mes sin datos de costo | Igual que un mes con datos: no se vuelve a preguntar mientras esté vigente |

Un CSV sin manifiesto es una descarga interrumpida y no cuenta: se vuelve a descargar.

El parámetro `-Force` de los comandos de consulta ignora el caché.
[Clear-KnowITAzCostsCache](Clear-KnowITAzCostsCache.md) lo borra.

### Periodos

[Get-KnowITAzCostsDetail](Get-KnowITAzCostsDetail.md) y
[Export-KnowITAzCostsRaw](Export-KnowITAzCostsRaw.md) aceptan una de dos formas:

- `-Month` (alias `-Period`): uno o varios meses completos, `yyyy-MM`.
- `-StartDate` y `-EndDate`: un rango de fechas, ambas inclusive. El caché siempre guarda
  meses completos; los meses que el rango cubre a medias solo suman los días dentro del
  rango.

`Get-KnowITAzCostsDetail` devuelve una fila por recurso **por mes**, aunque el periodo abarque
varios meses.

### Tags

Los nombres de tag no distinguen mayúsculas, como en Azure. Un tag con valor vacío no cuenta
como tag.

Cada comando usa los tags de un momento distinto:

| Comando | Tags |
|---|---|
| `Get-KnowITAzCostsResourceInventory` | Los de hoy. |
| `Get-KnowITAzCostsDetail` | Los de hoy si el recurso sigue existiendo, porque son los que alguien va a corregir; si ya no existe, los que tenía cuando generó el cargo. |
| `Export-KnowITAzCostsRaw` | Los que tenía el recurso el día del cargo. Con `-TagsFromInventory`, los de hoy para los recursos que siguen existiendo. |

**Filtros.** `-Tag @{ Nombre = 'valor' }` exige que se cumplan todos los pares, y los valores
aceptan comodines. `-Untagged` deja solo lo que no tiene ningún tag y no se combina con
`-Tag` ni con `-ResourceGroup`.

**Exportar.** La propiedad `Tags` es una hashtable, y `Export-Csv` la escribiría como
`System.Collections.Hashtable`. Para exportar hay dos opciones:

- `-TagsAsJson`: la columna `Tags` sale como JSON compacto.
- `-TagColumn`: los tags indicados salen como columnas propias. Si un tag se llama igual que
  una propiedad o columna existente, se le antepone `tag_`.

**Autocompletado.** En la consola, `-TagColumn` y `-Tag` completan con Tab los tags y valores
que existen en la suscripción indicada en `-SubscriptionId`. Si el inventario del día no
está en caché, se consulta Resource Graph.

### Límites de la Cost Details API

- Un mes por consulta, hasta 13 meses hacia atrás.
- Los datos de un mes recién cerrado tardan unos días en consolidarse.
- Solo trabaja a nivel de suscripción, no de resource group ni de management group.
- Microsoft pide no consultarla más de una vez al día por suscripción; si se excede,
  responde 429.

## VEA TAMBIÉN

- [Get-KnowITAzCostsResourceInventory](Get-KnowITAzCostsResourceInventory.md)
- [Get-KnowITAzCostsDetail](Get-KnowITAzCostsDetail.md)
- [Export-KnowITAzCostsRaw](Export-KnowITAzCostsRaw.md)
- [Clear-KnowITAzCostsCache](Clear-KnowITAzCostsCache.md)
- [Cost Management para partners](https://learn.microsoft.com/azure/cost-management-billing/costs/get-started-partners)
- [Obtener conjuntos pequeños de datos de costos a petición](https://learn.microsoft.com/azure/cost-management-billing/automate/get-small-usage-datasets-on-demand)
