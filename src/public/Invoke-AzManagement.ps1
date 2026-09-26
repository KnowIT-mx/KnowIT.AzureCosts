function Invoke-AzManagement {

    [CmdletBinding()]
    param(
        # Ruta relativa a https://management.azure.com, o URL absoluta (p. ej. el
        # encabezado Location de una operacion asincrona).
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$Method = 'GET',

        [object]$Body,

        [ValidateNotNullOrWhiteSpace()]
        [Alias('TenantId')]
        [string]$Tenant,

        # Devuelve el objeto de respuesta completo (Success, StatusCode, Headers, Value/Error)
        # en vez de solo el valor. Hace falta para las operaciones que responden 202.
        [switch]$DetailResponse
    )

    try {
        Update-CallerPreference $PSCmdlet -Skip Verbose
        if($DebugPreference -eq 'Continue') {
            $VerbosePreference = 'Continue'
        }

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
    catch {
        $PSCmdlet.WriteError($_)
    }
}
