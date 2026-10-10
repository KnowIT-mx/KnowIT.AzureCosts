function Clear-KnowITAzCostsCache {
    <#
    .SYNOPSIS
        Borra el cache local de detalle de costos e inventario.

    .DESCRIPTION
        El cache está en ~/.knowit/KnowIT.AzureCosts, una carpeta por suscripcion. Sin
        parametros borra todo el cache. Borrar el detalle de un mes obliga a volver a
        consultar la Cost Details API, que Microsoft pide no usar mas de una vez al dia por
        suscripcion.

    .PARAMETER SubscriptionId
        Solo el cache de estas suscripciones.

    .PARAMETER Month
        Solo el detalle de costos de estos meses (yyyy-MM), de todas las metricas. El
        inventario no se toca. Alias: -Period.

    .EXAMPLE
        Clear-KnowITAzCostsCache -SubscriptionId $sub -Month 2026-09

    .EXAMPLE
        Clear-KnowITAzCostsCache -WhatIf
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
        [Alias('Id')]
        [string[]]$SubscriptionId,

        [ValidatePattern('^\d{4}-(0[1-9]|1[0-2])$')]
        [Alias('Period')]
        [string[]]$Month
    )

    begin {
        $subscriptions = [System.Collections.Generic.List[string]]::new()
    }
    process {
        foreach($id in $SubscriptionId) { $subscriptions.Add($id) }
    }
    end {
        try {
            # Update-CallerPreference usa Set-Variable, que tambien obedece -WhatIf e imprimiria
            # un "What if" por cada preferencia.
            $whatIf = $WhatIfPreference
            $WhatIfPreference = $false
            Update-CallerPreference $PSCmdlet -Skip Confirm, WhatIf
            $WhatIfPreference = $whatIf

            if(!(Test-Path $script:CacheRoot)) {
                Write-Verbose "No hay cache en $script:CacheRoot"
                return
            }

            $folders = $subscriptions.Count ?
                @($subscriptions | ForEach-Object { GetCacheFolder $_ } | Where-Object { Test-Path $_ }) :
                @(Get-ChildItem $script:CacheRoot -Directory | ForEach-Object FullName)

            foreach($folder in $folders) {
                if($Month) {
                    $files = @(Get-ChildItem $folder -File | Where-Object {
                        $name = $_.Name
                        @($Month | Where-Object { $name -like "cost-*-$_.json" -or $name -like "cost-*-$_-part*.csv" }).Count
                    })
                    foreach($file in $files) {
                        if($PSCmdlet.ShouldProcess($file.FullName, 'Borrar del cache')) {
                            Remove-Item $file.FullName -Force
                        }
                    }
                }
                elseif($PSCmdlet.ShouldProcess($folder, 'Borrar cache de la suscripcion')) {
                    Remove-Item $folder -Recurse -Force
                }
            }
        }
        catch {
            $PSCmdlet.WriteError($_)
        }
    }
}
