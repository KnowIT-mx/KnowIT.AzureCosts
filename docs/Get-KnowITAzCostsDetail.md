---
Module Name: KnowIT.AzureCosts
schema: 2.0.0
---

[KnowIT.AzureCosts](README.md) › Get-KnowITAzCostsDetail

# Get-KnowITAzCostsDetail

## SINOPSIS

Obtiene el costo por recurso y por mes de una o varias suscripciones de Azure.

## SINTAXIS

### Month (predeterminado)

```
Get-KnowITAzCostsDetail
   [-Month] <String[]>
   [-SubscriptionId] <String[]>
   [-ResourceGroup <String[]>]
   [-Untagged]
   [-Tag <Hashtable>]
   [-TagColumn <String[]>]
   [-TagsAsJson]
   [-Metric <String>]
   [-Tenant <String>]
   [-Force]
   [<CommonParameters>]
```

### Range

```
Get-KnowITAzCostsDetail
   [-SubscriptionId] <String[]>
   -StartDate <DateTime>
   -EndDate <DateTime>
   [-ResourceGroup <String[]>]
   [-Untagged]
   [-Tag <Hashtable>]
   [-TagColumn <String[]>]
   [-TagsAsJson]
   [-Metric <String>]
   [-Tenant <String>]
   [-Force]
   [<CommonParameters>]
```

## DESCRIPCIÓN

El cmdlet **Get-KnowITAzCostsDetail** devuelve un objeto por recurso por mes, con el costo
acumulado del periodo, sus tags y los datos del recurso.

La primera vez que se pide un mes de una suscripción, el cmdlet descarga el detalle completo
de ese mes con la Cost Details API y lo guarda en el caché local. Los filtros se aplican
después sobre ese detalle, sin volver a consultar Azure. Ver
[about_KnowIT.AzureCosts](about_KnowIT.AzureCosts.md#caché).

El detalle se combina con el inventario de recursos del día para:

- **Tags:** si el recurso existe hoy, se usan sus tags actuales, que son los que alguien va a
  corregir. Si ya no existe, se usan los que tenía cuando generó el cargo.
- **Recursos borrados:** siguen saliendo, con `ExistsInInventory` en `$false`.
- **Cargos sin recurso** (Marketplace, soporte, reservas): salen como filas sin
  `ResourceId`, identificadas por `ServiceName` y `ChargeType`.
- **Data Factory:** el costo de los pipelines y triggers se suma a su factory.

## EJEMPLOS

### Ejemplo 1: Costo de un mes

```powershell
Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId '00000000-0000-0000-0000-000000000000'
```

Devuelve una fila por recurso con el costo de agosto de 2026, del más caro al más barato.

### Ejemplo 2: Varios meses

```powershell
Get-KnowITAzCostsDetail -Period 2026-06, 2026-07, 2026-08 -SubscriptionId $sub |
    Group-Object Month |
    Select-Object Name, @{ Name = 'Cost'; Expression = { ($_.Group | Measure-Object Cost -Sum).Sum } }
```

Con varios meses sale una fila por recurso por mes. El ejemplo calcula el total de cada mes.

### Ejemplo 3: Rango de fechas

```powershell
Get-KnowITAzCostsDetail -StartDate 2026-07-15 -EndDate 2026-08-14 -SubscriptionId $sub
```

El rango cruza dos meses: devuelve las filas de julio (del 15 al 31) y las de agosto (del 1 al
14), cada una con su `Month`.

### Ejemplo 4: Cuánto gastan los recursos sin tags

```powershell
Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -Untagged | Measure-Object Cost -Sum
```

### Ejemplo 5: Filtrar por tags

```powershell
Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -Tag @{ Environment = 'Prod*'; Role = 'Web' }
```

Devuelve los recursos cuyo tag `Environment` empieza con "Prod" **y** cuyo tag `Role` es "Web".

### Ejemplo 6: Exportar con tags en columnas

```powershell
Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -TagColumn Environment, Owner -TagsAsJson |
    Export-Csv costos-2026-08.csv
```

`Environment` y `Owner` salen como columnas propias; los demás tags quedan en la columna
`Tags` como JSON.

### Ejemplo 7: Costo por resource group

```powershell
Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub |
    Group-Object ResourceGroup |
    Select-Object Name, @{ Name = 'Cost'; Expression = { ($_.Group | Measure-Object Cost -Sum).Sum } } |
    Sort-Object Cost -Descending
```

### Ejemplo 8: Varias suscripciones

```powershell
Get-AzSubscription | Where-Object Name -like '*Prod*' | Get-KnowITAzCostsDetail -Month 2026-08
```

Cada suscripción que no esté en caché es una consulta a la Cost Details API, que tarda unos
minutos.

## PARÁMETROS

### -EndDate

Fin del rango de fechas, inclusive. Se usa junto con `-StartDate` en lugar de `-Month`.

```yaml
Type: DateTime
Parameter Sets: Range
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Force

Vuelve a descargar el detalle de costos y el inventario aunque estén en caché. Gasta una
consulta a la Cost Details API por cada suscripción y mes.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Metric

Tipo de costo. `ActualCost` es el costo como se factura: una compra de reserva aparece
completa el día que se compra. `AmortizedCost` reparte las reservas entre los días de su
vigencia y los recursos que las usan. Cada métrica tiene su propio caché.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: ActualCost, AmortizedCost

Required: False
Position: Named
Default value: ActualCost
Accept pipeline input: False
Accept wildcard characters: False
```

### -Month

Uno o varios meses, en formato `yyyy-MM`. No puede ser un mes que todavía no empieza ni
tener más de 13 meses de antigüedad.

```yaml
Type: String[]
Parameter Sets: Month
Aliases: Period

Required: True
Position: 0
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ResourceGroup

Devuelve solo los recursos de estos resource groups. Acepta comodines y no distingue
mayúsculas. No se puede combinar con `-Untagged`.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: True
```

### -StartDate

Inicio del rango de fechas. Se usa junto con `-EndDate` en lugar de `-Month`. Los meses que
el rango cubre a medias solo suman los días dentro del rango.

```yaml
Type: DateTime
Parameter Sets: Range
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -SubscriptionId

Una o varias suscripciones. Es obligatorio porque cada suscripción que no está en caché es
una consulta a la Cost Details API.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases: Id

Required: True
Position: 1
Default value: None
Accept pipeline input: True (ByPropertyName)
Accept wildcard characters: False
```

### -Tag

Devuelve solo los recursos cuyos tags cumplen **todos** los pares indicados. Los nombres de
tag no distinguen mayúsculas y los valores aceptan comodines: `@{ Environment = 'Prod*' }`.
Un recurso que no tiene el tag no cumple el filtro. No se puede combinar con `-Untagged`.

En la consola, Tab completa con los pares tag=valor que existen en la suscripción indicada.

```yaml
Type: Hashtable
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: True
```

### -TagColumn

Tags que, además de ir en la propiedad `Tags`, se agregan como propiedades propias, listas
para `Export-Csv`. Un recurso que no tiene el tag queda con la propiedad vacía. Si un tag se
llama igual que una propiedad existente (por ejemplo `Location`), la propiedad se llama
`tag_Location`.

En la consola, Tab completa con los tags que existen en la suscripción indicada.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -TagsAsJson

Entrega la propiedad `Tags` como texto JSON compacto en lugar de hashtable, listo para
`Export-Csv`. Los tags van en orden alfabético y un recurso sin tags queda como `{}`. Los
filtros y `-TagColumn` se aplican antes de la conversión.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Tenant

Tenant para el que se pide el token. Sin este parámetro se usa el tenant de la sesión de Az.

```yaml
Type: String
Parameter Sets: (All)
Aliases: TenantId

Required: False
Position: Named
Default value: Tenant de la sesión de Az
Accept pipeline input: False
Accept wildcard characters: False
```

### -Untagged

Devuelve solo los recursos sin ningún tag. Un tag con valor vacío no cuenta como tag. No se
puede combinar con `-ResourceGroup` ni con `-Tag`.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters

Este cmdlet admite los parámetros comunes: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction y -WarningVariable. Para más información, consulte
[about_CommonParameters](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters).

## ENTRADAS

### System.String[]

Puede canalizar objetos con una propiedad `SubscriptionId` o `Id`, como los de
`Get-AzSubscription`.

## SALIDAS

### KnowIT.AzureCosts.CostDetail

Un objeto por recurso por mes, con estas propiedades:

| Propiedad | Tipo | Descripción |
|---|---|---|
| Month | String | Mes, `yyyy-MM`. |
| SubscriptionId | String | Suscripción. |
| ResourceId | String | Id del recurso. Vacío en los cargos sin recurso. |
| ResourceName | String | Nombre del recurso. |
| ResourceType | String | Tipo de recurso. |
| ResourceGroup | String | Resource group. |
| Location | String | Región. |
| ServiceName | String | Servicio que generó el cargo. |
| ChargeType | String | Tipo de cargo. Solo en los cargos sin recurso (`Purchase`, por ejemplo). |
| Cost | Double | Costo del periodo, en la moneda de facturación. |
| Currency | String | Moneda de facturación. |
| ExistsInInventory | Boolean | `$true` si el recurso existe hoy. |
| Tags | Hashtable | Tags efectivos (ver la descripción). Con `-TagsAsJson`, texto JSON. |

Con `-TagColumn` se agrega una propiedad más por cada tag indicado.

## NOTAS

- Requiere **Cost Management Reader** (o Contributor) sobre la suscripción para el detalle
  de costos, y **Reader** para el inventario. Sin Reader, el costo sale igual pero ningún
  recurso cruza con el inventario (`ExistsInInventory` en `$false` y tags del cargo).
- En suscripciones CSP el partner debe tener activada la política de cost visibility. Los
  montos salen a precio retail de pay-as-you-go y no cuadran contra la factura.
- Microsoft pide no consultar la Cost Details API más de una vez al día por suscripción. No
  uses `-Force` sin necesidad.
- Un mes sin datos de costo muestra una advertencia y no devuelve filas.
- Las filas se ordenan por suscripción, mes y costo descendente.

## VÍNCULOS RELACIONADOS

- [Export-KnowITAzCostsRaw](Export-KnowITAzCostsRaw.md)
- [Get-KnowITAzCostsResourceInventory](Get-KnowITAzCostsResourceInventory.md)
- [Clear-KnowITAzCostsCache](Clear-KnowITAzCostsCache.md)
- [about_KnowIT.AzureCosts](about_KnowIT.AzureCosts.md)
- [Cost Details API](https://learn.microsoft.com/rest/api/cost-management/generate-cost-details-report)
