function GetTagSuggestions ([object[]]$Inventory, [string[]]$RequiredTags)
{
    # "<rg>|<tag>" -> valor mas comun entre los recursos del RG que si lo tienen. Solo se
    # sugiere cuando un valor domina (>= 60%): un RG mezclado no da una pista confiable.
    $conteo = @{}
    foreach($r in $Inventory) {
        foreach($t in $RequiredTags) {
            if(TestTagValue $r.Tags $t) {
                $clave = "$($r.ResourceGroup.ToLowerInvariant())|$t"
                $conteo[$clave] ??= @{}
                $conteo[$clave][$r.Tags[$t]] = ($conteo[$clave][$r.Tags[$t]] ?? 0) + 1
            }
        }
    }
    $sugerido = @{}
    foreach($clave in $conteo.Keys) {
        $valores = $conteo[$clave]
        $top = $valores.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
        $total = ($valores.Values | Measure-Object -Sum).Sum
        if($top.Value / $total -ge 0.6) { $sugerido[$clave] = $top.Key }
    }
    $sugerido
}

function ExportTagTemplateWorkbook
{
    param(
        [string]$Path, [object[]]$Inventory, [string[]]$RequiredTags,
        [object[]]$WithCost, [object[]]$WithoutCost, [int]$Omitted, [int]$AlreadyFixed,
        [string]$SubscriptionId, [string]$Currency
    )

    $sugerido = GetTagSuggestions $Inventory $RequiredTags
    # Valores ya en uso: alimentan las listas desplegables, para no crear variantes
    # (Production vs Prod).
    $enUso = [ordered]@{}
    foreach($t in $RequiredTags) {
        $enUso[$t] = @(SortOrdinal @($Inventory | Where-Object { TestTagValue $_.Tags $t } |
            ForEach-Object { $_.Tags[$t] } | Select-Object -Unique -CaseInsensitive:$false))
    }

    $pkg = NewXlPackage $Path
    try {
        AddSheetInstrucciones $pkg $RequiredTags $SubscriptionId $WithCost.Count $WithoutCost.Count $Omitted $AlreadyFixed $Currency
        AddSheetRecursosPorEtiquetar $pkg 'Con costo' $WithCost $RequiredTags $sugerido $enUso $Currency
        AddSheetRecursosPorEtiquetar $pkg 'Sin costo' $WithoutCost $RequiredTags $sugerido $enUso $Currency

        $ws = $pkg.Workbook.Worksheets.Add('Valores')
        for($i = 0; $i -lt $RequiredTags.Count; $i++) {
            SetXlCell $ws 1 ($i + 1) $RequiredTags[$i] -Bold
            $valores = $enUso[$RequiredTags[$i]]
            for($j = 0; $j -lt $valores.Count; $j++) {
                SetXlCell $ws ($j + 2) ($i + 1) $valores[$j]
            }
        }
        $ws.Hidden = [OfficeOpenXml.eWorkSheetHidden]::Hidden
    }
    finally {
        Close-ExcelPackage $pkg
    }
}

function AddSheetInstrucciones ($Package, [string[]]$RequiredTags, [string]$SubscriptionId, [int]$ConCosto, [int]$SinCosto, [int]$Omitidos, [int]$YaCorregidos, [string]$Moneda)
{
    $ws = $Package.Workbook.Worksheets.Add('Instrucciones')
    $lineas = @(
        , @('Etiquetas pendientes', 'titulo')
        , @("Suscripcion $SubscriptionId. Generado $(Get-Date -Format 'yyyy-MM-dd').", 'tenue')
        , @('', $null)
        , @('Como llenarlo', 'negrita')
        , @("1. Llena las columnas amarillas ($($RequiredTags -join ', ')). Las que ya traen valor son los tags actuales; puedes corregirlas.", $null)
        , @("2. La columna 'Sugerido por RG' es lo que usan los demas recursos del mismo resource group. Es una pista, no se aplica sola: copiala si aplica.", $null)
        , @('3. Las listas desplegables traen los valores que ya existen. Prefierelos para no crear variantes (Production vs Prod). Se permite escribir otro.', $null)
        , @('4. Deja vacia una celda si no sabes el valor: no se toca ese tag.', $null)
        , @('5. No borres, reordenes ni renombres columnas. ResourceId identifica el recurso.', $null)
        , @('', $null)
        , @('Que contiene', 'negrita')
        , @("Con costo: $ConCosto recursos que generaron costo y les falta algun tag. Ordenados por costo ($Moneda): empieza por arriba.", $null)
        , @("Sin costo: $SinCosto recursos de primer nivel sin costo en el mes.", $null)
        , @("Omitidos: $Omitidos sub-recursos (versiones de template specs, extensiones de VM, bases de Arc, runbooks...). Rara vez se etiquetan y no afectan el reporte de costos.", 'tenue')
        , @('No se incluyen recursos borrados: tienen costo en el mes pero ya no se pueden etiquetar.', 'tenue')
        , @("Tampoco $YaCorregidos recursos que no tenian tags en el mes pero hoy ya los tienen completos.", 'tenue')
    )
    for($i = 0; $i -lt $lineas.Count; $i++) {
        $texto, $estilo = $lineas[$i]
        switch ($estilo) {
            'titulo' { SetXlCell $ws ($i + 1) 1 $texto -Bold -Size 14 }
            'negrita' { SetXlCell $ws ($i + 1) 1 $texto -Bold }
            'tenue' { SetXlCell $ws ($i + 1) 1 $texto -Color $script:Xl.Gris -Italic }
            default { SetXlCell $ws ($i + 1) 1 $texto }
        }
    }
    $ws.Column(1).Width = 120
}

function AddSheetRecursosPorEtiquetar ($Package, [string]$Nombre, [object[]]$Items, [string[]]$RequiredTags, [hashtable]$Sugerido, $EnUso, [string]$Moneda)
{
    $ws = $Package.Workbook.Worksheets.Add($Nombre)
    $cols = @('Resource group', 'Recurso', 'Tipo', "Costo del mes ($Moneda)") + $RequiredTags + @('Sugerido por RG', 'ResourceId')
    SetXlHeaders $ws $cols
    $primeraTag = 5

    $fila = 2
    foreach($item in $Items) {
        $r = $item.Recurso
        SetXlCell $ws $fila 1 $r.ResourceGroup
        SetXlCell $ws $fila 2 $r.Name
        SetXlCell $ws $fila 3 $r.Type
        if($null -ne $item.Costo) {
            SetXlCell $ws $fila 4 ([math]::Round($item.Costo, 2)) -Format '#,##0.00'
        }
        $pistas = [System.Collections.Generic.List[string]]::new()
        for($j = 0; $j -lt $RequiredTags.Count; $j++) {
            $t = $RequiredTags[$j]
            $actual = (TestTagValue $r.Tags $t) ? $r.Tags[$t] : $null
            SetXlCell $ws $fila ($primeraTag + $j) $actual
            $celda = $ws.Cells[$fila, ($primeraTag + $j)]
            $celda.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            $celda.Style.Fill.BackgroundColor.SetColor($script:Xl.Editable)
            $s = $Sugerido["$($r.ResourceGroup.ToLowerInvariant())|$t"]
            if($s -and !$actual) { $pistas.Add("$t=$s") }
        }
        SetXlCell $ws $fila ($primeraTag + $RequiredTags.Count) ($pistas -join ', ') -Color $script:Xl.Gris -Italic
        SetXlCell $ws $fila ($primeraTag + $RequiredTags.Count + 1) $r.IdNorm -Color $script:Xl.Gris -Italic
        $fila++
    }

    $ultima = [math]::Max(2, $Items.Count + 1)
    for($j = 0; $j -lt $RequiredTags.Count; $j++) {
        $t = $RequiredTags[$j]
        $colValores = [OfficeOpenXml.ExcelCellAddress]::GetColumnLetter($j + 1)
        $colTag = [OfficeOpenXml.ExcelCellAddress]::GetColumnLetter($primeraTag + $j)
        $dv = $ws.DataValidations.AddListValidation("${colTag}2:${colTag}$ultima")
        $dv.Formula.ExcelFormula = "Valores!`$$colValores`$2:`$$colValores`$$([math]::Max(2, $EnUso[$t].Count + 1))"
        $dv.AllowBlank = $true
        # Advertencia y no error: un valor nuevo puede ser legitimo.
        $dv.ErrorStyle = [OfficeOpenXml.DataValidation.ExcelDataValidationWarningStyle]::warning
        $dv.ShowErrorMessage = $true
        $dv.ErrorTitle = 'Valor nuevo'
        $dv.Error = "'$t' no tiene este valor en ningun recurso todavia. ¿Seguro?"
    }

    $anchos = @(26, 34, 42, 16) + (@(16) * $RequiredTags.Count) + @(40, 60)
    for($i = 0; $i -lt $anchos.Count; $i++) { $ws.Column($i + 1).Width = $anchos[$i] }
    $ws.View.FreezePanes(2, 3)
    $ws.Cells[1, 1, $ultima, $cols.Count].AutoFilter = $true
}
