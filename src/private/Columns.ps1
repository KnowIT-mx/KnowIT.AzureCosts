# Orden = preferencia. FOCUS primero, esquema legacy (ActualCost/AmortizedCost) despues.
# La Cost Details API entrega el legacy con nombres en camelCase: la busqueda no distingue
# mayusculas.
$script:ColumnCandidates = [ordered]@{
    ResourceId    = 'ResourceId', 'InstanceId', 'InstanceName'
    ResourceName  = , 'ResourceName'
    ResourceType  = 'ResourceType', 'ConsumedService', 'MeterCategory'
    ResourceGroup = 'x_ResourceGroupName', 'ResourceGroup', 'ResourceGroupName'
    Service       = 'ServiceName', 'MeterCategory', 'ConsumedService'
    Charge        = 'ChargeCategory', 'ChargeType'
    Location      = 'RegionName', 'RegionId', 'ResourceLocation', 'MeterRegion'
    Tags          = , 'Tags'
    # EffectiveCost es el amortizado en FOCUS; para atribucion mensual es el correcto.
    Cost          = 'EffectiveCost', 'BilledCost', 'CostInBillingCurrency', 'Cost', 'PreTaxCost', 'CostInUSD'
    Currency      = 'BillingCurrency', 'BillingCurrencyCode', 'Currency'
    Date          = 'ChargePeriodStart', 'Date', 'UsageDate'
}

# La Cost Details API entrega MM/dd/yyyy; FOCUS, ISO 8601 con zona.
$script:DateFormats = [string[]]@('MM/dd/yyyy', 'M/d/yyyy', 'yyyy-MM-dd', 'yyyy-MM-ddTHH:mm:ssK', 'yyyy-MM-ddTHH:mm:ss')

function NewColumnMap ([string[]]$Headers)
{
    # Hashtable de PowerShell: llaves sin distinguir mayusculas.
    $index = @{}
    foreach($header in $Headers) {
        if(!$index.ContainsKey($header)) { $index[$header] = $header }
    }
    $map = @{}
    foreach($field in $script:ColumnCandidates.Keys) {
        $map[$field] = $null
        foreach($candidate in $script:ColumnCandidates[$field]) {
            if($index.ContainsKey($candidate)) {
                $map[$field] = $index[$candidate]
                break
            }
        }
    }
    $map
}

function ConvertFromTagsText ([string]$Text)
{
    # FOCUS entrega Tags como JSON: {"Owner":"pepe"}
    # El export legacy a veces lo entrega SIN llaves: "Owner": "pepe", "Env": "prod"
    # Esta diferencia es la causa clasica de reportar todo como sin etiquetar.
    $tags = @{}
    if([string]::IsNullOrWhiteSpace($Text)) { return $tags }

    $json = $Text.Trim()
    if(!$json.StartsWith('{')) { $json = "{$json}" }
    try {
        $data = ConvertFrom-Json $json -AsHashtable -ErrorAction Stop
    }
    catch {
        return $tags
    }
    if($data -isnot [System.Collections.IDictionary]) { return $tags }

    foreach($key in $data.Keys) {
        $tags[[string]$key] = "$($data[$key])"
    }
    return $tags
}

function ConvertToCostNumber ([string]$Text)
{
    # InvariantCulture: el CSV usa punto decimal y a veces notacion cientifica, sin
    # importar la configuracion regional de la maquina.
    $value = 0.0
    if([double]::TryParse($Text, [Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$value)) {
        return $value
    }
    return 0.0
}

function ConvertToUsageDate ([string]$Text)
{
    # AdjustToUniversal: sin el, '2026-08-01T00:00:00Z' en Mexico se vuelve 31 de julio.
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    $value = [datetime]::MinValue
    if([datetime]::TryParseExact($Text.Trim(), $script:DateFormats, [cultureinfo]::InvariantCulture, $styles, [ref]$value)) {
        return $value.Date
    }
    return $null
}

function ReadCostRows ([string[]]$Path)
{
    # Devuelve @{ Rows; Headers }. Los parts de un mismo reporte comparten esquema; entre
    # meses podria cambiar, asi que los encabezados son la union en orden de aparicion.
    $rows = [System.Collections.Generic.List[object]]::new()
    $headers = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($file in $Path) {
        $batch = Import-Csv -Path $file -Encoding utf8
        if($batch) {
            foreach($name in $batch[0].PSObject.Properties.Name) {
                if($seen.Add($name)) { $headers.Add($name) }
            }
        }
        foreach($row in $batch) { $rows.Add($row) }
    }
    @{ Rows = $rows; Headers = @($headers) }
}
