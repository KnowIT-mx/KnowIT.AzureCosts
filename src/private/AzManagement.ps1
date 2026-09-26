function InvokeAzManagement
{
    # Llamada a Azure Resource Manager. Devuelve el valor (o el objeto de respuesta completo
    # con -DetailResponse) y lanza excepcion si Azure responde con error: las funciones
    # publicas la atrapan y la emiten con $PSCmdlet.WriteError.
    param(
        # Ruta relativa a https://management.azure.com, o URL absoluta (p. ej. el
        # encabezado Location de una operacion asincrona o un nextLink).
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$Method = 'GET',

        [object]$Body,

        [string]$Tenant,

        # Devuelve Success, StatusCode, Headers, Value y Content (el cuerpo sin desenvolver)
        # en vez de solo el valor, y no lanza excepcion por error. Hace falta para las
        # operaciones que responden 202 y para paginar con nextLink.
        [switch]$DetailResponse
    )

    $uri = $Path -match '^https://' ? $Path : "$script:ArmEndpoint/$($Path.TrimStart('/'))"
    $restParams = @{
        Method      = $Method
        Uri         = $uri
        Headers     = @{ Authorization = "Bearer $(GetArmToken $Tenant)" }
        Body        = $Body ? (ConvertTo-Json $Body -Depth 6) : $null
        ContentType = 'application/json'
        Verbose     = $false
    }
    Write-Verbose "Request ARM: $Method $uri"
    if($Body) { Write-Debug "Body: $($restParams.Body)" }

    $result = Invoke-RestMethod @restParams -SkipHttpErrorCheck -StatusCodeVariable statusCode -ResponseHeadersVariable headers

    if($statusCode -lt 400) {
        Write-Verbose "Response ARM: [$statusCode] $([Net.HttpStatusCode]$statusCode)"
        $response = [PSCustomObject]@{
            PSTypeName = 'KnowIT.AzureCosts.Response'
            Success    = $true
            StatusCode = $statusCode
            Headers    = $headers
            Value      = $result.value ?? $result
            Content    = $result
        }
    }
    else {
        Write-Debug 'Procesando error en la respuesta del API:'
        Write-Debug (ConvertTo-Json $result -Depth 8)
        $response = [PSCustomObject]@{
            PSTypeName = 'KnowIT.AzureCosts.Response'
            Success    = $false
            StatusCode = $statusCode
            Headers    = $headers
            Content    = $result
            Error      = [ordered]@{
                code    = $result.error.code ?? "$([Net.HttpStatusCode]$statusCode)"
                message = $result.error.message ?? "$result"
            }
        }
        Write-Verbose "Response ARM: [$statusCode] $($response.Error.code) - $($response.Error.message)"
    }

    if($DetailResponse) {
        return $response
    }
    if(!$response.Success) {
        throw (FormatArmError $response)
    }
    $response.Value
}
