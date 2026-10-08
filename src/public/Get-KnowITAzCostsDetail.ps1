function Get-KnowITAzCostsDetail {
    <#
    .SYNOPSIS
        Costo por recurso y por mes de una o varias suscripciones de Azure.

    .DESCRIPTION
        Devuelve un objeto por recurso por mes con el costo acumulado del periodo, sus tags y
        los datos del recurso. Los cargos que no pertenecen a un recurso (Marketplace,
        soporte, reservas) salen como filas sin ResourceId.

        Trabaja sobre un cache local: la primera vez que se pide un mes de una suscripcion se
        descarga el detalle completo con la Cost Details API y los filtros se aplican
        despues, sin volver a consultar Azure. Microsoft pide no consultar esa API mas de una
        vez al dia por suscripcion. Los meses cerrados quedan en cache de forma permanente;
        el mes en curso se renueva cada 24 horas.

        Tags: si el recurso existe hoy se usan sus tags de hoy, aunque no tenga ninguno: son los
        que alguien va a corregir. Si ya no existe, los ultimos con valor que tuvo en el
        periodo. Los pipelines y triggers de Data Factory se suman a su factory.

    .PARAMETER Month
        Uno o varios meses en formato yyyy-MM. Alias: -Period.

    .PARAMETER StartDate
        Inicio de un rango de fechas. Con -EndDate, alternativa a -Month; los meses que el
        rango cubre a medias solo suman los dias dentro del rango.

    .PARAMETER EndDate
        Fin del rango de fechas, inclusive.

    .PARAMETER SubscriptionId
        Una o varias suscripciones. Acepta la salida de Get-AzSubscription por pipeline.

    .PARAMETER ResourceGroup
        Solo los recursos de estos resource groups. Acepta comodines.

    .PARAMETER Untagged
        Solo los recursos sin ningun tag. Excluyente con -ResourceGroup y -Tag.

    .PARAMETER Tag
        Solo los recursos cuyos tags cumplen todos los pares indicados. Los valores aceptan
        comodines: @{ Environment = 'Prod*'; Role = 'Web' }.

    .PARAMETER TagColumn
        Tags que ademas de ir en la propiedad Tags se agregan como propiedades propias, listas
        para Export-Csv. Si un tag se llama igual que una propiedad existente, la columna se
        llama tag_<nombre>.

    .PARAMETER Metric
        ActualCost (default) o AmortizedCost.

    .PARAMETER Tenant
        Tenant para pedir el token. Sin el se usa el de la sesion de Az.

    .PARAMETER SplitByTagChange
        Si un recurso cambio de tags dentro del mes, devuelve una fila por cada juego de tags
        que tuvo, con el costo de esos dias y las propiedades FirstDate y LastDate. Usa los tags
        historicos del detalle aunque el recurso exista hoy; los dias sin tags forman su propia
        fila. Los pipelines y triggers de Data Factory siguen los tags que su factory tuvo ese dia.

    .PARAMETER TagsAsJson
        Entrega la propiedad Tags como texto JSON compacto en vez de hashtable, lista para
        Export-Csv: {"Environment":"Production","Owner":"Equipo-FinOps"}. Sin tags queda {}.

    .PARAMETER Force
        Vuelve a descargar el detalle y el inventario aunque esten en cache.

    .EXAMPLE
        Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -Untagged

    .EXAMPLE
        Get-KnowITAzCostsDetail -Period 2026-07, 2026-08 -SubscriptionId $sub -Tag @{ Environment = 'Production' } -TagColumn Role, Owner -TagsAsJson |
            Export-Csv costos.csv
    #>

    [CmdletBinding(DefaultParameterSetName = 'Month')]
    [OutputType('KnowIT.AzureCosts.CostDetail')]
    param(
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

        [switch]$TagsAsJson,

        [switch]$SplitByTagChange,

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
            $inventory = @(GetInventory -SubscriptionId $unique -Tenant $Tenant -Force:$Force)
            $inventoryIndex = NewInventoryIndex $inventory

            $results = [System.Collections.Generic.List[object]]::new()
            foreach($subscription in $unique) {
                foreach($period in $periods) {
                    $files = @(GetCostDetailFiles -SubscriptionId $subscription -Month $period.Month -Metric $Metric -Tenant $Tenant -Force:$Force)
                    if(!$files) { continue }

                    Write-Verbose "Leyendo detalle de $($period.Month) de $subscription..."
                    $data = ReadCostRows $files
                    $items = MergeResourceCost -SubscriptionId $subscription -Period $period -Rows $data.Rows -Headers $data.Headers -InventoryIndex $inventoryIndex -SplitByTagChange:$SplitByTagChange
                    foreach($item in $items) {
                        if(TestItemFilter -ResourceGroup $item.ResourceGroup -Tags $item.Tags -ResourceGroupFilter $ResourceGroup -Untagged:$Untagged -TagFilter $Tag) {
                            $results.Add($item)
                        }
                    }
                }
            }

            if($TagColumn -and $results.Count) {
                AddTagColumns $results $TagColumn $results[0].PSObject.Properties.Name
            }
            if($TagsAsJson) { ConvertTagsToJson $results }
            # Por suscripcion y mes, el recurso mas caro primero.
            $results | Sort-Object SubscriptionId, Month, @{ Expression = 'Cost'; Descending = $true } -Stable
        }
        catch {
            $PSCmdlet.WriteError($_)
        }
    }
}
