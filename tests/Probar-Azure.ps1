#requires -Modules KnowIT.Builder, Az.Accounts, ImportExcel
<#
    Prueba contra Azure las funciones que llaman a ARM: Invoke-AzManagement,
    Get-ResourceInventory y Get-CostDetail, con la sesion de Az que este activa y contra
    cualquier suscripcion a la que esa sesion tenga acceso.

    Verificar.ps1 cubre el analisis con datos sinteticos; esto cubre lo que solo se puede
    comprobar con una sesion real: autenticacion, paginacion de Resource Graph
    y el ciclo 202/Location de la Cost Details API.

    Get-CostDetail solo corre con -IncludeCostDetail porque gasta la consulta del dia
    (Microsoft pide <=1 por suscripcion). Si los CSV del mes ya estan en -Path se
    reutilizan en vez de volver a pedirlos, salvo con -Force.

        Connect-AzAccount -Tenant <tenant>
        pwsh ./tests/Probar-Azure.ps1 -SubscriptionId <guid>
        pwsh ./tests/Probar-Azure.ps1 -SubscriptionId <guid> -IncludeCostDetail -Month 2026-08
#>

param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId,

    [ValidatePattern('^\d{4}-\d{2}$')]
    [string]$Month = (Get-Date).AddMonths(-1).ToString('yyyy-MM'),

    # Sin -Tenant se usa el del contexto de Az.
    [string]$Tenant,

    # Donde quedan inventario, CSV y xlsx. salidas/ esta ignorado por git.
    [string]$Path = (Join-Path $PSScriptRoot '../salidas'),

    [switch]$IncludeCostDetail,

    # Vuelve a pedir el detalle aunque los CSV del mes ya existan.
    [switch]$Force,

    [string[]]$RequiredTags = @('Environment', 'Owner', 'CostCenter')
)

$ErrorActionPreference = 'Stop'
Import-Module $PSScriptRoot/../src/KnowIT.AzureCosts.psm1 -Force -DisableNameChecking

$script:fallos = [System.Collections.Generic.List[string]]::new()

function Check ([string]$Nombre, $Obtenido, $Esperado)
{
    $ok = "$Obtenido" -eq "$Esperado"
    $marca = $ok ? 'OK   ' : 'FALLA'
    Write-Host "  $marca $Nombre`: $Obtenido$($ok ? '' : "  (esperado $Esperado)")" -ForegroundColor ($ok ? 'Gray' : 'Red')
    if(!$ok) { $script:fallos.Add($Nombre) }
}

function Separar ([object[]]$Salida)
{
    # Cuenta los errores que la funcion emite por el stream (2>&1). -ErrorVariable no sirve
    # para esto: tambien junta los que la funcion atrapa en su propio try/catch.
    [PSCustomObject]@{
        Valores = @($Salida | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] })
        Errores = @($Salida | Where-Object { $_ -is [Management.Automation.ErrorRecord] })
    }
}

$carpeta = New-Item -ItemType Directory -Path $Path -Force
$apiParams = @{}
if($Tenant) { $apiParams.Tenant = $Tenant }

# --- sesion ----------------------------------------------------------------------------------
Write-Host "`n--- sesion ---"
$contexto = Get-AzContext
if(!$contexto) {
    Write-Host '  No hay sesion de Azure. Ejecuta Connect-AzAccount' -ForegroundColor Red
    exit 1
}
Write-Host "  Cuenta: $($contexto.Account.Id)  Tenant: $($contexto.Tenant.Id)"

# --- Invoke-AzManagement ---------------------------------------------------------------------
Write-Host "`n--- Invoke-AzManagement ---"
$sub = Invoke-AzManagement @apiParams "subscriptions/$SubscriptionId`?api-version=2022-12-01"
Check 'la suscripcion es visible' $sub.subscriptionId $SubscriptionId
Check 'la suscripcion esta habilitada' $sub.state 'Enabled'
# Informativo: si el tenant de la suscripcion no es el de la sesion, el acceso es delegado (p. ej. Lighthouse).
Write-Host "  Suscripcion: $($sub.displayName)  Tenant de la suscripcion: $($sub.tenantId)"

$absoluta = Invoke-AzManagement @apiParams "https://management.azure.com/subscriptions/$SubscriptionId`?api-version=2022-12-01"
Check 'acepta URL absoluta (encabezado Location)' $absoluta.subscriptionId $SubscriptionId

# Un resource group que no existe da un 404 predecible sin tocar nada.
$rgFalso = "subscriptions/$SubscriptionId/resourcegroups/rg-no-existe-$([guid]::NewGuid().ToString('N').Substring(0, 8))?api-version=2021-04-01"
$r = Invoke-AzManagement @apiParams $rgFalso -DetailResponse
Check '-DetailResponse con error: Success' $r.Success $false
Check '-DetailResponse con error: StatusCode' $r.StatusCode 404
Check '-DetailResponse con error: trae codigo' ([bool]$r.Error.code) $true
Write-Host "  Error devuelto: $($r.Error.code)"

$r = Separar (Invoke-AzManagement @apiParams $rgFalso -ErrorAction Continue 2>&1)
Check 'sin -DetailResponse emite un solo error sin terminar el script' $r.Errores.Count 1
Check 'sin -DetailResponse el error no devuelve valor' $r.Valores.Count 0

# --- Get-ResourceInventory -------------------------------------------------------------------
Write-Host "`n--- Get-ResourceInventory ---"
$rutaInventario = Join-Path $carpeta "inventario-$SubscriptionId.json"
$r = Separar (Get-ResourceInventory @apiParams -SubscriptionId $SubscriptionId -OutFile $rutaInventario -ErrorAction Continue 2>&1)
$inventario = $r.Valores
Check 'sin errores' $r.Errores.Count 0
Check 'devolvio recursos' ($inventario.Count -gt 0) $true
Write-Host "  Recursos: $($inventario.Count)"

# Contar en Resource Graph por separado prueba la paginacion: con mas de 1000 recursos
# un $skipToken mal manejado corta el inventario sin error.
$conteo = Invoke-AzManagement @apiParams -Method POST `
    -Path 'providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' `
    -Body @{
        subscriptions = @($SubscriptionId)
        query         = 'resources | count'
        options       = @{ resultFormat = 'objectArray' }
    }
Check 'coincide con el conteo de Resource Graph' $inventario.Count $conteo.data[0].Count
Check 'ResourceId sin duplicados' @($inventario.IdNorm | Sort-Object -Unique).Count $inventario.Count
Check 'todos son de la suscripcion' @($inventario | Where-Object { !$_.IdNorm.StartsWith("/subscriptions/$($SubscriptionId.ToLowerInvariant())/") }).Count 0
Check 'tipo de objeto' @($inventario | Where-Object { $_.PSTypeNames[0] -ne 'KnowIT.AzureCosts.Resource' }).Count 0

$recargado = @(Get-ResourceInventory -Path $rutaInventario)
# Comparar solo el conteo no basta: un bug de lectura devolvia recursos vacios con el mismo conteo.
Check '-OutFile y -Path: mismos recursos' $recargado.Count $inventario.Count
Check '-OutFile y -Path: mismos ResourceId' @(Compare-Object $recargado.IdNorm $inventario.IdNorm).Count 0
Check '-OutFile y -Path: mismos tags' (($recargado | ForEach-Object { $_.Tags.Count } | Measure-Object -Sum).Sum) (($inventario | ForEach-Object { $_.Tags.Count } | Measure-Object -Sum).Sum)
Write-Host "  Guardado en $rutaInventario"

# --- Get-CostDetail --------------------------------------------------------------------------
if(!$IncludeCostDetail) {
    Write-Host "`n--- Get-CostDetail: omitido (gasta la consulta del dia; usa -IncludeCostDetail) ---" -ForegroundColor Yellow
}
else {
    Write-Host "`n--- Get-CostDetail ($Month) ---"
    $existentes = @(Get-ChildItem $carpeta -Filter "detalle-$SubscriptionId-$Month-part*.csv")
    if($existentes -and !$Force) {
        Write-Host "  Ya hay $($existentes.Count) CSV de $Month; se reutilizan sin consultar la API (usa -Force para pedirlos de nuevo)." -ForegroundColor Yellow
        $csv = $existentes
    }
    else {
        $r = Separar (Get-CostDetail @apiParams -SubscriptionId $SubscriptionId -Month $Month -Path $carpeta -Verbose -ErrorAction Continue 2>&1)
        $csv = $r.Valores
        Check 'sin errores' $r.Errores.Count 0
        $r.Errores | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    }

    Check 'descargo al menos un CSV' ($csv.Count -gt 0) $true
    Check 'ningun CSV vacio' @($csv | Where-Object Length -eq 0).Count 0
    Check 'nombre que New-CostReport reconoce' @($csv | Where-Object Name -notmatch "^detalle-$SubscriptionId-$Month-part\d+\.csv$").Count 0

    if($csv) {
        $encabezados = (Get-Content $csv[0].FullName -TotalCount 1) -split ','
        $encabezados = $encabezados.ForEach({ $_.Trim('"') })
        Check 'trae columna ResourceId' ('ResourceId' -in $encabezados) $true
        Check 'trae columna de costo legacy' ('CostInBillingCurrency' -in $encabezados) $true

        # De punta a punta: el reporte no vuelve a llamar a Azure.
        $r = Separar ($csv | New-CostReport -Inventory $inventario -RequiredTags $RequiredTags `
            -Path (Join-Path $carpeta "reporte-costos-$SubscriptionId-$Month.xlsx") -ErrorAction Continue 2>&1)
        $reporte = $r.Valores | Select-Object -First 1
        Check 'New-CostReport sin errores' $r.Errores.Count 0
        $r.Errores | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        Check 'costo total mayor que cero' ($reporte.CostoTotal -gt 0) $true
        Write-Host "  Reporte: $($reporte.Path)"
    }
}

Write-Host ("`n" + '=' * 60)
if($script:fallos.Count) {
    Write-Host "FALLARON $($script:fallos.Count) verificaciones:" -ForegroundColor Red
    $script:fallos | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host 'Todas las verificaciones pasaron.' -ForegroundColor Green
