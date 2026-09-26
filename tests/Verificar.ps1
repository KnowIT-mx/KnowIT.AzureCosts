#requires -Modules KnowIT.Builder, Az.Accounts, ImportExcel
<#
    Verifica las cifras del analisis contra datos sinteticos con resultado conocido.
    No basta con que el modulo corra: los numeros tienen que ser los correctos.

    Los esperados se validaron de forma independiente, y el modulo produjo el mismo reporte
    celda por celda que esa validacion sobre datos reales.

        pwsh ./tests/Verificar.ps1
#>

$ErrorActionPreference = 'Stop'
Import-Module $PSScriptRoot/../src/KnowIT.AzureCosts.psm1 -Force -DisableNameChecking

$datos = Join-Path $PSScriptRoot 'datos'
$req = 'CostCenter', 'Owner', 'Environment'
$script:fallos = [System.Collections.Generic.List[string]]::new()

function Check ([string]$Nombre, $Obtenido, $Esperado, [double]$Tolerancia = 0)
{
    $ok = ($Esperado -is [ValueType] -and $Esperado -isnot [bool]) ?
        ([math]::Abs([double]$Obtenido - [double]$Esperado) -le $Tolerancia) :
        ("$Obtenido" -ceq "$Esperado")
    $marca = $ok ? 'OK   ' : 'FALLA'
    Write-Host "  $marca $Nombre`: $Obtenido$($ok ? '' : "  (esperado $Esperado)")" -ForegroundColor ($ok ? 'Gray' : 'Red')
    if(!$ok) { $script:fallos.Add($Nombre) }
}

function Analizar ([string[]]$Csv, [object[]]$Inventario, [string[]]$Tags = $req)
{
    & (Get-Module KnowIT.AzureCosts) {
        param($Csv, $Inventario, $Tags)
        $d = ReadCostRows $Csv
        InvokeCostAnalysis -Month '2026-08' -Rows $d.Filas -Headers $d.Encabezados -Inventory $Inventario -RequiredTags $Tags
    } $Csv $Inventario $Tags
}

function NuevoCsv ([object[]]$Filas)
{
    $ruta = Join-Path ([IO.Path]::GetTempPath()) "verificar-$([guid]::NewGuid()).csv"
    $Filas | Export-Csv $ruta -NoTypeInformation -Encoding utf8
    $ruta
}

$inventario = @(Get-ResourceInventory -Path (Join-Path $datos 'inventario.json'))

# --- inventario guardado como arreglo simple -----------------------------------------------
Write-Host "`n--- inventario como arreglo simple ---"
$ruta = Join-Path ([IO.Path]::GetTempPath()) "verificar-$([guid]::NewGuid()).json"
$inventario | Select-Object Id, Name, Type, ResourceGroup, Location, Tags | ConvertTo-Json -Depth 4 | Set-Content $ruta
$arreglo = @(Get-ResourceInventory -Path $ruta)
Remove-Item $ruta
Check 'mismos recursos' $arreglo.Count $inventario.Count
Check 'conserva los ResourceId' (@($arreglo | Where-Object { !$_.Id }).Count) 0
Check 'conserva los tags' (($arreglo | ForEach-Object { $_.Tags.Count } | Measure-Object -Sum).Sum) (($inventario | ForEach-Object { $_.Tags.Count } | Measure-Object -Sum).Sum)

# --- esquemas completos ------------------------------------------------------------------
$casos = @(
    @{ Nombre = 'legacy (ActualCost)'; Csv = 'costos-legacy.csv'; Costo = 'CostInBillingCurrency'; RG = 'ResourceGroup'
        Filas = 312; ConCargo = 12; SinEtiquetar = 7; SinArm = 3; Total = 1599.16; TotalSin = 1139.33 }
    @{ Nombre = 'focus (FocusCost)'; Csv = 'costos-focus.csv'; Costo = 'EffectiveCost'; RG = 'x_ResourceGroupName'
        Filas = 310; ConCargo = 10; SinEtiquetar = 5; SinArm = 1; Total = 1453.66; TotalSin = 993.83 }
)
foreach($c in $casos) {
    Write-Host "`n--- $($c.Nombre) ---"
    $a = Analizar (Join-Path $datos $c.Csv) $inventario
    $d = $a.Diagnostico
    Check 'columna de costo elegida' $d.ColumnaCosto $c.Costo
    Check 'columna de resource group' $d.ColumnaRG $c.RG
    Check 'filas leidas' $d.FilasLeidas $c.Filas
    Check 'recursos distintos con cargo' $d.RecursosConCargo $c.ConCargo
    Check 'recursos en inventario' $d.RecursosEnArg 13
    Check 'cruzaron con Resource Graph' $d.CruzadosOk 9
    Check 'sin etiquetar con costo' $a.Resumen.RecursosSinEtiquetar $c.SinEtiquetar
    Check 'sin etiquetar sin costo' $a.Resumen.InventarioSinEtiquetarSinCosto 3
    Check 'cargos sin recurso ARM' $a.Resumen.CargosSinRecursoArm $c.SinArm
    Check 'costo total' $a.Resumen.CostoTotal $c.Total 0.01
    Check 'costo sin etiquetar' $a.Resumen.CostoSinEtiquetar $c.TotalSin 0.01

    # Casos puntuales que suelen fallar en silencio
    $staging = $a.PorRecurso | Where-Object ResourceId -like '*sql-erp-staging*'
    Check 'tag con valor vacio cuenta como faltante' ([bool]($staging -and 'Owner' -in $staging.TagsFaltantes)) $true
    $nic = $a.PorRecurso | Where-Object ResourceId -like '*nic-app-01*'
    Check "recurso con costo 0 fuera de 'sin etiquetar con costo'" ([bool]($nic -and $nic.ResourceId -notin $a.SinEtiquetarConCosto.ResourceId)) $true
    $vm = $a.PorRecurso | Where-Object ResourceId -like '*vm-app-01*'
    Check 'cruce por casing distinto resolvio el nombre desde ARG' ([bool]($vm.ExisteEnArg -and $vm.ResourceGroup -ceq 'rg-prod-app')) $true
    Check 'tags conservados pese a filas vacias a mitad de mes' $vm.Tags['Owner'] 'pepe'
}

# --- parseo --------------------------------------------------------------------------------
Write-Host "`n--- parseo de tags ---"
& (Get-Module KnowIT.AzureCosts) {
    param($check)
    & $check 'legacy sin llaves' ((ConvertFromTagsText '"Owner": "pepe", "Env": "prod"').Env) 'prod'
    & $check 'focus con llaves' ((ConvertFromTagsText '{"Owner":"pepe"}').Owner) 'pepe'
    & $check 'vacio' (ConvertFromTagsText '').Count 0
    & $check 'corrupto no revienta' (ConvertFromTagsText '{"a": ').Count 0
    & $check 'costo en notacion cientifica' (ConvertToCostNumber '1.5E-3') 0.0015 1e-12
    & $check 'extraccion de rg con casing de ARG' (GetResourceGroupFromId '/subscriptions/x/resourcegroups/mi-rg/providers/a/b/c') 'mi-rg'
} ${function:Check}

# --- sub-recursos sumados al padre ---------------------------------------------------------
Write-Host "`n--- sub-recursos sumados al padre ---"
$fac = '/subscriptions/x/resourceGroups/RG-DWH/providers/Microsoft.DataFactory/factories/adf-1'
$facSinArg = '/subscriptions/x/resourceGroups/RG-DWH/providers/Microsoft.DataFactory/factories/adf-borrada'
$db = '/subscriptions/x/resourceGroups/RG-DWH/providers/Microsoft.Sql/servers/srv/databases/temp-01'
$tagsFac = '{"Environment":"Prod","Owner":"dwh","CostCenter":"100"}'
$csv = NuevoCsv @(
    # El hijo aparece antes que el padre y con tags distintos: el padre debe ganar.
    [PSCustomObject]@{ ResourceId = "$fac/pipelines/Carga Full"; ResourceName = 'Carga Full'; CostInBillingCurrency = '10'; Tags = '{"Environment":"Otro"}' }
    [PSCustomObject]@{ ResourceId = $fac; ResourceName = 'adf-1'; CostInBillingCurrency = '1'; Tags = $tagsFac }
    [PSCustomObject]@{ ResourceId = "$fac/triggers/diario"; ResourceName = 'diario'; CostInBillingCurrency = '2'; Tags = '' }
    [PSCustomObject]@{ ResourceId = "$facSinArg/pipelines/p1"; ResourceName = 'p1'; CostInBillingCurrency = '5'; Tags = $tagsFac }
    [PSCustomObject]@{ ResourceId = $db; ResourceName = 'temp-01'; CostInBillingCurrency = '7'; Tags = '' }
)
$inv = & (Get-Module KnowIT.AzureCosts) {
    NewResourceItem -Id $args[0] -Name 'adf-1' -Type 'microsoft.datafactory/factories' -ResourceGroup 'rg-dwh' -Location 'eastus'
    NewResourceItem -Id '/subscriptions/x/resourcegroups/rg-dwh/providers/microsoft.sql/servers/srv' -Name 'srv' -Type 'microsoft.sql/servers' -ResourceGroup 'rg-dwh' -Location 'eastus'
} $fac
$a = Analizar $csv $inv
Remove-Item $csv
$porId = @{}; foreach($r in $a.PorRecurso) { $porId[$r.ResourceId] = $r }
$f = $porId[$fac.ToLowerInvariant()]
$g = $porId[$facSinArg.ToLowerInvariant()]
Check 'pipeline y trigger sumados al costo de la factory' $f.Costo 13.0
Check 'la factory conserva sus propios tags' $f.Tags['Environment'] 'Prod'
Check 'la factory cuenta como etiquetada' $f.Etiquetado $true
Check 'ningun pipeline queda como recurso propio' ([bool]($porId.Keys | Where-Object { $_ -match '/(pipelines|triggers)/' })) $false
Check 'factory sin ARG toma nombre del id, no del pipeline' $g.Nombre 'adf-borrada'
Check 'factory sin ARG ni filas propias hereda tags de sus hijos' $g.Etiquetado $true
Check 'base SQL borrada NO se suma a su servidor' $porId.ContainsKey($db.ToLowerInvariant()) $true
Check 'sub-recursos contados en el diagnostico' $a.Diagnostico.SubrecursosAlPadre 3
Check 'costo de sub-recursos en el diagnostico' $a.Diagnostico.CostoSubrecursosAlPadre 17.0
Check 'el total no cambia' $a.Resumen.CostoTotal 25.0

# --- resource group con casing distinto ----------------------------------------------------
Write-Host "`n--- resource group con casing distinto ---"
$csv = NuevoCsv @(
    [PSCustomObject]@{ ResourceId = '/subscriptions/x/resourceGroups/RG-APP/providers/Microsoft.Web/sites/borrado'; ResourceGroup = 'RG-APP'; CostInBillingCurrency = '4'; Tags = '' }
    [PSCustomObject]@{ ResourceId = '/subscriptions/x/resourceGroups/rg-app/providers/Microsoft.Web/sites/vivo'; ResourceGroup = 'rg-app'; CostInBillingCurrency = '6'; Tags = '' }
)
$a = Analizar $csv @()
Remove-Item $csv
Check 'un solo grupo pese al casing' @($a.PorResourceGroup).Count 1
Check 'costo del grupo' $a.PorResourceGroup[0].Costo 10.0

Write-Host ("`n" + '=' * 60)
if($script:fallos.Count) {
    Write-Host "FALLARON $($script:fallos.Count) verificaciones:" -ForegroundColor Red
    $script:fallos | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host 'Todas las verificaciones pasaron.' -ForegroundColor Green
