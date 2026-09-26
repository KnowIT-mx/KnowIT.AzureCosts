# Orden = preferencia. FOCUS primero, esquema legacy (ActualCost/AmortizedCost) despues.
# La Cost Details API entrega el legacy, con nombres en camelCase: la busqueda no distingue
# mayusculas.
$script:CandidatasColumnas = [ordered]@{
    resource_id    = 'ResourceId', 'InstanceId', 'InstanceName'
    resource_name  = , 'ResourceName'
    resource_type  = 'ResourceType', 'ConsumedService', 'MeterCategory'
    resource_group = 'x_ResourceGroupName', 'ResourceGroup', 'ResourceGroupName'
    servicio       = 'ServiceName', 'MeterCategory', 'ConsumedService'
    charge         = 'ChargeCategory', 'ChargeType'
    region         = 'RegionName', 'RegionId', 'ResourceLocation', 'MeterRegion'
    tags           = , 'Tags'
    # EffectiveCost es el amortizado en FOCUS; para atribucion mensual es el correcto.
    costo          = 'EffectiveCost', 'BilledCost', 'CostInBillingCurrency', 'Cost', 'PreTaxCost', 'CostInUSD'
    moneda         = 'BillingCurrency', 'BillingCurrencyCode', 'Currency'
}

function NewColumnMap ([string[]]$Headers)
{
    # Hashtable de PowerShell: llaves sin distinguir mayusculas.
    $indice = @{}
    foreach($h in $Headers) {
        if(!$indice.ContainsKey($h)) { $indice[$h] = $h }
    }
    $mapa = @{}
    foreach($campo in $script:CandidatasColumnas.Keys) {
        $mapa[$campo] = $null
        foreach($candidata in $script:CandidatasColumnas[$campo]) {
            if($indice.ContainsKey($candidata)) {
                $mapa[$campo] = $indice[$candidata]
                break
            }
        }
    }
    $mapa
}

function ConvertFromTagsText ([string]$Text)
{
    # FOCUS entrega Tags como JSON: {"Owner":"pepe"}
    # El export legacy lo entrega SIN llaves: "Owner": "pepe", "Env": "prod"
    # Esta diferencia es la causa clasica de reportar todo como sin etiquetar.
    $tags = @{}
    if([string]::IsNullOrWhiteSpace($Text)) { return $tags }

    $texto = $Text.Trim()
    if(!$texto.StartsWith('{')) { $texto = "{$texto}" }
    try {
        $datos = ConvertFrom-Json $texto -AsHashtable -ErrorAction Stop
    }
    catch {
        return $tags
    }
    if($datos -isnot [System.Collections.IDictionary]) { return $tags }

    foreach($k in $datos.Keys) {
        $tags[[string]$k] = "$($datos[$k])"
    }
    return $tags
}

function ConvertToCostNumber ([string]$Text)
{
    # InvariantCulture: el CSV usa punto decimal y a veces notacion cientifica, sin
    # importar la configuracion regional de la maquina.
    $valor = 0.0
    if([double]::TryParse($Text, [Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$valor)) {
        return $valor
    }
    return 0.0
}
