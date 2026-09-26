function GetCostDetailFiles
{
    # Devuelve los CSV del mes desde el cache y los descarga si faltan o ya caducaron. Un mes
    # sin datos devuelve una lista vacia (tambien queda en cache para no volver a preguntar).
    param(
        [string]$SubscriptionId,
        [string]$Month,
        [string]$Metric,
        [string]$Tenant,
        [switch]$Force
    )

    $manifest = ReadCostManifest $SubscriptionId $Metric $Month
    if($Force -or !(TestCostCacheFresh $manifest $Month)) {
        $manifest = SaveCostDetailReport -SubscriptionId $SubscriptionId -Month $Month -Metric $Metric -Tenant $Tenant
    }
    else {
        Write-Verbose "Detalle de $Month ($Metric) de $SubscriptionId desde cache, descargado $($manifest.downloadedAt)"
    }

    if($manifest.status -eq 'NoDataFound') {
        Write-Warning "Azure no tiene datos de costo de $Month para la suscripcion $SubscriptionId."
        return
    }
    $folder = GetCacheFolder $SubscriptionId
    foreach($name in $manifest.files) { Join-Path $folder $name }
}

function SaveCostDetailReport
{
    # Genera el detalle de un mes con la Cost Details API y lo guarda en cache. No crea
    # recursos en Azure: Microsoft genera el CSV en su storage y devuelve URLs con SAS.
    # Limites: un mes por reporte, maximo 13 meses de antiguedad, solo ActualCost o
    # AmortizedCost (nunca FOCUS) y solo scope de suscripcion.
    param(
        [string]$SubscriptionId,
        [string]$Month,
        [string]$Metric,
        [string]$Tenant,
        [int]$TimeoutMinutes = 30
    )

    $first = [datetime]::ParseExact("$Month-01", 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
    $last = $first.AddMonths(1).AddDays(-1)
    # El mes en curso solo se puede pedir hasta hoy.
    $today = [datetime]::UtcNow.Date
    if($last -gt $today) { $last = $today }
    $apiParams = @{ DetailResponse = $true }
    if($Tenant) { $apiParams.Tenant = $Tenant }

    Write-Verbose "Solicitando detalle de $Month ($($first.ToString('yyyy-MM-dd')) a $($last.ToString('yyyy-MM-dd'))), metrica $Metric, suscripcion $SubscriptionId..."
    $response = InvokeAzManagement @apiParams -Method POST `
        -Path "subscriptions/$SubscriptionId/providers/Microsoft.CostManagement/generateCostDetailsReport?api-version=2024-08-01" `
        -Body @{
            metric     = $Metric
            timePeriod = @{ start = $first.ToString('yyyy-MM-dd'); end = $last.ToString('yyyy-MM-dd') }
        }
    if(!$response.Success) { throw (FormatArmError $response) }

    # 200 inmediato es posible con datasets chicos; 202 + Location es el camino normal.
    if($response.StatusCode -eq 202) {
        $location = "$($response.Headers.Location)"
        if(!$location) { throw 'Azure devolvio 202 sin encabezado Location.' }
        $retryAfter = "$($response.Headers.'Retry-After')"
        $wait = $retryAfter ? [int]$retryAfter : 20
        $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
        $attempt = 0

        do {
            if((Get-Date) -gt $deadline) {
                throw "El reporte no termino de generarse en $TimeoutMinutes minutos."
            }
            $wait = [math]::Clamp($wait, 5, 60)
            $attempt++
            Write-Verbose "  generando... (intento $attempt, siguiente consulta en ${wait}s)"
            Start-Sleep -Seconds $wait

            $response = InvokeAzManagement @apiParams -Path $location
            if(!$response.Success) { throw (FormatArmError $response) }
            if($response.Headers.'Retry-After') {
                $wait = [int]"$($response.Headers.'Retry-After')"
            }
        } while($response.StatusCode -ne 200)
    }

    $report = $response.Value
    $folder = GetCacheFolder $SubscriptionId
    $baseName = GetCostCacheBaseName $Metric $Month
    $manifest = [ordered]@{
        subscriptionId = $SubscriptionId
        month          = $Month
        metric         = $Metric
        status         = 'Completed'
        downloadedAt   = [datetime]::UtcNow.ToString('o')
        files          = @()
    }

    switch ($report.status) {
        'NoDataFound' {
            $manifest.status = 'NoDataFound'
        }
        { $_ -and $_ -ne 'Completed' } {
            throw "La generacion del reporte termino en estado '$_'."
        }
        default {
            $blobs = @($report.manifest.blobs)
            if(!$blobs) {
                throw "El manifiesto no trae blobs: $(ConvertTo-Json $report -Depth 4 -Compress)"
            }
            Write-Verbose ("Manifiesto listo: {0} archivo(s), {1:N0} KB" -f $blobs.Count, ($report.manifest.byteCount / 1KB))

            # Los parts viejos se borran antes: un mes que antes traia 3 parts y ahora 2 no
            # debe arrastrar el tercero.
            $null = New-Item -ItemType Directory -Path $folder -Force
            Get-ChildItem $folder -Filter "$baseName-part*.csv" | Remove-Item -Force
            for($i = 0; $i -lt $blobs.Count; $i++) {
                $name = "$baseName-part$i.csv"
                $target = Join-Path $folder $name
                Write-Verbose "  descargando parte $($i + 1)/$($blobs.Count)..."
                # blobLink ya trae SAS: se descarga sin encabezado de autorizacion.
                Invoke-WebRequest -Uri $blobs[$i].blobLink -OutFile "$target.tmp" -Verbose:$false
                Move-Item "$target.tmp" $target -Force
                $manifest.files += $name
            }
        }
    }

    WriteCacheFile (Join-Path $folder "$baseName.json") (ConvertTo-Json $manifest)
    [PSCustomObject]$manifest
}
