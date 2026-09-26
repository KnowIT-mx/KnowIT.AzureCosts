---
Module Name: KnowIT.AzureCosts
schema: 2.0.0
---

[KnowIT.AzureCosts](README.md) › Export-KnowITAzCostsRaw

# Export-KnowITAzCostsRaw

## SINOPSIS

Exporta a CSV el detalle diario por recurso tal como lo entrega la Cost Details API, con los
tags en columnas.

## SINTAXIS

### Month (predeterminado)

```
Export-KnowITAzCostsRaw
   [-Month] <String[]>
   [-SubscriptionId] <String[]>
   -Path <String>
   [-ResourceGroup <String[]>]
   [-Untagged]
   [-Tag <Hashtable>]
   [-TagColumn <String[]>]
   [-TagsFromInventory]
   [-Metric <String>]
   [-Tenant <String>]
   [-Force]
   [<CommonParameters>]
```

### Range

```
Export-KnowITAzCostsRaw
   [-SubscriptionId] <String[]>
   -Path <String>
   -StartDate <DateTime>
   -EndDate <DateTime>
   [-ResourceGroup <String[]>]
   [-Untagged]
   [-Tag <Hashtable>]
   [-TagColumn <String[]>]
   [-TagsFromInventory]
   [-Metric <String>]
   [-Tenant <String>]
   [-Force]
   [<CommonParameters>]
```

## DESCRIPCIÓN

El cmdlet **Export-KnowITAzCostsRaw** escribe un solo archivo CSV con el mayor detalle que
entrega la Cost Details API: una fila por recurso, por día y por medidor, con todas las
columnas originales de la API.

A esas columnas agrega una por tag. Sin `-TagColumn` se agregan todos los tags que aparecen
en las filas exportadas, y a la fila cuyo recurso no tiene un tag se le deja vacío. Esto
facilita cargar el archivo en Excel o en un data mart sin tener que separar el JSON de tags.

A diferencia de [Get-KnowITAzCostsDetail](Get-KnowITAzCostsDetail.md), no acumula nada:

- Los tags son los que tenía el recurso **el día del cargo**. Con `-TagsFromInventory` se usan
  los de hoy para los recursos que siguen existiendo.
- Los pipelines y triggers de Data Factory quedan como filas propias; no se suman a su
  factory.

Usa el mismo caché local que [Get-KnowITAzCostsDetail](Get-KnowITAzCostsDetail.md). Ver
[about_KnowIT.AzureCosts](about_KnowIT.AzureCosts.md#caché).

## EJEMPLOS

### Ejemplo 1: Exportar un mes

```powershell
Export-KnowITAzCostsRaw -Month 2026-08 -SubscriptionId '00000000-0000-0000-0000-000000000000' -Path ./costos-2026-08.csv
```

Escribe el detalle diario de agosto de 2026 y devuelve el archivo generado.

### Ejemplo 2: Solo algunos tags como columna

```powershell
Export-KnowITAzCostsRaw -Month 2026-08 -SubscriptionId $sub -Path ./costos.csv -TagColumn Environment, Owner
```

Agrega únicamente las columnas `Environment` y `Owner`, aunque los recursos tengan más tags.

### Ejemplo 3: Tags de hoy en lugar de los del día del cargo

```powershell
Export-KnowITAzCostsRaw -Month 2026-08 -SubscriptionId $sub -Path ./costos.csv -TagsFromInventory
```

Útil si los tags se corrigieron después de que el recurso generó el cargo.

### Ejemplo 4: Varias suscripciones y un rango de fechas en un solo archivo

```powershell
Get-AzSubscription | Where-Object Name -like '*Prod*' |
    Export-KnowITAzCostsRaw -StartDate 2026-07-01 -EndDate 2026-09-30 -Path ./costos-q3.csv
```

Todas las suscripciones y los tres meses quedan en el mismo CSV; la columna de suscripción de
la API permite distinguirlas.

### Ejemplo 5: Solo las filas de un resource group

```powershell
Export-KnowITAzCostsRaw -Month 2026-08 -SubscriptionId $sub -Path ./rg-prod.csv -ResourceGroup 'rg-prod-*'
```

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

Vuelve a descargar el detalle de costos (y el inventario, con `-TagsFromInventory`) aunque
estén en caché. Gasta una consulta a la Cost Details API por cada suscripción y mes.

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

Tipo de costo: `ActualCost` o `AmortizedCost`. Ver
[Get-KnowITAzCostsDetail](Get-KnowITAzCostsDetail.md#-metric).

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

Uno o varios meses, en formato `yyyy-MM`.

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

### -Path

Ruta del CSV que se va a generar. Si el archivo existe, se reemplaza; si la carpeta no
existe, se crea.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ResourceGroup

Exporta solo las filas de estos resource groups. Acepta comodines y no distingue mayúsculas.
No se puede combinar con `-Untagged`.

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

Inicio del rango de fechas. Se usa junto con `-EndDate` en lugar de `-Month`.

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

Una o varias suscripciones.

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

Exporta solo las filas cuyos tags cumplen **todos** los pares indicados. Los valores aceptan
comodines. No se puede combinar con `-Untagged`. En la consola, Tab completa con los pares
tag=valor existentes.

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

Limita las columnas de tags a estos. Si un tag se llama igual que una columna del detalle
(por ejemplo `CostCenter`), la columna del tag se llama `tag_CostCenter`. En la consola, Tab
completa con los tags existentes.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: Todos los tags de las filas exportadas
Accept pipeline input: False
Accept wildcard characters: False
```

### -TagsFromInventory

Usa los tags de hoy (inventario de Resource Graph) en lugar de los que tenía el recurso el
día del cargo. Los recursos que ya no existen conservan los del cargo. Requiere el rol
**Reader** sobre la suscripción.

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

Exporta solo las filas sin ningún tag. No se puede combinar con `-ResourceGroup` ni con
`-Tag`.

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

### System.IO.FileInfo

El archivo CSV generado.

## NOTAS

- El CSV usa el mismo formato que `Export-Csv` de PowerShell 7: UTF-8 sin BOM y todos los
  campos entre comillas.
- Un mes de una suscripción grande puede tener decenas de miles de filas; el archivo se
  escribe directo, sin crear un objeto por fila.
- Requiere **Cost Management Reader** (o Contributor) sobre la suscripción. Con
  `-TagsFromInventory`, también **Reader**.
- Microsoft pide no consultar la Cost Details API más de una vez al día por suscripción.

## VÍNCULOS RELACIONADOS

- [Get-KnowITAzCostsDetail](Get-KnowITAzCostsDetail.md)
- [Clear-KnowITAzCostsCache](Clear-KnowITAzCostsCache.md)
- [about_KnowIT.AzureCosts](about_KnowIT.AzureCosts.md)
- [Campos del detalle de costos](https://learn.microsoft.com/azure/cost-management-billing/automate/understand-usage-details-fields)
