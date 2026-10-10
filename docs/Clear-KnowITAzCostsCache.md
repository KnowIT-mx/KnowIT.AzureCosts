---
Module Name: KnowIT.AzureCosts
schema: 2.0.0
---

[KnowIT.AzureCosts](README.md) › Clear-KnowITAzCostsCache

# Clear-KnowITAzCostsCache

## SINOPSIS

Borra el caché local de detalle de costos e inventario.

## SINTAXIS

```
Clear-KnowITAzCostsCache
   [[-SubscriptionId] <String[]>]
   [-Month <String[]>]
   [-WhatIf]
   [-Confirm]
   [<CommonParameters>]
```

## DESCRIPCIÓN

El cmdlet **Clear-KnowITAzCostsCache** borra archivos del caché local en
`~/.knowit/KnowIT.AzureCosts`. Sin parámetros borra todo el caché. Con `-SubscriptionId` borra
el caché de esas suscripciones, y con `-Month` solo el detalle de costos de esos meses, de
todas las métricas, sin tocar el inventario.

Normalmente no hace falta: el caché caduca solo (ver
[about_KnowIT.AzureCosts](about_KnowIT.AzureCosts.md#caché)). Borrar el detalle de un mes
obliga a volver a consultar la Cost Details API, que Microsoft pide no usar más de una vez al
día por suscripción. Para renovar un dato sin borrarlo, usa `-Force` en el comando de
consulta.

## EJEMPLOS

### Ejemplo 1: Ver qué se borraría

```powershell
Clear-KnowITAzCostsCache -WhatIf
```

Muestra las carpetas que se borrarían, sin borrar nada.

### Ejemplo 2: Borrar un mes de una suscripción

```powershell
Clear-KnowITAzCostsCache -SubscriptionId '00000000-0000-0000-0000-000000000000' -Month 2026-09
```

### Ejemplo 3: Borrar el caché de varias suscripciones

```powershell
Get-AzSubscription | Where-Object Name -like '*Dev*' | Clear-KnowITAzCostsCache
```

## PARÁMETROS

### -Confirm

Pide confirmación antes de borrar cada archivo o carpeta.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Month

Borra solo el detalle de costos de estos meses (`yyyy-MM`), de todas las métricas. El
inventario no se toca.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases: Period

Required: False
Position: Named
Default value: Todos los meses
Accept pipeline input: False
Accept wildcard characters: False
```

### -SubscriptionId

Borra solo el caché de estas suscripciones.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases: Id

Required: False
Position: 0
Default value: Todas las suscripciones en caché
Accept pipeline input: True (ByPropertyName)
Accept wildcard characters: False
```

### -WhatIf

Muestra qué se borraría, sin borrar nada.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi

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

### None

Este cmdlet no devuelve nada.

## VÍNCULOS RELACIONADOS

- [Get-KnowITAzCostsDetail](Get-KnowITAzCostsDetail.md)
- [Export-KnowITAzCostsRaw](Export-KnowITAzCostsRaw.md)
- [Get-KnowITAzCostsResourceInventory](Get-KnowITAzCostsResourceInventory.md)
- [about_KnowIT.AzureCosts](about_KnowIT.AzureCosts.md)
