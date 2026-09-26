function New-CostReport {
    <#
        Genera el xlsx de costos y etiquetado a partir del detalle de costos (CSV de
        Get-CostDetail) y del inventario de Resource Graph (Get-ResourceInventory).

        No llama a la Cost Details API: trabaja sobre CSV ya descargados, asi que se puede
        regenerar con otros tags las veces que haga falta sin gastar la consulta del dia.

        Devuelve el resumen y el diagnostico del reporte, con la ruta del xlsx generado.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$CostDetailPath,

        # Inventario de Get-ResourceInventory. Sin el se pierde el cruce, el inventario sin
        # costo y los nombres/tags actuales de ARG, pero los costos salen igual.
        [object[]]$Inventory = @(),

        # Tags que un recurso debe tener (con valor) para contar como etiquetado.
        [Parameter(Mandatory)]
        [string[]]$RequiredTags,

        # Solo para titulos y el nombre del archivo. Por default se toma del nombre del CSV
        # que genera Get-CostDetail (detalle-<suscripcion>-<yyyy-MM>-partN.csv).
        [string]$Month,

        [string]$SubscriptionId,

        [string]$Path
    )

    begin {
        $archivos = [System.Collections.Generic.List[string]]::new()
    }
    process {
        foreach($p in $CostDetailPath) { $archivos.Add((Convert-Path $p)) }
    }
    end {
        try {
            Update-CallerPreference $PSCmdlet

            $origen = GetCostDetailOrigin $archivos[0]
            if(!$Month) { $Month = $origen.Month }
            if(!$SubscriptionId) { $SubscriptionId = $origen.SubscriptionId }
            if(!$Path) { $Path = "reporte-costos-$($Month ? $Month : 'sin-mes').xlsx" }
            $RequiredTags = @($RequiredTags | ForEach-Object { $_.Trim() } | Where-Object { $_ })

            Write-Verbose "Leyendo $($archivos.Count) archivo(s) de detalle de costos..."
            $datos = ReadCostRows $archivos
            Write-Verbose "$($datos.Filas.Count) filas leidas, $($datos.Encabezados.Count) columnas"
            if(!$datos.Filas.Count) {
                throw 'El detalle de costos vino vacio. Nada que reportar.'
            }

            Write-Verbose 'Analizando y cruzando con el inventario...'
            $analisis = InvokeCostAnalysis -Month $Month -Rows $datos.Filas -Headers $datos.Encabezados `
                -Inventory $Inventory -RequiredTags $RequiredTags

            $rutaXlsx = [IO.Path]::GetFullPath($Path, (Get-Location).Path)
            Write-Verbose "Generando $rutaXlsx..."
            ExportCostReportWorkbook $analisis $rutaXlsx $SubscriptionId

            $r = $analisis.Resumen
            $d = $analisis.Diagnostico
            [PSCustomObject]@{
                PSTypeName                     = 'KnowIT.AzureCosts.Report'
                Path                           = $rutaXlsx
                SubscriptionId                 = $SubscriptionId
                Mes                            = $Month
                Moneda                         = $r.Moneda
                CostoTotal                     = [math]::Round($r.CostoTotal, 2)
                CostoSinEtiquetar              = [math]::Round($r.CostoSinEtiquetar, 2)
                PctSinEtiquetar                = [math]::Round($r.PctSinEtiquetar, 4)
                RecursosConCargo               = $d.RecursosConCargo
                RecursosSinEtiquetar           = $r.RecursosSinEtiquetar
                InventarioSinEtiquetarSinCosto = $r.InventarioSinEtiquetarSinCosto
                CargosSinRecursoArm            = $r.CargosSinRecursoArm
                CruzadosConResourceGraph       = $d.CruzadosOk
                TagsRequeridos                 = $RequiredTags
                Diagnostico                    = $d
            }
        }
        catch {
            $PSCmdlet.WriteError($_)
        }
    }
}
