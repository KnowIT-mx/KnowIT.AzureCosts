function New-TagTemplate {
    <#
        Genera un xlsx con los recursos a los que les falta algun tag requerido, para que
        alguien lo llene a mano y despues se aplique de regreso a Azure.

        No modifica nada en Azure. Los tags se leen del inventario de hoy (ARG), que es lo
        que se va a modificar, no del detalle de costos del mes.

        El formato es el contrato con el paso de regreso: la columna ResourceId identifica
        el recurso y las columnas de tags se leen por nombre de encabezado.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$CostDetailPath,

        [Parameter(Mandatory)]
        [object[]]$Inventory,

        [Parameter(Mandatory)]
        [string[]]$RequiredTags,

        [string]$SubscriptionId,

        [string]$Path = "etiquetas-pendientes-$(Get-Date -Format 'yyyy-MM-dd').xlsx"
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
            if(!$SubscriptionId) { $SubscriptionId = $origen.SubscriptionId }
            $RequiredTags = @($RequiredTags | ForEach-Object { $_.Trim() } | Where-Object { $_ })

            $datos = ReadCostRows $archivos
            $analisis = InvokeCostAnalysis -Month $origen.Month -Rows $datos.Filas -Headers $datos.Encabezados `
                -Inventory $Inventory -RequiredTags $RequiredTags

            $porId = @{}
            foreach($r in $Inventory) { $porId[$r.IdNorm] = $r }
            $completoHoy = { param($r) @($RequiredTags | Where-Object { !(TestTagValue $r.Tags $_) }).Count -eq 0 }

            # Con costo: solo los que siguen existiendo; un recurso borrado no se puede etiquetar.
            $vigentes = @($analisis.SinEtiquetarConCosto |
                Where-Object { $porId.ContainsKey($_.ResourceId) } |
                ForEach-Object { [PSCustomObject]@{ Recurso = $porId[$_.ResourceId]; Costo = $_.Costo } })
            # Sin tags en el mes pero ya etiquetados despues: no hay nada que llenar.
            $yaCorregidos = @($vigentes | Where-Object { & $completoHoy $_.Recurso }).Count
            $conCosto = @($vigentes | Where-Object { !(& $completoHoy $_.Recurso) })

            # Sub-recursos (extensiones de VM, versiones de template specs, bases de Arc...):
            # rara vez se etiquetan y no afectan el reporte de costos.
            $esSubrecurso = { param($tipo) ($tipo.ToCharArray() | Where-Object { $_ -eq '/' }).Count -ge 2 }
            $sinCosto = @($analisis.SinEtiquetarSinCosto |
                Where-Object { !(& $esSubrecurso $_.Type) } |
                ForEach-Object { [PSCustomObject]@{ Recurso = $_; Costo = $null } })
            $omitidos = @($analisis.SinEtiquetarSinCosto).Count - $sinCosto.Count

            $rutaXlsx = [IO.Path]::GetFullPath($Path, (Get-Location).Path)
            ExportTagTemplateWorkbook -Path $rutaXlsx -Inventory $Inventory -RequiredTags $RequiredTags `
                -WithCost $conCosto -WithoutCost $sinCosto -Omitted $omitidos -AlreadyFixed $yaCorregidos `
                -SubscriptionId $SubscriptionId -Currency $analisis.Moneda

            [PSCustomObject]@{
                PSTypeName         = 'KnowIT.AzureCosts.TagTemplate'
                Path               = $rutaXlsx
                SubscriptionId     = $SubscriptionId
                ConCosto           = $conCosto.Count
                SinCosto           = $sinCosto.Count
                SubrecursosOmitidos = $omitidos
                YaCorregidos       = $yaCorregidos
                TagsRequeridos     = $RequiredTags
            }
        }
        catch {
            $PSCmdlet.WriteError($_)
        }
    }
}
