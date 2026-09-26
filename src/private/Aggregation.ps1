function MergeResourceCost
{
    # Suma el detalle diario de un mes en una fila por recurso. Devuelve los objetos sin
    # filtrar; los filtros se aplican despues sobre los tags efectivos.
    param(
        [string]$SubscriptionId,
        $Period,
        [System.Collections.Generic.List[object]]$Rows,
        [string[]]$Headers,
        [hashtable]$InventoryIndex
    )

    $map = NewColumnMap $Headers
    $column = { param($row, $field) $name = $map[$field]; $name ? "$($row.$name)".Trim() : '' }

    if(!$map.Cost) {
        Write-Warning "No se encontro ninguna columna de costo reconocible en el detalle de $($Period.Month). Candidatas: $($script:ColumnCandidates.Cost -join ', ')"
    }

    # Las llaves son ResourceId en minusculas. Los tags se toman de la ultima fila no vacia:
    # el detalle repite tags por dia y a veces vienen vacios en filas de ajuste.
    $costByKey = [ordered]@{}
    $tagsByKey = @{}
    # Tags de sub-recursos sumados al padre: solo cuentan si el padre no trajo los suyos ni
    # esta en el inventario.
    $childTagsByKey = @{}
    $sampleByKey = @{}
    $sampleFromChild = [System.Collections.Generic.HashSet[string]]::new()
    # El mismo texto de tags se repite en miles de filas: parsearlo una vez.
    $tagsCache = [System.Collections.Generic.Dictionary[string, hashtable]]::new()
    $currency = ''

    foreach($row in $Rows) {
        if(!(TestDateInPeriod (ConvertToUsageDate (& $column $row 'Date')) $Period)) { continue }

        $idNorm = (& $column $row 'ResourceId').ToLowerInvariant()
        $parent = $idNorm ? (GetParentResourceId $idNorm) : $null
        $cost = ConvertToCostNumber (& $column $row 'Cost')

        if(!$idNorm) {
            # Cargos sin ResourceId (soporte, algunos Marketplace) se agrupan por servicio y
            # tipo de cargo para no perderlos del total.
            $key = "`0$(& $column $row 'Service')`0$(& $column $row 'Charge')"
        }
        else {
            $key = $parent ?? $idNorm
        }

        $costByKey[$key] = ($costByKey[$key] ?? 0.0) + $cost
        # La muestra da nombre y servicio cuando el recurso no esta en el inventario: la del
        # propio padre gana sobre la de un hijo.
        if(!$sampleByKey.ContainsKey($key) -or (!$parent -and $sampleFromChild.Contains($key))) {
            $sampleByKey[$key] = $row
            if($parent) { $null = $sampleFromChild.Add($key) } else { $null = $sampleFromChild.Remove($key) }
        }

        $tagsText = & $column $row 'Tags'
        if($tagsText) {
            if(!$tagsCache.TryGetValue($tagsText, [ref]$null)) {
                $tagsCache[$tagsText] = ConvertFromTagsText $tagsText
            }
            $tags = $tagsCache[$tagsText]
            if($tags.Count) {
                if($parent) { $childTagsByKey[$key] = $tags } else { $tagsByKey[$key] = $tags }
            }
        }
        if(!$currency) { $currency = & $column $row 'Currency' }
    }

    foreach($key in $costByKey.Keys) {
        $sample = $sampleByKey[$key]
        # Ordinal: con comparacion cultural .NET ignora el caracter nulo y todo "empieza" con el.
        $isCharge = $key.StartsWith("`0", [StringComparison]::Ordinal)
        $resource = $isCharge ? $null : $InventoryIndex[$key]

        # Si el recurso existe hoy, sus tags de hoy: son los que alguien va a corregir. Si ya
        # no existe, los del detalle (los que tenia cuando genero el cargo).
        $tags = $resource ? $resource.Tags : $tagsByKey[$key]
        if(!$resource -and !$tags.Count) { $tags = $childTagsByKey[$key] }
        if(!$tags) { $tags = @{} }

        if($resource) {
            $resourceId = $resource.ResourceId
            $name = $resource.Name
            $type = $resource.Type
            $resourceGroup = $resource.ResourceGroup
            $location = $resource.Location
        }
        elseif($isCharge) {
            $resourceId = $null
            $name = $null
            $type = $null
            $resourceGroup = $null
            $location = & $column $sample 'Location'
        }
        else {
            $sampleId = & $column $sample 'ResourceId'
            $resourceId = $sampleId -and $sampleId.ToLowerInvariant() -eq $key ? $sampleId : $key
            $name = $sampleFromChild.Contains($key) ? '' : (& $column $sample 'ResourceName')
            if(!$name) { $name = $key.Substring($key.LastIndexOf('/') + 1) }
            $type = & $column $sample 'ResourceType'
            $resourceGroup = & $column $sample 'ResourceGroup'
            if(!$resourceGroup) { $resourceGroup = GetResourceGroupFromId $key }
            $location = & $column $sample 'Location'
        }

        [PSCustomObject]@{
            PSTypeName        = 'KnowIT.AzureCosts.CostDetail'
            Month             = $Period.Month
            SubscriptionId    = $SubscriptionId
            ResourceId        = $resourceId
            ResourceName      = $name
            ResourceType      = $type
            ResourceGroup     = $resourceGroup
            Location          = $location
            ServiceName       = & $column $sample 'Service'
            ChargeType        = $isCharge ? (& $column $sample 'Charge') : $null
            Cost              = $costByKey[$key]
            Currency          = $currency
            ExistsInInventory = [bool]$resource
            Tags              = $tags
        }
    }
}
