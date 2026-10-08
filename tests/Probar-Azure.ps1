#requires -Modules KnowIT.Builder, Az.Accounts
<#
    Prueba los comandos contra Azure con la sesion de Az que este activa y contra cualquier
    suscripcion a la que esa sesion tenga acceso.

    Verificar.ps1 cubre la logica con datos sinteticos; esto cubre lo que solo se puede
    comprobar con una sesion real: autenticacion, paginacion de Resource Graph, el ciclo
    202/Location de la Cost Details API y el cache en ~/.knowit/KnowIT.AzureCosts.

    Si el mes no esta en cache, el detalle de costos solo se descarga con -IncludeCostDetail
    porque gasta la consulta del dia (Microsoft pide <=1 por suscripcion).

        Connect-AzAccount -Tenant <tenant>
        pwsh ./tests/Probar-Azure.ps1 -SubscriptionId <guid>
        pwsh ./tests/Probar-Azure.ps1 -SubscriptionId <guid> -Month 2026-08 -IncludeCostDetail
#>

param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId,

    [ValidatePattern('^\d{4}-\d{2}$')]
    [string]$Month = (Get-Date).AddMonths(-1).ToString('yyyy-MM'),

    # Sin -Tenant se usa el del contexto de Az.
    [string]$Tenant,

    [switch]$IncludeCostDetail
)

$ErrorActionPreference = 'Stop'
Import-Module $PSScriptRoot/../src/KnowIT.AzureCosts.psm1 -Force -DisableNameChecking
$module = Get-Module KnowIT.AzureCosts

$script:Failures = [System.Collections.Generic.List[string]]::new()

function Check ([string]$Name, $Actual, $Expected, [double]$Tolerance = 0)
{
    $ok = ($Expected -is [ValueType] -and $Expected -isnot [bool]) ?
        ([math]::Abs([double]$Actual - [double]$Expected) -le $Tolerance) :
        ("$Actual" -eq "$Expected")
    $mark = $ok ? 'OK   ' : 'FALLA'
    Write-Host "  $mark $Name`: $Actual$($ok ? '' : "  (esperado $Expected)")" -ForegroundColor ($ok ? 'Gray' : 'Red')
    if(!$ok) { $script:Failures.Add($Name) }
}

function Split-Output ([object[]]$Output)
{
    # Cuenta los errores que la funcion emite por el stream (2>&1). -ErrorVariable no sirve
    # para esto: tambien junta los que la funcion atrapa en su propio try/catch.
    [PSCustomObject]@{
        Values = @($Output | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] })
        Errors = @($Output | Where-Object { $_ -is [Management.Automation.ErrorRecord] })
    }
}

$common = @{ SubscriptionId = $SubscriptionId }
if($Tenant) { $common.Tenant = $Tenant }

# --- sesion ----------------------------------------------------------------------------------
Write-Host "`n--- sesion ---"
$context = Get-AzContext
if(!$context) {
    Write-Host '  No hay sesion de Azure. Ejecuta Connect-AzAccount' -ForegroundColor Red
    exit 1
}
Write-Host "  Cuenta: $($context.Account.Id)  Tenant: $($context.Tenant.Id)"
$cacheRoot = & $module { $script:CacheRoot }
Write-Host "  Cache: $cacheRoot"

# --- llamadas ARM (privadas) -----------------------------------------------------------------
Write-Host "`n--- InvokeAzManagement ---"
$subscription = & $module { param($s, $t) InvokeAzManagement "subscriptions/$s`?api-version=2022-12-01" -Tenant $t } $SubscriptionId $Tenant
Check 'la suscripcion es visible' $subscription.subscriptionId $SubscriptionId
# Informativo: si el tenant de la suscripcion no es el de la sesion, el acceso es delegado (p. ej. Lighthouse).
Write-Host "  Suscripcion: $($subscription.displayName)  Tenant de la suscripcion: $($subscription.tenantId)"

$missingRg = "subscriptions/$SubscriptionId/resourcegroups/rg-no-existe-$([guid]::NewGuid().ToString('N').Substring(0, 8))?api-version=2021-04-01"
$response = & $module { param($p, $t) InvokeAzManagement $p -Tenant $t -DetailResponse } $missingRg $Tenant
Check '-DetailResponse con error: StatusCode' $response.StatusCode 404
Check '-DetailResponse con error: no lanza excepcion' $response.Success $false
$threw = $false
try { & $module { param($p, $t) InvokeAzManagement $p -Tenant $t } $missingRg $Tenant } catch { $threw = $true }
Check 'sin -DetailResponse lanza excepcion' $threw $true

# --- inventario ------------------------------------------------------------------------------
Write-Host "`n--- Get-KnowITAzCostsResourceInventory ---"
$r = Split-Output (Get-KnowITAzCostsResourceInventory @common -Force -ErrorAction Continue 2>&1)
$inventory = $r.Values
Check 'sin errores' $r.Errors.Count 0
Write-Host "  Recursos: $($inventory.Count)"

# Contar en Resource Graph por separado prueba la paginacion: con mas de 1000 recursos un
# $skipToken mal manejado corta el inventario sin error.
$count = & $module {
    param($s, $t)
    InvokeAzManagement -Method POST -Tenant $t -Path 'providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' `
        -Body @{ subscriptions = @($s); query = 'resources | count'; options = @{ resultFormat = 'objectArray' } }
} $SubscriptionId $Tenant
Check 'coincide con el conteo de Resource Graph' $inventory.Count $count.data[0].Count
Check 'ResourceId sin duplicados' @($inventory.ResourceId | Sort-Object -Unique).Count $inventory.Count
Check 'todos son de la suscripcion' @($inventory | Where-Object SubscriptionId -ne $SubscriptionId).Count 0

$today = [datetime]::Now.ToString('yyyy-MM-dd')
Check 'quedo en cache' (Test-Path (Join-Path $cacheRoot "$($SubscriptionId.ToLowerInvariant())/inventory-$today.json")) $true
$cached = @(Get-KnowITAzCostsResourceInventory @common)
Check 'desde cache: mismos recursos' @(Compare-Object $cached.ResourceId $inventory.ResourceId).Count 0
Check 'desde cache: mismos tags' ($cached | ForEach-Object { $_.Tags.Count } | Measure-Object -Sum).Sum ($inventory | ForEach-Object { $_.Tags.Count } | Measure-Object -Sum).Sum
$untagged = @(Get-KnowITAzCostsResourceInventory @common -Untagged)
Check '-Untagged: solo recursos sin tags' @($untagged | Where-Object { $_.Tags.Values -match '\S' }).Count 0
Write-Host "  Sin ningun tag: $($untagged.Count)"

$all = @(Get-KnowITAzCostsResourceInventory -ErrorAction Continue 2>&1 | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] })
Check 'sin -SubscriptionId incluye la suscripcion' ($SubscriptionId -in $all.SubscriptionId) $true
Write-Host "  Todas las suscripciones: $(@($all.SubscriptionId | Sort-Object -Unique).Count) suscripciones, $($all.Count) recursos"

# --- detalle ---------------------------------------------------------------------------------
$fresh = & $module { param($s, $m) TestCostCacheFresh (ReadCostManifest $s 'ActualCost' $m) $m } $SubscriptionId $Month
if(!$fresh -and !$IncludeCostDetail) {
    Write-Host "`n--- detalle de costos: omitido ($Month no esta en cache; -IncludeCostDetail lo descarga y gasta la consulta del dia) ---" -ForegroundColor Yellow
}
else {
    Write-Host "`n--- Get-KnowITAzCostsDetail ($Month, $($fresh ? 'desde cache' : 'descargando')) ---"
    $r = Split-Output (Get-KnowITAzCostsDetail -Month $Month @common -Verbose -ErrorAction Continue 2>&1 4>&1 |
        ForEach-Object { if($_ -is [Management.Automation.VerboseRecord]) { Write-Host "  $($_.Message)" -ForegroundColor DarkGray } else { $_ } })
    $detail = $r.Values
    Check 'sin errores' $r.Errors.Count 0
    $r.Errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    $total = ($detail | Measure-Object Cost -Sum).Sum
    Check 'devolvio costos' ($detail.Count -gt 0) $true
    Check 'una fila por recurso' @($detail | Where-Object ResourceId | Group-Object ResourceId | Where-Object Count -gt 1).Count 0
    Write-Host ("  {0} filas, total {1:N2} {2}, {3} cruzaron con el inventario" -f $detail.Count, $total, $detail[0].Currency, @($detail | Where-Object ExistsInInventory).Count)

    $untaggedCost = @(Get-KnowITAzCostsDetail -Month $Month @common -Untagged)
    Check '-Untagged es un subconjunto' ($untaggedCost.Count -le $detail.Count) $true
    Write-Host ("  Sin ningun tag: {0} filas, {1:N2}" -f $untaggedCost.Count, ($untaggedCost | Measure-Object Cost -Sum).Sum)

    $byGroup = $detail | Where-Object ResourceGroup | Group-Object ResourceGroup | Sort-Object Count -Descending | Select-Object -First 1
    $oneGroup = @(Get-KnowITAzCostsDetail -Month $Month @common -ResourceGroup $byGroup.Name)
    Check '-ResourceGroup filtra desde cache' $oneGroup.Count $byGroup.Count

    # --- export crudo ------------------------------------------------------------------------
    Write-Host "`n--- Export-KnowITAzCostsRaw ($Month) ---"
    $out = Join-Path ([IO.Path]::GetTempPath()) "probar-raw-$([guid]::NewGuid().ToString('N')).csv"
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $file = Export-KnowITAzCostsRaw -Month $Month @common -Path $out
    $watch.Stop()
    $raw = @(Import-Csv $file.FullName)
    $costColumn = @('costInBillingCurrency', 'CostInBillingCurrency', 'EffectiveCost').Where({ $_ -in $raw[0].PSObject.Properties.Name }, 'First')[0]
    $rawTotal = ($raw | ForEach-Object { [double]::Parse($_.$costColumn, [cultureinfo]::InvariantCulture) } | Measure-Object -Sum).Sum
    Check 'el crudo suma lo mismo que el detalle' $rawTotal $total 0.01
    Write-Host ("  {0} filas, {1} columnas en {2:N1} s" -f $raw.Count, @($raw[0].PSObject.Properties).Count, $watch.Elapsed.TotalSeconds)
    Remove-Item $out
}

Write-Host ("`n" + '=' * 60)
if($script:Failures.Count) {
    Write-Host "FALLARON $($script:Failures.Count) verificaciones:" -ForegroundColor Red
    $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host 'Todas las verificaciones pasaron.' -ForegroundColor Green
