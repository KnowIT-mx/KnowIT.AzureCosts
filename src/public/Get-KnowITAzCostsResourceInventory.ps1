function Get-KnowITAzCostsResourceInventory {
    <#
    .SYNOPSIS
        Inventario de recursos de Azure con sus tags, desde Azure Resource Graph.

    .DESCRIPTION
        Devuelve un objeto por recurso ARM de las suscripciones indicadas, con sus tags de hoy.
        Complementa al detalle de costos: un NSG o un disco desasociado no generan cargo y no
        aparecen en el detalle, pero si en el inventario.

        El inventario se guarda en un cache local por dia; las siguientes llamadas del mismo
        dia no vuelven a consultar Azure salvo con -Force.

    .PARAMETER SubscriptionId
        Suscripciones a inventariar. Sin este parametro se usan todas las suscripciones
        habilitadas a las que tiene acceso la sesion, incluidas las delegadas por Lighthouse.

    .PARAMETER ResourceGroup
        Solo los recursos de estos resource groups. Acepta comodines. Excluyente con -Untagged.

    .PARAMETER Untagged
        Solo los recursos sin ningun tag (un tag con valor vacio no cuenta).

    .PARAMETER Tenant
        Tenant para pedir el token. Sin el se usa el de la sesion de Az.

    .PARAMETER TagsAsJson
        Entrega la propiedad Tags como texto JSON compacto en vez de hashtable, lista para
        Export-Csv: {"Environment":"Production","Owner":"Equipo-FinOps"}. Sin tags queda {}.

    .PARAMETER Force
        Vuelve a consultar Resource Graph aunque el inventario de hoy ya este en cache.

    .EXAMPLE
        Get-KnowITAzCostsResourceInventory -SubscriptionId $sub -Untagged

    .EXAMPLE
        Get-AzSubscription | Get-KnowITAzCostsResourceInventory -TagsAsJson | Export-Csv inventario.csv
    #>

    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType('KnowIT.AzureCosts.Resource')]
    param(
        [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
        [Alias('Id')]
        [string[]]$SubscriptionId,

        [Parameter(Mandatory, ParameterSetName = 'ResourceGroup')]
        [SupportsWildcards()]
        [string[]]$ResourceGroup,

        [Parameter(Mandatory, ParameterSetName = 'Untagged')]
        [switch]$Untagged,

        [ValidateNotNullOrWhiteSpace()]
        [Alias('TenantId')]
        [string]$Tenant,

        [switch]$TagsAsJson,

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

            if(!$subscriptions.Count) {
                Write-Verbose 'Sin -SubscriptionId: se usan todas las suscripciones accesibles.'
                foreach($id in (GetAccessibleSubscriptions $Tenant)) { $subscriptions.Add($id) }
            }
            $unique = @($subscriptions | Sort-Object -Unique)

            $inventory = @(GetInventory -SubscriptionId $unique -Tenant $Tenant -Force:$Force |
                Where-Object { TestItemFilter -ResourceGroup $_.ResourceGroup -Tags $_.Tags -ResourceGroupFilter $ResourceGroup -Untagged:$Untagged })
            if($TagsAsJson) { ConvertTagsToJson $inventory }
            SortOrdinal $inventory { "$($_.SubscriptionId)`0$($_.ResourceGroup)`0$($_.Name)".ToLowerInvariant() }
        }
        catch {
            $PSCmdlet.WriteError($_)
        }
    }
}
