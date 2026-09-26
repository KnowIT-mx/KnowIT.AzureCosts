function Export-KnowITAzCostsRaw {
    <#
    .SYNOPSIS
        Exporta a CSV el detalle diario por recurso tal como lo entrega la Cost Details API,
        con los tags expandidos en columnas.

    .DESCRIPTION
        Escribe un solo CSV con todas las columnas originales del detalle de costos (una fila
        por recurso, por dia y por medidor) de las suscripciones y meses indicados, mas una
        columna por tag. Sin -TagColumn se agregan todos los tags que aparecen en las filas
        exportadas; al recurso que no tiene un tag se le deja vacio.

        Por default los tags son los que tenia el recurso el dia del cargo. Con
        -TagsFromInventory se usan los de hoy para los recursos que siguen existiendo.

        Usa el mismo cache local que Get-KnowITAzCostsDetail. Devuelve el archivo generado.

    .PARAMETER Path
        Ruta del CSV a generar. Si existe, se reemplaza.

    .PARAMETER Month
        Uno o varios meses en formato yyyy-MM. Alias: -Period.

    .PARAMETER StartDate
        Inicio de un rango de fechas. Con -EndDate, alternativa a -Month.

    .PARAMETER EndDate
        Fin del rango de fechas, inclusive.

    .PARAMETER SubscriptionId
        Una o varias suscripciones. Acepta la salida de Get-AzSubscription por pipeline.

    .PARAMETER ResourceGroup
        Solo las filas de estos resource groups. Acepta comodines.

    .PARAMETER Untagged
        Solo las filas sin ningun tag. Excluyente con -ResourceGroup y -Tag.

    .PARAMETER Tag
        Solo las filas cuyos tags cumplen todos los pares indicados. Los valores aceptan
        comodines.

    .PARAMETER TagColumn
        Limita las columnas de tags a estos. Si un tag se llama igual que una columna del
        detalle, la columna se llama tag_<nombre>.

    .PARAMETER TagsFromInventory
        Usa los tags de hoy (inventario de Resource Graph) en vez de los del dia del cargo.
        Los recursos que ya no existen conservan los del cargo.

    .PARAMETER Metric
        ActualCost (default) o AmortizedCost.

    .PARAMETER Tenant
        Tenant para pedir el token. Sin el se usa el de la sesion de Az.

    .PARAMETER Force
        Vuelve a descargar el detalle (y el inventario) aunque esten en cache.

    .EXAMPLE
        Export-KnowITAzCostsRaw -Month 2026-08 -SubscriptionId $sub -Path ./costos-2026-08.csv

    .EXAMPLE
        Export-KnowITAzCostsRaw -StartDate 2026-07-15 -EndDate 2026-08-14 -SubscriptionId $sub -TagColumn Environment, Owner -Path ./costos.csv
    #>

    [CmdletBinding(DefaultParameterSetName = 'Month')]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrWhiteSpace()]
        [string]$Path,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Month')]
        [ValidatePattern('^\d{4}-(0[1-9]|1[0-2])$')]
        [Alias('Period')]
        [string[]]$Month,

        [Parameter(Mandatory, ParameterSetName = 'Range')]
        [datetime]$StartDate,

        [Parameter(Mandatory, ParameterSetName = 'Range')]
        [datetime]$EndDate,

        [Parameter(Mandatory, Position = 1, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
        [Alias('Id')]
        [string[]]$SubscriptionId,

        [SupportsWildcards()]
        [string[]]$ResourceGroup,

        [switch]$Untagged,

        [hashtable]$Tag,

        [string[]]$TagColumn,

        [switch]$TagsFromInventory,

        [ValidateSet('ActualCost', 'AmortizedCost')]
        [string]$Metric = 'ActualCost',

        [ValidateNotNullOrWhiteSpace()]
        [Alias('TenantId')]
        [string]$Tenant,

        [switch]$Force
    )

    begin {
        $subscriptions = [System.Collections.Generic.List[string]]::new()
    }
    process {
        foreach($id in $SubscriptionId) { $subscriptions.Add($id) }
    }
    end {
        try {
            Update-CallerPreference $PSCmdlet
            AssertFilterCombination $PSBoundParameters

            $periods = @(ResolvePeriod -Month $Month -StartDate ($PSBoundParameters.StartDate) -EndDate ($PSBoundParameters.EndDate))
            $unique = @($subscriptions | Sort-Object -Unique)
            $inventoryIndex = $TagsFromInventory ? (NewInventoryIndex @(GetInventory -SubscriptionId $unique -Tenant $Tenant -Force:$Force)) : @{}

            # Primera pasada: filtrar y resolver tags. Las columnas de tags dependen de todas
            # las filas elegidas, asi que no se puede escribir mientras se lee.
            $selected = [System.Collections.Generic.List[object]]::new()
            $headers = [System.Collections.Generic.List[string]]::new()
            $seenHeaders = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            $tagsCache = [System.Collections.Generic.Dictionary[string, hashtable]]::new()

            foreach($subscription in $unique) {
                foreach($period in $periods) {
                    $files = @(GetCostDetailFiles -SubscriptionId $subscription -Month $period.Month -Metric $Metric -Tenant $Tenant -Force:$Force)
                    if(!$files) { continue }

                    Write-Verbose "Leyendo detalle de $($period.Month) de $subscription..."
                    $data = ReadCostRows $files
                    foreach($header in $data.Headers) {
                        if($seenHeaders.Add($header)) { $headers.Add($header) }
                    }
                    $map = NewColumnMap $data.Headers

                    foreach($row in $data.Rows) {
                        if($map.Date -and !(TestDateInPeriod (ConvertToUsageDate $row.($map.Date)) $period)) { continue }

                        $resourceId = $map.ResourceId ? "$($row.($map.ResourceId))".Trim() : ''
                        $resource = $resourceId ? $inventoryIndex[$resourceId.ToLowerInvariant()] : $null
                        if($resource) {
                            $tags = $resource.Tags
                        }
                        else {
                            $tagsText = $map.Tags ? "$($row.($map.Tags))" : ''
                            if(!$tagsCache.TryGetValue($tagsText, [ref]$null)) {
                                $tagsCache[$tagsText] = ConvertFromTagsText $tagsText
                            }
                            $tags = $tagsCache[$tagsText]
                        }

                        # No llamarla $resourceGroup: es la misma variable que el parametro -ResourceGroup.
                        $rowResourceGroup = $map.ResourceGroup ? "$($row.($map.ResourceGroup))".Trim() : ''
                        if(!$rowResourceGroup -and $resourceId) { $rowResourceGroup = GetResourceGroupFromId $resourceId }

                        if(TestItemFilter -ResourceGroup $rowResourceGroup -Tags $tags -ResourceGroupFilter $ResourceGroup -Untagged:$Untagged -TagFilter $Tag) {
                            $selected.Add(@{ Row = $row; Tags = $tags })
                        }
                    }
                }
            }

            $tagNames = $TagColumn ? $TagColumn : (GetTagNames @($selected | ForEach-Object Tags))
            $reserved = [System.Collections.Generic.HashSet[string]]::new([string[]]$headers, [StringComparer]::OrdinalIgnoreCase)
            $tagColumns = @(foreach($name in $tagNames) {
                @{ Tag = $name; Column = $reserved.Contains($name) ? "tag_$name" : $name }
            })

            $target = [IO.Path]::GetFullPath($Path, (Get-Location).Path)
            $null = New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force
            Write-Verbose "Escribiendo $($selected.Count) filas y $($tagColumns.Count) columnas de tags en $target..."
            WriteRawCsv -Path $target -Headers $headers -TagColumns $tagColumns -Items $selected
            Get-Item $target
        }
        catch {
            $PSCmdlet.WriteError($_)
        }
    }
}
