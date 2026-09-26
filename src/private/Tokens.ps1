#requires -Modules Az.Accounts

function GetArmToken ([string]$Tenant)
{
    # Sin -Tenant se usa el del contexto de Az. Con Azure Lighthouse eso es lo correcto:
    # el token del tenant administrador sirve para las suscripciones delegadas.
    $params = @{
        ResourceUrl    = $script:ArmEndpoint
        AsSecureString = $true
        Debug          = $false
    }
    if($Tenant) { $params.Tenant = $Tenant }

    if(!(Get-AzContext)) {
        throw 'No hay sesion de Azure. Ejecuta Connect-AzAccount (o Connect-AzAccount -Identity con una managed identity).'
    }
    $token = Get-AzAccessToken @params
    ConvertFrom-SecureString $token.Token -AsPlainText
}
