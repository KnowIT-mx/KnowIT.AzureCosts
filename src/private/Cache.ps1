# Cache local por usuario en ~/.knowit/KnowIT.AzureCosts: sobrevive reinicios y usuario
# quien mantiene el suyo. Estructura:
#   <CacheRoot>/<suscripcion>/inventory-<yyyy-MM-dd>.json          un archivo por dia
#   <CacheRoot>/<suscripcion>/cost-<metrica>-<yyyy-MM>.json        manifiesto del mes
#   <CacheRoot>/<suscripcion>/cost-<metrica>-<yyyy-MM>-partN.csv   detalle tal cual de la API
# El manifiesto se escribe al final: un CSV sin manifiesto es una descarga interrumpida y
# no cuenta.

# Un mes se considera definitivo si se descargo al menos estos dias despues de cerrar: antes
# de eso Azure todavia consolida cargos del mes.
$script:CostFinalAfterDays = 5
# Mes en curso o recien cerrado: se vuelve a pedir pasado este tiempo. Microsoft pide no
# consultar la Cost Details API mas de una vez al dia por suscripcion.
$script:CostMaxAge = [timespan]::FromHours(24)

function GetCacheFolder ([string]$SubscriptionId)
{
    Join-Path $script:CacheRoot $SubscriptionId.ToLowerInvariant()
}

function GetCostCacheBaseName ([string]$Metric, [string]$Month)
{
    "cost-$($Metric.ToLowerInvariant())-$Month"
}

function ReadCostManifest ([string]$SubscriptionId, [string]$Metric, [string]$Month)
{
    $path = Join-Path (GetCacheFolder $SubscriptionId) "$(GetCostCacheBaseName $Metric $Month).json"
    if(!(Test-Path $path)) { return $null }
    try {
        Get-Content $path -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        # Un manifiesto corrupto equivale a no tener cache: se vuelve a descargar.
        Write-Verbose "Manifiesto ilegible, se ignora: $path"
        $null
    }
}

function TestCostCacheFresh ($Manifest, [string]$Month)
{
    if(!$Manifest) { return $false }

    $downloadedAt = ([datetime]$Manifest.downloadedAt).ToUniversalTime()
    $first = [datetime]::ParseExact("$Month-01", 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
    $finalFrom = $first.AddMonths(1).AddDays($script:CostFinalAfterDays)
    if($downloadedAt -ge $finalFrom) { return $true }

    return ([datetime]::UtcNow - $downloadedAt) -lt $script:CostMaxAge
}

function WriteCacheFile ([string]$Path, [string]$Content)
{
    # Escribir a un temporal y mover: si el proceso se interrumpe no queda un archivo a
    # medias con el nombre bueno.
    $folder = Split-Path $Path -Parent
    $null = New-Item -ItemType Directory -Path $folder -Force
    $temp = "$Path.tmp"
    Set-Content -Path $temp -Value $Content -Encoding utf8 -NoNewline
    Move-Item -Path $temp -Destination $Path -Force
}
