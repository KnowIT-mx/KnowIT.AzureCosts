function MergeResourceCost
{
    # Suma el detalle diario de un mes en una fila por recurso (o por recurso y juego de tags
    # con -SplitByTagChange). Devuelve los objetos sin filtrar; los filtros se aplican despues
    # sobre los tags efectivos.
    param(
        [string]$SubscriptionId,
        $Period,
        [System.Collections.Generic.List[object]]$Rows,
        [string[]]$Headers,
        [hashtable]$InventoryIndex,
        [switch]$SplitByTagChange
    )

    $map = NewColumnMap $Headers
    $column = { param($row, $field) $name = $map[$field]; $name ? "$($row.$name)".Trim() : '' }

    if(!$map.Cost) {
        Write-Warning "No se encontro ninguna columna de costo reconocible en el detalle de $($Period.Month). Candidatas: $($script:ColumnCandidates.Cost -join ', ')"
    }

    # Las llaves son ResourceId en minusculas; los sub-recursos de Data Factory van a la llave
    # de su padre. Por llave se guarda la historia de tags con valor, por fecha: los propios
    # del recurso y, aparte, los de sus hijos, que solo cuentan si el padre no trae ninguno.
    # $ownDayTags guarda ademas los dias sin tags: con split, los hijos siguen los tags que su
    # padre tuvo ese dia, vacios o no.
    $costByKey = [ordered]@{}
    $ownHistory = @{}
    $childHistory = @{}
    $ownDayTags = @{}
    $sampleByKey = @{}
    $sampleFromChild = [System.Collections.Generic.HashSet[string]]::new()
    $records = [System.Collections.Generic.List[object]]::new()
    # El mismo texto de tags se repite en miles de filas: parsearlo una vez.
    $tagsCache = [System.Collections.Generic.Dictionary[string, hashtable]]::new()
    $currency = ''

    foreach($row in $Rows) {
        $date = ConvertToUsageDate (& $column $row 'Date')
        if(!(TestDateInPeriod $date $Period)) { continue }

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
        if(!$tagsCache.TryGetValue($tagsText, [ref]$null)) {
            $tagsCache[$tagsText] = ConvertFromTagsText $tagsText
        }
        $tags = $tagsCache[$tagsText]
        if(!(TestUntagged $tags)) {
            AddTagHistory ($parent ? $childHistory : $ownHistory) $key $date $tags
        }
        if($SplitByTagChange) {
            if(!$parent) { AddTagHistory $ownDayTags $key $date $tags }
            $records.Add(@{ Key = $key; Date = $date; Cost = $cost; Tags = $tags; IsChild = [bool]$parent })
        }
        if(!$currency) { $currency = & $column $row 'Currency' }
    }

    if(!$SplitByTagChange) {
        foreach($key in $costByKey.Keys) {
            $resource = GetInventoryResource $InventoryIndex $key
            # Si el recurso existe, sus tags de hoy, aunque no tenga ninguno: son los que alguien
            # va a corregir. Si ya no existe, los ultimos con valor que tuvo en el periodo (por
            # fecha, no por orden de fila: la API no entrega las filas ordenadas).
            $tags = $resource ? $resource.Tags :
                ((GetLatestTags $ownHistory[$key]) ?? (GetLatestTags $childHistory[$key]) ?? @{})
            NewCostDetailItem -Key $key -Sample $sampleByKey[$key] -Resource $resource -Cost $costByKey[$key] -Tags $tags `
                -Map $map -Month $Period.Month -SubscriptionId $SubscriptionId -Currency $currency -FromChild $sampleFromChild.Contains($key)
        }
        return
    }

    # Con split, cada fila lleva los tags que trae ese dia, tal cual: una fila sin tags es un
    # juego mas y genera su propio segmento. Los hijos de Data Factory siguen los tags que su
    # padre tuvo ese dia; solo si el padre no tiene filas ese dia se usan los del hijo.
    $segments = [ordered]@{}
    foreach($record in $records) {
        $key = $record.Key
        $tags = $record.Tags
        if($record.IsChild) {
            $parentTags = $null
            if($ownDayTags[$key]?.TryGetValue(($record.Date ?? [datetime]::MinValue), [ref]$parentTags)) { $tags = $parentTags }
        }
        $segmentKey = "$key`0$(GetTagSetKey $tags)"
        $segment = $segments[$segmentKey]
        if(!$segment) {
            $segment = @{ Key = $key; Tags = $tags; Cost = 0.0; FirstDate = $record.Date; LastDate = $record.Date }
            $segments[$segmentKey] = $segment
        }
        $segment.Cost += $record.Cost
        if($record.Date -and (!$segment.FirstDate -or $record.Date -lt $segment.FirstDate)) { $segment.FirstDate = $record.Date }
        if($record.Date -and (!$segment.LastDate -or $record.Date -gt $segment.LastDate)) { $segment.LastDate = $record.Date }
    }
    foreach($segment in $segments.Values) {
        $resource = GetInventoryResource $InventoryIndex $segment.Key
        $item = NewCostDetailItem -Key $segment.Key -Sample $sampleByKey[$segment.Key] -Resource $resource -Cost $segment.Cost -Tags $segment.Tags `
            -Map $map -Month $Period.Month -SubscriptionId $SubscriptionId -Currency $currency -FromChild $sampleFromChild.Contains($segment.Key)
        $item | Add-Member -NotePropertyName FirstDate -NotePropertyValue $segment.FirstDate
        $item | Add-Member -NotePropertyName LastDate -NotePropertyValue $segment.LastDate
        $item
    }
}

function GetInventoryResource ([hashtable]$InventoryIndex, [string]$Key)
{
    # Ordinal: con comparacion cultural .NET ignora el caracter nulo y todo "empieza" con el.
    if($Key.StartsWith("`0", [StringComparison]::Ordinal)) { return $null }
    $InventoryIndex[$Key]
}

function AddTagHistory ([hashtable]$History, [string]$Key, $Date, [hashtable]$Tags)
{
    # Un juego de tags por dia; si un dia trae dos distintos gana el ultimo leido (con valor,
    # si alguno lo tiene: una fila de ajuste vacia no borra los tags del dia).
    if(!$History.ContainsKey($Key)) {
        $History[$Key] = [System.Collections.Generic.SortedDictionary[datetime, hashtable]]::new()
    }
    $day = $Date ?? [datetime]::MinValue
    $previous = $null
    if($History[$Key].TryGetValue($day, [ref]$previous) -and (TestUntagged $Tags) -and !(TestUntagged $previous)) { return }
    $History[$Key][$day] = $Tags
}

function GetLatestTags ($History)
{
    if(!$History -or !$History.Count) { return $null }
    $latest = $null
    foreach($entry in $History.GetEnumerator()) { $latest = $entry.Value }
    $latest
}

function GetTagSetKey ([hashtable]$Tags)
{
    # Identifica un juego de tags sin importar el orden de las llaves ni sus mayusculas.
    $parts = foreach($name in (SortOrdinal @($Tags.Keys | ForEach-Object { $_.ToLowerInvariant() }))) {
        "$name=$($Tags[$name])"
    }
    $parts -join "`0"
}

function NewCostDetailItem
{
    param(
        [string]$Key,
        $Sample,
        $Resource,
        [double]$Cost,
        [hashtable]$Tags,
        [hashtable]$Map,
        [string]$Month,
        [string]$SubscriptionId,
        [string]$Currency,
        # La muestra salio de un sub-recurso: su nombre es el del hijo, no el del recurso.
        [bool]$FromChild
    )

    $isCharge = $Key.StartsWith("`0", [StringComparison]::Ordinal)
    $column = { param($row, $field) $name = $Map[$field]; $name ? "$($row.$name)".Trim() : '' }

    if($Resource) {
        $resourceId = $Resource.ResourceId
        $name = $Resource.Name
        $type = $Resource.Type
        $resourceGroup = $Resource.ResourceGroup
        $location = $Resource.Location
    }
    elseif($isCharge) {
        $resourceId = $null
        $name = $null
        $type = $null
        $resourceGroup = $null
        $location = & $column $Sample 'Location'
    }
    else {
        $sampleId = & $column $Sample 'ResourceId'
        $resourceId = $sampleId -and $sampleId.ToLowerInvariant() -eq $Key ? $sampleId : $Key
        $name = $FromChild ? '' : (& $column $Sample 'ResourceName')
        if(!$name) { $name = $Key.Substring($Key.LastIndexOf('/') + 1) }
        $type = & $column $Sample 'ResourceType'
        $resourceGroup = & $column $Sample 'ResourceGroup'
        if(!$resourceGroup) { $resourceGroup = GetResourceGroupFromId $Key }
        $location = & $column $Sample 'Location'
    }

    [PSCustomObject]@{
        PSTypeName        = 'KnowIT.AzureCosts.CostDetail'
        Month             = $Month
        SubscriptionId    = $SubscriptionId
        ResourceId        = $resourceId
        ResourceName      = $name
        ResourceType      = $type
        ResourceGroup     = $resourceGroup
        Location          = $location
        ServiceName       = & $column $Sample 'Service'
        ChargeType        = $isCharge ? (& $column $Sample 'Charge') : $null
        Cost              = $Cost
        Currency          = $Currency
        ExistsInInventory = [bool]$Resource
        Tags              = $Tags
    }
}
