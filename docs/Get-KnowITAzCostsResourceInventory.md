---
Module Name: KnowIT.AzureCosts
schema: 2.0.0
---

[KnowIT.AzureCosts](README.md) › Get-KnowITAzCostsResourceInventory

# Get-KnowITAzCostsResourceInventory

## SINOPSIS

Obtiene los recursos de Azure de una o varias suscripciones, con sus tags de hoy.

## SINTAXIS

### All (predeterminado)

```
Get-KnowITAzCostsResourceInventory
   [[-SubscriptionId] <String[]>]
   [-Tenant <String>]
   [-TagsAsJson]
   [-Force]
   [<CommonParameters>]
```

### ResourceGroup

```
Get-KnowITAzCostsResourceInventory
   [[-SubscriptionId] <String[]>]
   -ResourceGroup <String[]>
   [-Tenant <String>]
   [-TagsAsJson]
   [-Force]
   [<CommonParameters>]
```

### Untagged

```
Get-KnowITAzCostsResourceInventory
   [[-SubscriptionId] <String[]>]
   -Untagged
   [-Tenant <String>]
   [-TagsAsJson]
   [-Force]
   [<CommonParameters>]
```

## DESCRIPCIÓN

El cmdlet **Get-KnowITAzCostsResourceInventory** devuelve un objeto por cada recurso ARM de
las suscripciones indicadas, con sus tags actuales. Consulta Azure Resource Graph.

Incluye los recursos que no generan cargo, como un grupo de seguridad de red o un disco
desasociado. Esos recursos no aparecen en el detalle de costos, así que el inventario es la
forma de encontrarlos.

El inventario se guarda en el caché local, un archivo por suscripción por día. Las llamadas
siguientes del mismo día no vuelven a consultar Azure, salvo con `-Force`. Ver
[about_KnowIT.AzureCosts](about_KnowIT.AzureCosts.md#caché).

## EJEMPLOS

### Ejemplo 1: Inventario de una suscripción

```powershell
Get-KnowITAzCostsResourceInventory -SubscriptionId '00000000-0000-0000-0000-000000000000'
```

Devuelve todos los recursos de la suscripción, ordenados por resource group y nombre.

### Ejemplo 2: Recursos sin ningún tag, exportados a CSV

```powershell
Get-KnowITAzCostsResourceInventory -SubscriptionId $sub -Untagged -TagsAsJson |
    Export-Csv recursos-sin-tags.csv
```

`-Untagged` deja solo los recursos sin tags. `-TagsAsJson` hace que la columna `Tags` del CSV
tenga texto JSON (`{}` en este caso) en lugar de `System.Collections.Hashtable`.

### Ejemplo 3: Recursos de varios resource groups

```powershell
Get-KnowITAzCostsResourceInventory -SubscriptionId $sub -ResourceGroup 'rg-prod-*', 'rg-shared'
```

Los nombres aceptan comodines y no distinguen mayúsculas.

### Ejemplo 4: Todas las suscripciones accesibles

```powershell
Get-KnowITAzCostsResourceInventory | Group-Object SubscriptionId | Select-Object Name, Count
```

Sin `-SubscriptionId` se usan todas las suscripciones habilitadas a las que tiene acceso la
sesión, incluidas las delegadas por Azure Lighthouse. El resultado muestra cuántos recursos
tiene cada una.

### Ejemplo 5: Suscripciones desde Get-AzSubscription

```powershell
Get-AzSubscription | Where-Object Name -like '*Prod*' | Get-KnowITAzCostsResourceInventory
```

El parámetro `-SubscriptionId` acepta por pipeline la propiedad `Id` de los objetos de
`Get-AzSubscription`.

### Ejemplo 6: Filtrar por el valor de un tag

```powershell
Get-KnowITAzCostsResourceInventory -SubscriptionId $sub |
    Where-Object { $_.Tags['Environment'] -eq 'Production' }
```

Sin `-TagsAsJson`, `Tags` es una hashtable y se puede consultar por nombre de tag.

## PARÁMETROS

### -Force

Vuelve a consultar Resource Graph aunque el inventario de hoy ya esté en caché.

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

### -ResourceGroup

Devuelve solo los recursos de estos resource groups. Acepta comodines y no distingue
mayúsculas. No se puede combinar con `-Untagged`.

```yaml
Type: String[]
Parameter Sets: ResourceGroup
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: True
```

### -SubscriptionId

Suscripciones que se van a inventariar. Sin este parámetro se usan todas las suscripciones
habilitadas a las que tiene acceso la sesión.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases: Id

Required: False
Position: 0
Default value: Todas las suscripciones accesibles
Accept pipeline input: True (ByPropertyName)
Accept wildcard characters: False
```

### -TagsAsJson

Entrega la propiedad `Tags` como texto JSON compacto en lugar de hashtable, listo para
`Export-Csv`: `{"Environment":"Production","Owner":"Equipo-FinOps"}`. Los tags van en orden alfabético
y un recurso sin tags queda como `{}`.

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
puede combinar con `-ResourceGroup`.

```yaml
Type: SwitchParameter
Parameter Sets: Untagged
Aliases:

Required: True
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

### KnowIT.AzureCosts.Resource

Un objeto por recurso, con estas propiedades:

| Propiedad | Tipo | Descripción |
|---|---|---|
| ResourceId | String | Id completo del recurso, tal como lo entrega Resource Graph. |
| Name | String | Nombre del recurso. |
| Type | String | Tipo de recurso, en minúsculas (`microsoft.compute/virtualmachines`). |
| ResourceGroup | String | Resource group del recurso. |
| Location | String | Región del recurso. |
| SubscriptionId | String | Suscripción del recurso. |
| Tags | Hashtable | Tags del recurso. Las llaves no distinguen mayúsculas. Con `-TagsAsJson`, texto JSON. |

## NOTAS

- Requiere el rol **Reader** sobre la suscripción. Sin él, Resource Graph no devuelve los
  recursos y el inventario sale vacío o incompleto.
- El resultado se ordena por suscripción, resource group y nombre, con comparación ordinal:
  sale igual en cualquier máquina.
- Solo se conserva en caché el inventario del día; los de días anteriores se borran al
  guardar uno nuevo.

## VÍNCULOS RELACIONADOS

- [Get-KnowITAzCostsDetail](Get-KnowITAzCostsDetail.md)
- [Clear-KnowITAzCostsCache](Clear-KnowITAzCostsCache.md)
- [about_KnowIT.AzureCosts](about_KnowIT.AzureCosts.md)
- [Azure Resource Graph](https://learn.microsoft.com/azure/governance/resource-graph/overview)
