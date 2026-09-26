function Get-CostDetail {
    <#
        Genera y descarga el detalle de costos de un mes con la Cost Details API.
        No crea recursos en Azure: Microsoft genera el CSV en su storage y devuelve
        URLs con SAS temporal.

        Devuelve los CSV descargados (FileInfo). Guardarlos es deliberado: la API esta
        limitada (Microsoft pide ~1 consulta al dia) y con los CSV se puede regenerar el
        reporte o la plantilla de tags las veces que haga falta sin volver a consultar.

        Limites de la API: un mes por reporte, maximo 13 meses de antiguedad, solo
        ActualCost/AmortizedCost (nunca FOCUS), y solo scope de suscripcion.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrWhiteSpace()]
        [string]$SubscriptionId,

        # Periodo yyyy-MM. Default: mes anterior.
        [ValidatePattern('^\d{4}-\d{2}$')]
        [string]$Month = (Get-Date).AddMonths(-1).ToString('yyyy-MM'),

        [ValidateSet('ActualCost', 'AmortizedCost')]
        [string]$Metric = 'ActualCost',

        # Carpeta donde se guardan los CSV.
        [string]$Path = '.',

        [ValidateNotNullOrWhiteSpace()]
        [Alias('TenantId')]
        [string]$Tenant,

        # Tope de espera para que Azure termine de generar el reporte.
        [int]$TimeoutMinutes = 30
    )

    try {
        Update-CallerPreference $PSCmdlet

        $inicio = [datetime]::ParseExact("$Month-01", 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
        $fin = $inicio.AddMonths(1).AddDays(-1)
        $apiParams = @{ DetailResponse = $true }
        if($Tenant) { $apiParams.Tenant = $Tenant }

        Write-Verbose "Solicitando detalle de $Month ($($inicio.ToString('yyyy-MM-dd')) a $($fin.ToString('yyyy-MM-dd'))), metrica $Metric..."
        $respuesta = Invoke-AzManagement @apiParams -Method POST `
            -Path "subscriptions/$SubscriptionId/providers/Microsoft.CostManagement/generateCostDetailsReport?api-version=2024-08-01" `
            -Body @{
                metric     = $Metric
                timePeriod = @{ start = $inicio.ToString('yyyy-MM-dd'); end = $fin.ToString('yyyy-MM-dd') }
            }
        if(!$respuesta.Success) { throw (FormatArmError $respuesta) }

        # 200 inmediato es posible con datasets chicos; 202 + Location es el camino normal.
        if($respuesta.StatusCode -eq 202) {
            $ubicacion = "$($respuesta.Headers.Location)"
            if(!$ubicacion) { throw 'Azure devolvio 202 sin encabezado Location.' }
            $reintento = "$($respuesta.Headers.'Retry-After')"
            $espera = $reintento ? [int]$reintento : 20
            $limite = (Get-Date).AddMinutes($TimeoutMinutes)
            $intento = 0

            do {
                if((Get-Date) -gt $limite) {
                    throw "El reporte no termino de generarse en $TimeoutMinutes minutos."
                }
                $espera = [math]::Clamp($espera, 5, 60)
                $intento++
                Write-Verbose "  generando... (intento $intento, siguiente consulta en ${espera}s)"
                Start-Sleep -Seconds $espera

                $respuesta = Invoke-AzManagement @apiParams -Path $ubicacion
                if(!$respuesta.Success) { throw (FormatArmError $respuesta) }
                if($respuesta.Headers.'Retry-After') {
                    $espera = [int]"$($respuesta.Headers.'Retry-After')"
                }
            } while($respuesta.StatusCode -ne 200)
        }

        $reporte = $respuesta.Value
        switch ($reporte.status) {
            'NoDataFound' {
                throw ("Azure reporta que no hay datos de costo para $Month. Si el mes es reciente, " +
                    'los datos tardan unos dias en consolidarse; si es viejo, recuerda el limite de 13 meses.')
            }
            { $_ -and $_ -ne 'Completed' } {
                throw "La generacion del reporte termino en estado '$_'."
            }
        }

        $blobs = @($reporte.manifest.blobs)
        if(!$blobs) {
            throw "El manifiesto no trae blobs: $(ConvertTo-Json $reporte -Depth 4 -Compress)"
        }
        Write-Verbose ("Manifiesto listo: {0} archivo(s), {1:N0} KB, valido hasta {2}" -f
            $blobs.Count, ($reporte.manifest.byteCount / 1KB), $reporte.validTill)

        $carpeta = New-Item -ItemType Directory -Path $Path -Force
        for($i = 0; $i -lt $blobs.Count; $i++) {
            $destino = Join-Path $carpeta "detalle-$SubscriptionId-$Month-part$i.csv"
            Write-Verbose "  descargando parte $($i + 1)/$($blobs.Count)..."
            # blobLink ya trae SAS: se descarga sin encabezado de autorizacion.
            Invoke-WebRequest -Uri $blobs[$i].blobLink -OutFile $destino -Verbose:$false
            Get-Item $destino
        }
    }
    catch {
        $PSCmdlet.WriteError($_)
    }
}
