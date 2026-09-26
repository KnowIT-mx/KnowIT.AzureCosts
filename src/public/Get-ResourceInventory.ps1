function Get-ResourceInventory {
    <#
        Inventario completo de recursos ARM de una suscripcion, via Azure Resource Graph.
        Hace falta porque el detalle de costos solo ve lo que genero cargo: un NSG sin tags
        o un disco desasociado no aparecen ahi.
    #>

    [CmdletBinding(DefaultParameterSetName = 'Azure')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Azure')]
        [ValidateNotNullOrWhiteSpace()]
        [string]$SubscriptionId,

        [Parameter(ParameterSetName = 'Azure')]
        [ValidateNotNullOrWhiteSpace()]
        [Alias('TenantId')]
        [string]$Tenant,

        # Guarda el inventario en un JSON que despues se lee con -Path, para regenerar el
        # reporte sin volver a consultar Azure.
        [Parameter(ParameterSetName = 'Azure')]
        [ValidateNotNullOrWhiteSpace()]
        [string]$OutFile,

        # Inventario ya guardado: la respuesta de Resource Graph ({ data: [...] }) o un
        # arreglo con id, name, type, resourceGroup, location, tags.
        [Parameter(Mandatory, ParameterSetName = 'Archivo')]
        [string]$Path
    )

    try {
        Update-CallerPreference $PSCmdlet

        if($PSCmdlet.ParameterSetName -eq 'Archivo') {
            $crudo = Get-Content $Path -Raw | ConvertFrom-Json
            # No sirve '$crudo.data ?? $crudo': sobre un arreglo, .data enumera los elementos
            # y devuelve un $null por cada uno, que ?? no descarta. Salian recursos vacios.
            $items = $crudo.PSObject.Properties['data'] ? $crudo.data : $crudo
            foreach($item in $items) {
                NewResourceItem -Id $item.id -Name $item.name -Type $item.type `
                    -ResourceGroup $item.resourceGroup -Location $item.location -Tags $item.tags
            }
            return
        }

        $apiParams = @{}
        if($Tenant) { $apiParams.Tenant = $Tenant }
        $skipToken = $null
        $total = 0
        $crudos = [System.Collections.Generic.List[object]]::new()

        do {
            $opciones = @{ resultFormat = 'objectArray'; '$top' = 1000 }
            if($skipToken) { $opciones.'$skipToken' = $skipToken }

            $respuesta = Invoke-AzManagement @apiParams -Method POST `
                -Path 'providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' `
                -Body @{
                    subscriptions = @($SubscriptionId)
                    query         = 'resources | project id, name, type, resourceGroup, location, tags'
                    options       = $opciones
                }

            # Invoke-AzManagement desenvuelve .value; ARG usa .data, asi que llega el cuerpo completo.
            foreach($item in $respuesta.data) {
                if($OutFile) { $crudos.Add($item) }
                NewResourceItem -Id $item.id -Name $item.name -Type $item.type `
                    -ResourceGroup $item.resourceGroup -Location $item.location -Tags $item.tags
            }
            $total += @($respuesta.data).Count
            $skipToken = $respuesta.'$skipToken'
            Write-Verbose "  Resource Graph: $total recursos acumulados"
        } while($skipToken)

        # Se escribe al final y no por pagina: si una pagina falla, no queda un inventario a
        # medias que parezca completo.
        if($OutFile) {
            $carpeta = Split-Path $OutFile -Parent
            if($carpeta) { $null = New-Item -ItemType Directory -Path $carpeta -Force }
            # Mismo formato que devuelve Resource Graph, que es el que lee -Path.
            ConvertTo-Json -InputObject @{ data = $crudos } -Depth 6 | Set-Content $OutFile -Encoding utf8
            Write-Verbose "Inventario guardado en $OutFile"
        }
    }
    catch {
        $PSCmdlet.WriteError($_)
    }
}
