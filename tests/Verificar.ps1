#requires -Modules KnowIT.Builder, Az.Accounts
<#
    Verifica los comandos del modulo contra datos sinteticos con resultado conocido, sin
    tocar Azure: siembra un cache temporal con el detalle y el inventario y llama a los
    comandos publicos como lo haria un usuario. No basta con que corran: las cifras tienen
    que ser las correctas. Los esperados se calcularon por separado sobre los mismos archivos.

        pwsh ./tests/Verificar.ps1
#>

$ErrorActionPreference = 'Stop'
Import-Module $PSScriptRoot/../src/KnowIT.AzureCosts.psm1 -Force -DisableNameChecking
$module = Get-Module KnowIT.AzureCosts

$data = Join-Path $PSScriptRoot 'datos'
$sub = '11111111-2222-3333-4444-555555555555'
$subAdf = '22222222-3333-4444-5555-666666666666'
$today = [datetime]::Now.ToString('yyyy-MM-dd')
$script:Failures = [System.Collections.Generic.List[string]]::new()

$cacheRoot = Join-Path ([IO.Path]::GetTempPath()) "verificar-cache-$([guid]::NewGuid().ToString('N'))"
& $module { param($root) $script:CacheRoot = $root } $cacheRoot

function Check ([string]$Name, $Actual, $Expected, [double]$Tolerance = 0)
{
    $ok = ($Expected -is [ValueType] -and $Expected -isnot [bool]) ?
        ([math]::Abs([double]$Actual - [double]$Expected) -le $Tolerance) :
        ("$Actual" -ceq "$Expected")
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

function Set-CachedCost ([string]$Subscription, [string]$Metric, [string]$Month, [string]$CsvPath, [datetime]$DownloadedAt = [datetime]::UtcNow)
{
    $folder = Join-Path $cacheRoot $Subscription
    $null = New-Item -ItemType Directory -Path $folder -Force
    $base = "cost-$($Metric.ToLowerInvariant())-$Month"
    $files = @()
    if($CsvPath) {
        Copy-Item $CsvPath (Join-Path $folder "$base-part0.csv")
        $files = @("$base-part0.csv")
    }
    [ordered]@{
        subscriptionId = $Subscription; month = $Month; metric = $Metric
        status = $CsvPath ? 'Completed' : 'NoDataFound'
        downloadedAt = $DownloadedAt.ToString('o'); files = $files
    } | ConvertTo-Json | Set-Content (Join-Path $folder "$base.json")
}

function Set-CachedInventory ([string]$Subscription, [object[]]$Items)
{
    $folder = Join-Path $cacheRoot $Subscription
    $null = New-Item -ItemType Directory -Path $folder -Force
    ConvertTo-Json -InputObject @($Items) -Depth 6 | Set-Content (Join-Path $folder "inventory-$today.json")
}

function New-NoCsv ([object[]]$Rows)
{
    $path = Join-Path ([IO.Path]::GetTempPath()) "verificar-$([guid]::NewGuid()).csv"
    $Rows | Export-Csv $path -NoTypeInformation -Encoding utf8
    $path
}

try {
    # --- cache sembrado ------------------------------------------------------------------
    $inventoryItems = @((Get-Content (Join-Path $data 'inventario.json') -Raw | ConvertFrom-Json).data |
        Select-Object *, @{ Name = 'subscriptionId'; Expression = { $sub } })
    Set-CachedInventory $sub $inventoryItems
    Set-CachedCost $sub 'ActualCost' '2026-08' (Join-Path $data 'costos-legacy.csv')
    Set-CachedCost $sub 'AmortizedCost' '2026-08' (Join-Path $data 'costos-focus.csv')
    Set-CachedCost $sub 'ActualCost' '2026-07' $null

    # --- inventario ----------------------------------------------------------------------
    Write-Host "`n--- Get-KnowITAzCostsResourceInventory ---"
    $inventory = @(Get-KnowITAzCostsResourceInventory -SubscriptionId $sub)
    Check 'recursos' $inventory.Count 13
    Check 'tipo de objeto' @($inventory | Where-Object { $_.PSTypeNames[0] -ne 'KnowIT.AzureCosts.Resource' }).Count 0
    Check 'trae la suscripcion' @($inventory | Where-Object SubscriptionId -ne $sub).Count 0
    Check '-Untagged: sin ningun tag' @(Get-KnowITAzCostsResourceInventory -SubscriptionId $sub -Untagged).Count 5
    Check '-ResourceGroup con comodin' @(Get-KnowITAzCostsResourceInventory -SubscriptionId $sub -ResourceGroup 'RG-PROD-*').Count 6
    Check 'acepta suscripciones por pipeline' @([PSCustomObject]@{ Id = $sub } | Get-KnowITAzCostsResourceInventory).Count 13
    $json = @(Get-KnowITAzCostsResourceInventory -SubscriptionId $sub -TagsAsJson)
    $vm = $json | Where-Object Name -eq 'vm-app-01'
    Check '-TagsAsJson: JSON compacto con llaves en orden' $vm.Tags '{"CostCenter":"IT-100","Environment":"prod","Owner":"Equipo-FinOps"}'
    Check '-TagsAsJson: sin tags queda {}' ($json | Where-Object Name -eq 'nsg-app').Tags '{}'
    Check '-TagsAsJson: Export-Csv escribe el JSON' ((($json | Where-Object Name -eq 'vm-app-01') | ConvertTo-Csv)[1] -match 'CostCenter') $true
    Check '-TagsAsJson con -Untagged' (@(Get-KnowITAzCostsResourceInventory -SubscriptionId $sub -Untagged -TagsAsJson | Where-Object Tags -ne '{}').Count) 0

    # --- detalle: esquemas completos -------------------------------------------------------
    $cases = @(
        @{ Name = 'legacy (ActualCost)'; Metric = 'ActualCost'; Rows = 12; InInventory = 9; Total = 1599.1555; Range = 611.2609; Untagged = 5; UntaggedCost = 829.1811 }
        @{ Name = 'focus (AmortizedCost)'; Metric = 'AmortizedCost'; Rows = 10; InInventory = 9; Total = 1453.6555; Range = 465.7609; Untagged = 3; UntaggedCost = 683.6811 }
    )
    foreach($case in $cases) {
        Write-Host "`n--- Get-KnowITAzCostsDetail, $($case.Name) ---"
        $detail = @(Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -Metric $case.Metric)
        Check 'una fila por recurso' $detail.Count $case.Rows
        Check 'costo total' ($detail | Measure-Object Cost -Sum).Sum $case.Total 0.001
        Check 'cruzaron con el inventario' @($detail | Where-Object ExistsInInventory).Count $case.InInventory
        Check 'moneda' ($detail[0].Currency) 'USD'
        Check 'ordenado por costo' $detail[0].Cost 673.038 0.001

        $vm = $detail | Where-Object ResourceName -eq 'vm-app-01'
        Check 'cruce por casing distinto toma el resource group de ARG' $vm.ResourceGroup 'rg-prod-app'
        Check 'recurso vigente: tags de hoy' $vm.Tags['Owner'] 'Equipo-FinOps'
        $deleted = $detail | Where-Object ResourceName -eq 'vm-migracion-tmp'
        Check 'recurso borrado: sigue visible' ([bool]($deleted -and !$deleted.ExistsInInventory)) $true
        Check 'recurso borrado: tags del cargo' $deleted.Tags['Owner'] 'Equipo-FinOps'

        $range = @(Get-KnowITAzCostsDetail -StartDate 2026-08-01 -EndDate 2026-08-10 -SubscriptionId $sub -Metric $case.Metric)
        Check 'rango de fechas dentro del mes' ($range | Measure-Object Cost -Sum).Sum $case.Range 0.001

        $untagged = @(Get-KnowITAzCostsDetail -Period 2026-08 -SubscriptionId $sub -Metric $case.Metric -Untagged)
        Check '-Untagged: recursos' $untagged.Count $case.Untagged
        Check '-Untagged: costo' ($untagged | Measure-Object Cost -Sum).Sum $case.UntaggedCost 0.001

        $prod = @(Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -Metric $case.Metric -Tag @{ Environment = 'PROD' })
        Check '-Tag sin distinguir mayusculas' ($prod | Measure-Object Cost -Sum).Sum 401.2245 0.001
        Check '-Tag con comodin' @(Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -Metric $case.Metric -Tag @{ Environment = 'pr*' }).Count 3
        $rg = @(Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -Metric $case.Metric -ResourceGroup 'rg-prod-*')
        Check '-ResourceGroup con comodin' ($rg | Measure-Object Cost -Sum).Sum 1199.8495 0.001
    }

    Write-Host "`n--- Get-KnowITAzCostsDetail, casos puntuales ---"
    $staging = Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub | Where-Object ResourceName -eq 'sql-erp-staging'
    Check 'tag con valor vacio no cuenta como etiquetado' ([bool](Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -Tag @{ Owner = '?*' } | Where-Object ResourceName -eq 'sql-erp-staging')) $false
    Check 'pero el recurso no es -Untagged' ([bool]($staging.Tags.Count)) $true
    $charges = @(Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub | Where-Object { !$_.ResourceId })
    Check 'cargos sin recurso como filas propias' $charges.Count 2
    Check 'cargos sin recurso traen tipo de cargo' (@($charges.ChargeType | Sort-Object -Unique) -join ',') 'Purchase'

    $withColumns = @(Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -TagColumn Owner, Location)
    $vm = $withColumns | Where-Object ResourceName -eq 'vm-app-01'
    Check '-TagColumn agrega la propiedad' $vm.Owner 'Equipo-FinOps'
    Check '-TagColumn que choca con una propiedad usa tag_' ([bool]($vm.PSObject.Properties['tag_Location'])) $true
    Check '-TagColumn no pisa la propiedad original' $vm.Location 'eastus'
    $json = @(Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -Tag @{ Environment = 'prod' } -TagColumn Owner -TagsAsJson)
    Check '-TagsAsJson en el detalle: filtra antes de convertir' $json.Count 3
    Check '-TagsAsJson en el detalle: -TagColumn sigue funcionando' (@($json.Owner | Sort-Object -Unique) -join ',') 'Equipo-FinOps'
    Check '-TagsAsJson en el detalle: Tags es texto' ($json[0].Tags -is [string]) $true

    $crossing = Split-Output (Get-KnowITAzCostsDetail -StartDate 2026-07-25 -EndDate 2026-08-03 -SubscriptionId $sub -ErrorAction Continue 2>&1 3>$null)
    Check 'rango que cruza meses: mes sin datos no es error' $crossing.Errors.Count 0
    Check 'rango que cruza meses: una fila por recurso por mes' (@($crossing.Values.Month | Sort-Object -Unique) -join ',') '2026-08'

    $bad = Split-Output (Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub -Untagged -Tag @{ Owner = 'Equipo-FinOps' } -ErrorAction Continue 2>&1)
    Check '-Untagged con -Tag es error' $bad.Errors.Count 1
    $bad = Split-Output (Get-KnowITAzCostsDetail -Month 2099-01 -SubscriptionId $sub -ErrorAction Continue 2>&1)
    Check 'mes futuro es error' $bad.Errors.Count 1

    # --- sub-recursos sumados al padre -------------------------------------------------------
    Write-Host "`n--- sub-recursos sumados al padre ---"
    $factory = "/subscriptions/$subAdf/resourceGroups/RG-DWH/providers/Microsoft.DataFactory/factories/adf-1"
    $deletedFactory = "/subscriptions/$subAdf/resourceGroups/RG-DWH/providers/Microsoft.DataFactory/factories/adf-borrada"
    $database = "/subscriptions/$subAdf/resourceGroups/RG-DWH/providers/Microsoft.Sql/servers/srv/databases/temp-01"
    $factoryTags = '{"Environment":"Prod","Owner":"dwh","CostCenter":"100"}'
    $csv = New-NoCsv @(
        # El hijo aparece antes que el padre y con tags distintos: el padre debe ganar.
        [PSCustomObject]@{ ResourceId = "$factory/pipelines/Carga Full"; ResourceName = 'Carga Full'; Date = '2026-08-01'; CostInBillingCurrency = '10'; Tags = '{"Environment":"Otro"}' }
        [PSCustomObject]@{ ResourceId = $factory; ResourceName = 'adf-1'; Date = '2026-08-01'; CostInBillingCurrency = '1'; Tags = $factoryTags }
        [PSCustomObject]@{ ResourceId = "$factory/triggers/diario"; ResourceName = 'diario'; Date = '2026-08-01'; CostInBillingCurrency = '2'; Tags = '' }
        [PSCustomObject]@{ ResourceId = "$deletedFactory/pipelines/p1"; ResourceName = 'p1'; Date = '2026-08-01'; CostInBillingCurrency = '5'; Tags = $factoryTags }
        [PSCustomObject]@{ ResourceId = $database; ResourceName = 'temp-01'; Date = '2026-08-01'; CostInBillingCurrency = '7'; Tags = '' }
    )
    Set-CachedCost $subAdf 'ActualCost' '2026-08' $csv
    Remove-Item $csv
    Set-CachedInventory $subAdf @(
        @{ id = $factory.ToLowerInvariant(); name = 'adf-1'; type = 'microsoft.datafactory/factories'; resourceGroup = 'rg-dwh'; location = 'eastus'; subscriptionId = $subAdf; tags = @{ Environment = 'Prod' } }
        @{ id = "/subscriptions/$subAdf/resourcegroups/rg-dwh/providers/microsoft.sql/servers/srv"; name = 'srv'; type = 'microsoft.sql/servers'; resourceGroup = 'rg-dwh'; location = 'eastus'; subscriptionId = $subAdf; tags = @{} }
    )
    $adf = @(Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $subAdf)
    $f = $adf | Where-Object ResourceName -eq 'adf-1'
    $g = $adf | Where-Object ResourceName -eq 'adf-borrada'
    Check 'pipeline y trigger sumados al costo de la factory' $f.Cost 13.0
    Check 'la factory usa sus tags de hoy' $f.Tags['Environment'] 'Prod'
    Check 'ningun pipeline queda como recurso propio' @($adf | Where-Object { $_.ResourceId -match '/(pipelines|triggers)/' }).Count 0
    Check 'factory borrada toma nombre del id, no del pipeline' ([bool]$g) $true
    Check 'factory borrada sin filas propias hereda tags de sus hijos' $g.Tags['Owner'] 'dwh'
    Check 'base SQL borrada NO se suma a su servidor' @($adf | Where-Object ResourceName -eq 'temp-01').Count 1
    Check 'el total no cambia' ($adf | Measure-Object Cost -Sum).Sum 25.0
    $adfSplit = @(Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $subAdf -SplitByTagChange)
    $f = @($adfSplit | Where-Object ResourceName -eq 'adf-1')
    Check 'split: pipeline y trigger siguen los tags de la factory ese dia' "$($f.Count) $($f[0].Tags['Environment'])=$($f[0].Cost)" '1 Prod=13'
    Check 'split: factory borrada sin filas propias usa los tags del hijo' ($adfSplit | Where-Object ResourceName -eq 'adf-borrada').Tags['Owner'] 'dwh'
    Check 'varias suscripciones en una llamada' @(Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $sub, $subAdf | Select-Object -ExpandProperty SubscriptionId -Unique).Count 2

    # --- tags que cambian dentro del mes -----------------------------------------------------
    Write-Host "`n--- tags que cambian dentro del mes ---"
    $subTags = '33333333-4444-5555-6666-777777777777'
    $base = "/subscriptions/$subTags/resourceGroups/RG-T/providers/Microsoft.Compute/virtualMachines"
    $row = { param($name, $day, $cost, $tags) [PSCustomObject]@{ ResourceId = "$base/$name"; ResourceName = $name; Date = "2026-08-{0:d2}" -f $day; CostInBillingCurrency = "$cost"; Tags = $tags } }
    $rows = @(
        # vm-hoy: existe hoy con tags; en el mes tuvo Viejo (dias 1-10) y Nuevo (11-20), y el
        # dia 15 viene sin tags, como pasa en el detalle real.
        foreach($d in 1..10) { & $row 'vm-hoy' $d 1 '{"Env":"Viejo"}' }
        foreach($d in 11..20) { & $row 'vm-hoy' $d 2 ($d -eq 15 ? '' : '{"Env":"Nuevo"}') }
        # vm-sin-tags-hoy: existe hoy sin tags, pero en el mes si los tuvo.
        & $row 'vm-sin-tags-hoy' 3 5 '{"Env":"Prod"}'
        # vm-borrada: filas fuera de orden, como las entrega la API: el ultimo tag es el del dia 20.
        & $row 'vm-borrada' 20 4 '{"Env":"Ultimo"}'
        & $row 'vm-borrada' 5 3 '{"Env":"Primero"}'
        # vm-tardia: borrada, sin tags los primeros dias y etiquetada despues.
        foreach($d in 1..3) { & $row 'vm-tardia' $d 1 '' }
        & $row 'vm-tardia' 4 1 '{"Env":"X"}'
    )
    $csv = New-NoCsv $rows
    Set-CachedCost $subTags 'ActualCost' '2026-08' $csv
    Remove-Item $csv
    Set-CachedInventory $subTags @(
        @{ id = "$base/vm-hoy".ToLowerInvariant(); name = 'vm-hoy'; type = 'microsoft.compute/virtualmachines'; resourceGroup = 'rg-t'; location = 'eastus'; subscriptionId = $subTags; tags = @{ Env = 'Hoy' } }
        @{ id = "$base/vm-sin-tags-hoy".ToLowerInvariant(); name = 'vm-sin-tags-hoy'; type = 'microsoft.compute/virtualmachines'; resourceGroup = 'rg-t'; location = 'eastus'; subscriptionId = $subTags; tags = @{} }
    )

    $default = @(Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $subTags)
    $byName = @{}; foreach($d in $default) { $byName[$d.ResourceName] = $d }
    Check 'sin split: una fila por recurso' $default.Count 4
    Check 'existe hoy con tags: manda el de hoy' $byName['vm-hoy'].Tags['Env'] 'Hoy'
    Check 'existe hoy sin tags: se queda sin tags' $byName['vm-sin-tags-hoy'].Tags.Count 0
    Check 'borrado: el ultimo por fecha, no por orden de fila' $byName['vm-borrada'].Tags['Env'] 'Ultimo'
    Check 'sin split no agrega FirstDate' ([bool]$default[0].PSObject.Properties['FirstDate']) $false

    $split = @(Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $subTags -SplitByTagChange)
    $hoy = @($split | Where-Object ResourceName -eq 'vm-hoy' | Sort-Object { $_.Tags['Env'] })
    Check 'split: una fila por juego de tags, dia sin tags incluido' $hoy.Count 3
    Check 'split: usa los tags historicos aunque exista hoy' (($hoy | ForEach-Object { "$($_.Tags['Env'])=$($_.Cost)" }) -join ',') '=2,Nuevo=18,Viejo=10'
    Check 'split: el dia sin tags es su propio segmento' "$($hoy[0].FirstDate.ToString('dd'))-$($hoy[0].LastDate.ToString('dd'))" '15-15'
    Check 'split: FirstDate y LastDate de un juego' "$($hoy[1].FirstDate.ToString('dd'))-$($hoy[1].LastDate.ToString('dd'))" '11-20'
    Check 'split: borrado con dos tags' @($split | Where-Object ResourceName -eq 'vm-borrada').Count 2
    $late = @($split | Where-Object ResourceName -eq 'vm-tardia' | Sort-Object FirstDate)
    Check 'split: dias iniciales sin tags son otro segmento' (($late | ForEach-Object { "$($_.Tags['Env'])=$($_.Cost)" }) -join ',') '=3,X=1'
    Check 'sin split: borrado toma el ultimo con valor' $byName['vm-tardia'].Tags['Env'] 'X'
    Check 'split: el total no cambia' ($split | Measure-Object Cost -Sum).Sum ($default | Measure-Object Cost -Sum).Sum
    Check 'split: se puede filtrar por el tag historico' @(Get-KnowITAzCostsDetail -Month 2026-08 -SubscriptionId $subTags -SplitByTagChange -Tag @{ Env = 'Viejo' }).Count 1

    # --- export crudo ------------------------------------------------------------------------
    Write-Host "`n--- Export-KnowITAzCostsRaw ---"
    $out = Join-Path ([IO.Path]::GetTempPath()) "verificar-raw-$([guid]::NewGuid().ToString('N'))"
    $file = Export-KnowITAzCostsRaw -Month 2026-08 -SubscriptionId $sub -Path "$out/todo.csv"
    $raw = @(Import-Csv $file.FullName)
    $columns = @($raw[0].PSObject.Properties.Name)
    Check 'devuelve el archivo' ($file -is [IO.FileInfo]) $true
    Check 'todas las filas del detalle' $raw.Count 312
    Check 'columnas originales mas una por tag' $columns.Count 30
    Check 'tag que choca con una columna usa tag_' ('tag_CostCenter' -in $columns) $true
    Check 'la columna original no se pisa' ($raw[0].CostCenter) 'IT-100'
    Check 'tags del dia del cargo por default' @($raw | Where-Object { !$_.Owner }).Count 132
    $fromInventory = @(Import-Csv (Export-KnowITAzCostsRaw -Month 2026-08 -SubscriptionId $sub -Path "$out/inv.csv" -TagsFromInventory).FullName)
    Check '-TagsFromInventory usa los tags de hoy' @($fromInventory | Where-Object { !$_.Owner }).Count 127
    $limited = @(Import-Csv (Export-KnowITAzCostsRaw -Month 2026-08 -SubscriptionId $sub -Path "$out/owner.csv" -TagColumn Owner).FullName)
    Check '-TagColumn limita las columnas de tags' @($limited[0].PSObject.Properties.Name).Count 28
    Check 'rango de fechas' @(Import-Csv (Export-KnowITAzCostsRaw -StartDate 2026-08-01 -EndDate 2026-08-10 -SubscriptionId $sub -Path "$out/rango.csv").FullName).Count 102
    Check '-Untagged' @(Import-Csv (Export-KnowITAzCostsRaw -Month 2026-08 -SubscriptionId $sub -Path "$out/untagged.csv" -Untagged).FullName).Count 102
    Check '-ResourceGroup' @(Import-Csv (Export-KnowITAzCostsRaw -Month 2026-08 -SubscriptionId $sub -Path "$out/rg.csv" -ResourceGroup 'rg-prod-*').FullName).Count 155
    Check '-Tag' @(Import-Csv (Export-KnowITAzCostsRaw -Month 2026-08 -SubscriptionId $sub -Path "$out/tag.csv" -Tag @{ Environment = 'prod' }).FullName).Count 90
    Remove-Item $out -Recurse -Force

    # --- funciones internas ------------------------------------------------------------------
    Write-Host "`n--- funciones internas ---"
    & $module {
        param($check)
        & $check 'tags legacy sin llaves' ((ConvertFromTagsText '"Owner": "Equipo-FinOps", "Env": "prod"').Env) 'prod'
        & $check 'tags focus con llaves' ((ConvertFromTagsText '{"Owner":"Equipo-FinOps"}').Owner) 'Equipo-FinOps'
        & $check 'tags vacios' (ConvertFromTagsText '').Count 0
        & $check 'tags corruptos no revientan' (ConvertFromTagsText '{"a": ').Count 0
        & $check 'costo en notacion cientifica' (ConvertToCostNumber '1.5E-3') 0.0015 1e-12
        & $check 'fecha de la Cost Details API' (ConvertToUsageDate '08/31/2026').ToString('yyyy-MM-dd') '2026-08-31'
        & $check 'fecha FOCUS con zona no cambia de dia' (ConvertToUsageDate '2026-08-01T00:00:00Z').ToString('yyyy-MM-dd') '2026-08-01'
        & $check 'rg desde el id con casing de ARG' (GetResourceGroupFromId '/subscriptions/x/resourcegroups/mi-rg/providers/a/b/c') 'mi-rg'

        $periods = @(ResolvePeriod -StartDate ([datetime]'2026-06-15') -EndDate ([datetime]'2026-08-10'))
        & $check 'rango: meses cubiertos' ($periods.Month -join ',') '2026-06,2026-07,2026-08'
        & $check 'rango: mes completo sin recorte' ([bool]($periods[1].Start -or $periods[1].End)) $false
        & $check 'rango: recorte del primer mes' $periods[0].Start.ToString('yyyy-MM-dd') '2026-06-15'

        $closed = @{ downloadedAt = '2026-09-10T00:00:00Z' }
        $early = @{ downloadedAt = '2026-09-02T00:00:00Z' }
        $recent = @{ downloadedAt = [datetime]::UtcNow.AddHours(-1).ToString('o') }
        & $check 'cache: mes descargado ya cerrado es permanente' (TestCostCacheFresh $closed '2026-08') $true
        & $check 'cache: mes descargado antes de cerrar caduca' (TestCostCacheFresh $early '2026-08') $false
        & $check 'cache: mes en curso vale 24 horas' (TestCostCacheFresh $recent ([datetime]::UtcNow.ToString('yyyy-MM'))) $true
    } ${function:Check}

    # --- cache ---------------------------------------------------------------------------------
    Write-Host "`n--- Clear-KnowITAzCostsCache ---"
    Clear-KnowITAzCostsCache -SubscriptionId $sub -Month 2026-08 -WhatIf *>$null
    Check '-WhatIf no borra' (Test-Path (Join-Path $cacheRoot "$sub/cost-actualcost-2026-08.json")) $true
    Clear-KnowITAzCostsCache -SubscriptionId $sub -Month 2026-08 -Confirm:$false
    Check '-Month borra el detalle de ese mes, de todas las metricas' @(Get-ChildItem (Join-Path $cacheRoot $sub) -Filter 'cost-*-2026-08*').Count 0
    Check '-Month no toca el inventario ni otros meses' @(Get-ChildItem (Join-Path $cacheRoot $sub)).Count 2
    Clear-KnowITAzCostsCache -Confirm:$false
    Check 'sin parametros borra todo' @(Get-ChildItem $cacheRoot).Count 0
}
finally {
    Remove-Item $cacheRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ("`n" + '=' * 60)
if($script:Failures.Count) {
    Write-Host "FALLARON $($script:Failures.Count) verificaciones:" -ForegroundColor Red
    $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host 'Todas las verificaciones pasaron.' -ForegroundColor Green
