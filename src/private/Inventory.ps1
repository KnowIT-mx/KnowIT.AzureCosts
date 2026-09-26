function GetInventory
{
    # Inventario de Resource Graph de las suscripciones pedidas, desde el cache del dia. Las
    # que no estan en cache se consultan juntas en una sola llamada (con paginacion) y se
    # guardan por separado.
    param(
        [string[]]$SubscriptionId,
        [string]$Tenant,
        [switch]$Force
    )

    $today = [datetime]::Now.ToString('yyyy-MM-dd')
    $missing = [System.Collections.Generic.List[string]]::new()
    foreach($id in $SubscriptionId) {
        $path = Join-Path (GetCacheFolder $id) "inventory-$today.json"
        if($Force -or !(Test-Path $path)) { $missing.Add($id) }
    }

    if($missing.Count) {
        $bySubscription = @{}
        foreach($id in $missing) { $bySubscription[$id.ToLowerInvariant()] = [System.Collections.Generic.List[object]]::new() }

        foreach($item in (QueryResourceGraph -SubscriptionId $missing -Tenant $Tenant)) {
            $bySubscription["$($item.subscriptionId)".ToLowerInvariant()]?.Add($item)
        }
        foreach($id in $missing) {
            $folder = GetCacheFolder $id
            $items = $bySubscription[$id.ToLowerInvariant()]
            # Una suscripcion sin recursos tambien se guarda: el arreglo vacio es la respuesta.
            WriteCacheFile (Join-Path $folder "inventory-$today.json") (ConvertTo-Json -InputObject @($items) -Depth 6)
            # Solo sirve el inventario de hoy; los de dias anteriores se descartan.
            Get-ChildItem $folder -Filter 'inventory-*.json' |
                Where-Object Name -ne "inventory-$today.json" |
                Remove-Item -Force
            Write-Verbose "Inventario de $id guardado en cache: $($items.Count) recursos"
        }
    }

    foreach($id in $SubscriptionId) {
        $path = Join-Path (GetCacheFolder $id) "inventory-$today.json"
        if(!$missing.Contains($id)) { Write-Verbose "Inventario de $id desde cache ($today)" }
        foreach($item in (Get-Content $path -Raw | ConvertFrom-Json -NoEnumerate)) {
            NewResourceItem $item
        }
    }
}

function QueryResourceGraph
{
    param(
        [string[]]$SubscriptionId,
        [string]$Tenant
    )

    $apiParams = @{}
    if($Tenant) { $apiParams.Tenant = $Tenant }
    $skipToken = $null
    $total = 0

    do {
        $options = @{ resultFormat = 'objectArray'; '$top' = 1000 }
        if($skipToken) { $options.'$skipToken' = $skipToken }

        $response = InvokeAzManagement @apiParams -Method POST `
            -Path 'providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' `
            -Body @{
                subscriptions = @($SubscriptionId)
                query         = 'resources | project id, name, type, resourceGroup, location, subscriptionId, tags'
                options       = $options
            }

        # ARG usa .data y no .value, asi que llega el cuerpo completo.
        foreach($item in $response.data) { $item }
        $total += @($response.data).Count
        $skipToken = $response.'$skipToken'
        Write-Verbose "  Resource Graph: $total recursos acumulados"
    } while($skipToken)
}

function GetAccessibleSubscriptions ([string]$Tenant)
{
    # Incluye las suscripciones delegadas por Lighthouse: ARM las lista igual que las propias.
    $apiParams = @{ DetailResponse = $true }
    if($Tenant) { $apiParams.Tenant = $Tenant }
    $path = 'subscriptions?api-version=2022-12-01'
    while($path) {
        $response = InvokeAzManagement @apiParams -Path $path
        if(!$response.Success) { throw (FormatArmError $response) }
        foreach($subscription in @($response.Content.value)) {
            if($subscription.state -eq 'Enabled') { $subscription.subscriptionId }
        }
        $path = $response.Content.nextLink
    }
}
