function ExportCostReportWorkbook ($Analysis, [string]$Path, [string]$SubscriptionId)
{
    $pkg = NewXlPackage $Path
    try {
        AddSheetResumen $pkg $Analysis $SubscriptionId
        AddSheetDiagnostico $pkg $Analysis
        AddSheetSinEtiquetar $pkg $Analysis
        AddSheetPorRg $pkg $Analysis
        AddSheetCobertura $pkg $Analysis
        AddSheetPorRecurso $pkg $Analysis
        AddSheetInventario $pkg $Analysis
        AddSheetSinArm $pkg $Analysis
    }
    finally {
        Close-ExcelPackage $pkg
    }
}

function AddSheetResumen ($Package, $Analysis, [string]$SubscriptionId)
{
    $ws = $Package.Workbook.Worksheets.Add('Resumen')
    $r = $Analysis.Resumen
    $m = $r.Moneda

    SetXlCell $ws 1 1 'Reporte de costos y etiquetado' -Bold -Size 16
    $origen = $SubscriptionId ? "Suscripcion $SubscriptionId" : 'Suscripcion no indicada'
    SetXlCell $ws 2 1 "Periodo: $($r.Mes)    ·    $origen" -Color $script:Xl.Gris -Italic

    # Obligatorio: sin este aviso finanzas compara contra la factura y concluye que el reporte
    # esta mal. Es generico porque la diferencia depende del contrato (en CSP son precios
    # retail sin descuentos del partner) y el modulo no lo puede saber desde el CSV.
    SetXlCell $ws 4 1 'Advertencia' -Bold
    SetXlCell $ws 5 1 ('Los montos son el costo de consumo que reporta Azure Cost Management y pueden ' +
        'no coincidir con la factura: segun el tipo de contrato no incluyen descuentos, creditos, ' +
        'impuestos ni ajustes. Sirven para proporcion, tendencia y atribucion por etiqueta.')
    $ws.Cells['A5:D5'].Merge = $true
    $ws.Cells['A5'].Style.WrapText = $true
    $ws.Cells['A5'].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Top
    $ws.Row(5).Height = 45

    $fila = 7
    # $null deja un renglon en blanco entre grupos.
    $kpis = @(
        , @("Costo total ($m)", $r.CostoTotal, $script:Xl.FmtMoneda, $null)
        , @("Costo sin etiquetar ($m)", $r.CostoSinEtiquetar, $script:Xl.FmtMoneda, $script:Xl.Rojo)
        , @('% del costo sin etiquetar', $r.PctSinEtiquetar, '0.00%', ($r.PctSinEtiquetar -gt 0.10 ? $script:Xl.Rojo : $script:Xl.Verde))
        , $null
        , @('Recursos con cargo', $r.RecursosConCargo, $null, $null)
        , @('Recursos con cargo sin etiquetar', $r.RecursosSinEtiquetar, $null, $script:Xl.Rojo)
        , @('Recursos sin etiquetar y sin cargo', $r.InventarioSinEtiquetarSinCosto, $null, $null)
        , @('Cargos sin recurso ARM vigente', $r.CargosSinRecursoArm, $null, $null)
        , $null
        , @('Tags evaluados', ($Analysis.TagsRequeridos -join ', '), $null, $null)
    )
    foreach($k in $kpis) {
        if($k) {
            SetXlCell $ws $fila 1 $k[0] -Bold
            SetXlCell $ws $fila 2 $k[1] -Format $k[2] -Color $k[3]
        }
        $fila++
    }

    $fila += 2
    SetXlCell $ws $fila 1 'Top 10 resource groups por costo' -Bold
    $fila++
    SetXlHeaders $ws @('Resource group', "Costo ($m)", 'Sin etiquetar', '% sin etiquetar') $fila
    $fila++
    foreach($g in @($Analysis.PorResourceGroup | Select-Object -First 10)) {
        $pct = $g.Costo ? $g.CostoSinEtiquetar / $g.Costo : 0.0
        SetXlCell $ws $fila 1 $g.ResourceGroup
        SetXlCell $ws $fila 2 $g.Costo -Format $script:Xl.FmtMoneda
        SetXlCell $ws $fila 3 $g.CostoSinEtiquetar -Format $script:Xl.FmtMoneda
        SetXlCell $ws $fila 4 $pct -Format $script:Xl.FmtPct -Color ($pct -gt 0.10 ? $script:Xl.Rojo : $null)
        $fila++
    }

    $ws.Column(1).Width = 46; $ws.Column(2).Width = 20; $ws.Column(3).Width = 18; $ws.Column(4).Width = 16
}

function AddSheetDiagnostico ($Package, $Analysis)
{
    # Responde: los datos traen lo que el reporte necesita, y que etiquetas existen de verdad.
    $ws = $Package.Workbook.Worksheets.Add('Diagnostico')
    $d = $Analysis.Diagnostico
    $m = $Analysis.Moneda

    SetXlCell $ws 1 1 'Diagnostico de la extraccion' -Bold -Size 16
    SetXlCell $ws 2 1 'Usa esta hoja para validar los datos y decidir que tags exigir.' -Color $script:Xl.Gris -Italic

    $fila = 4
    if($d.Advertencias.Count) {
        SetXlCell $ws $fila 1 'ADVERTENCIAS' -Bold -Color $script:Xl.Rojo
        $fila++
        foreach($a in $d.Advertencias) {
            SetXlCell $ws $fila 1 "· $a" -Color $script:Xl.Rojo
            $ws.Cells[$fila, 1, $fila, 6].Merge = $true
            $ws.Cells[$fila, 1].Style.WrapText = $true
            $ws.Row($fila).Height = 30
            $fila++
        }
        $fila++
    }

    $secciones = [ordered]@{
        'Columnas que se eligieron' = @(
            , @('Costo', ($d.ColumnaCosto ?? 'NO ENCONTRADA'), ($d.ColumnaCosto ? $null : $script:Xl.Rojo))
            , @('Tags', ($d.ColumnaTags ?? 'NO ENCONTRADA'), ($d.ColumnaTags ? $null : $script:Xl.Rojo))
            , @('Resource group', ($d.ColumnaRG ?? '(derivado del ResourceId)'), $null)
            , @('Resource ID', ($d.ColumnaResourceId ?? 'NO ENCONTRADA'), ($d.ColumnaResourceId ? $null : $script:Xl.Rojo))
            , @('Moneda detectada', ($d.MonedaDetectada ? $d.MonedaDetectada : '(no venia en el dataset)'), $null)
        )
        'Volumen y cruce con Resource Graph' = @(
            , @('Filas leidas del detalle de costos', $d.FilasLeidas, $null)
            , @('Filas sin ResourceId', $d.FilasSinResourceId, $null)
            , @('Recursos distintos con cargo', $d.RecursosConCargo, $null)
            , @('Recursos en Resource Graph', $d.RecursosEnArg, $null)
            , @('Cruzaron correctamente', $d.CruzadosOk, ($d.CruzadosOk ? $script:Xl.Verde : $script:Xl.Rojo))
            , @('Cargos sin recurso ARM vigente', $d.SinCorrespondenciaArg, $null)
            , @('Sub-recursos sumados a su padre', $d.SubrecursosAlPadre, $null)
            , @("Costo de sub-recursos sumados ($m)", [math]::Round($d.CostoSubrecursosAlPadre, 2), $null)
        )
    }
    foreach($titulo in $secciones.Keys) {
        $fila++
        SetXlCell $ws $fila 1 $titulo -Bold -Size 12
        $fila++
        foreach($dato in $secciones[$titulo]) {
            SetXlCell $ws $fila 1 $dato[0]
            SetXlCell $ws $fila 2 $dato[1] -Color $dato[2]
            $fila++
        }
    }

    $fila++
    SetXlNote $ws $fila ("Nota: 'sin recurso ARM vigente' es normal. Son Marketplace, reservas, " +
        'soporte y recursos borrados durante el mes.') 6
    $fila += 2

    $fila++
    SetXlCell $ws $fila 1 'Etiquetas que existen hoy en la suscripcion' -Bold -Size 12
    $fila++
    SetXlNote $ws $fila 'Esto define que tags exigir en el reporte.'
    $fila++
    SetXlHeaders $ws @('Tag', 'Recursos que lo usan', "Costo asociado ($m)", '¿Esta en los requeridos?') $fila
    $fila++
    $inicio = $fila
    foreach($tag in $d.FrecuenciaTags.Keys) {
        $f = $d.FrecuenciaTags[$tag]
        $requerido = $tag -in $Analysis.TagsRequeridos
        SetXlCell $ws $fila 1 $tag
        SetXlCell $ws $fila 2 $f.Recursos
        SetXlCell $ws $fila 3 $f.Costo -Format $script:Xl.FmtMoneda
        if($requerido) {
            SetXlCell $ws $fila 4 'Si' -Color $script:Xl.Verde
        }
        else {
            SetXlCell $ws $fila 4 'No' -Color $script:Xl.Gris -Italic
        }
        $fila++
    }
    if($fila -eq $inicio) {
        SetXlCell $ws $fila 1 '(no se encontro ninguna etiqueta)' -Color $script:Xl.Rojo
        $fila++
    }

    $fila += 2
    SetXlCell $ws $fila 1 'Todas las columnas del dataset' -Bold -Size 12
    $fila++
    SetXlCell $ws $fila 1 ($d.ColumnasDisponibles -join ', ')
    $ws.Cells[$fila, 1, $fila, 8].Merge = $true
    $ws.Cells[$fila, 1].Style.WrapText = $true
    $ws.Cells[$fila, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Top
    $ws.Row($fila).Height = 120

    $ws.Column(1).Width = 44; $ws.Column(2).Width = 24; $ws.Column(3).Width = 24; $ws.Column(4).Width = 24
}

function AddSheetSinEtiquetar ($Package, $Analysis)
{
    $ws = $Package.Workbook.Worksheets.Add('Sin etiquetar (con costo)')
    $cols = 'Resource group', 'Recurso', 'Tipo', 'Servicio', 'Region', "Costo ($($Analysis.Moneda))", 'Tags faltantes', 'Tags presentes'
    SetXlHeaders $ws $cols

    $f = 2
    foreach($r in @($Analysis.SinEtiquetarConCosto | Select-Object -First $script:Xl.MaxFilas)) {
        SetXlCell $ws $f 1 $r.ResourceGroup
        SetXlCell $ws $f 2 $r.Nombre
        SetXlCell $ws $f 3 $r.Tipo
        SetXlCell $ws $f 4 $r.Servicio
        SetXlCell $ws $f 5 $r.Region
        SetXlCell $ws $f 6 $r.Costo -Format $script:Xl.FmtMoneda
        SetXlCell $ws $f 7 ($r.TagsFaltantes -join ', ') -Color $script:Xl.Rojo
        SetXlCell $ws $f 8 (FormatTagsText $r.Tags)
        $f++
    }
    CompleteXlSheet $ws ($f - 1) $cols.Count
}

function AddSheetPorRg ($Package, $Analysis)
{
    $ws = $Package.Workbook.Worksheets.Add('Costo por RG')
    $m = $Analysis.Moneda
    $cols = 'Resource group', "Costo ($m)", "Costo sin etiquetar ($m)", 'Recursos', 'Recursos sin etiquetar'
    SetXlHeaders $ws $cols

    $f = 2
    foreach($g in $Analysis.PorResourceGroup) {
        SetXlCell $ws $f 1 $g.ResourceGroup
        SetXlCell $ws $f 2 $g.Costo -Format $script:Xl.FmtMoneda
        SetXlCell $ws $f 3 $g.CostoSinEtiquetar -Format $script:Xl.FmtMoneda
        SetXlCell $ws $f 4 $g.Recursos
        SetXlCell $ws $f 5 $g.RecursosSinEtiquetar
        $f++
    }
    CompleteXlSheet $ws ($f - 1) $cols.Count
}

function AddSheetCobertura ($Package, $Analysis)
{
    $ws = $Package.Workbook.Worksheets.Add('Cobertura de tags')
    $m = $Analysis.Moneda
    $cols = 'Resource group', 'Recursos', 'Etiquetados', '% recursos', "Costo ($m)", "Costo etiquetado ($m)", '% costo'
    SetXlHeaders $ws $cols

    $f = 2
    foreach($c in $Analysis.Cobertura) {
        SetXlCell $ws $f 1 $c.ResourceGroup
        SetXlCell $ws $f 2 $c.Recursos
        SetXlCell $ws $f 3 $c.Etiquetados
        SetXlCell $ws $f 4 $c.PctRecursos -Format $script:Xl.FmtPct
        SetXlCell $ws $f 5 $c.Costo -Format $script:Xl.FmtMoneda
        SetXlCell $ws $f 6 $c.CostoEtiquetado -Format $script:Xl.FmtMoneda
        SetXlCell $ws $f 7 $c.PctCosto -Format $script:Xl.FmtPct
        $f++
    }

    if($f -gt 2) {
        # Semaforo: rojo en 0%, amarillo en 90%, verde en 100% de costo etiquetado.
        $escala = $ws.ConditionalFormatting.AddThreeColorScale([OfficeOpenXml.ExcelAddress]::new("G2:G$($f - 1)"))
        $num = [OfficeOpenXml.ConditionalFormatting.eExcelConditionalFormattingValueObjectType]::Num
        $escala.LowValue.Type = $num; $escala.LowValue.Value = 0
        $escala.LowValue.Color = [System.Drawing.Color]::FromArgb(0xF8, 0x69, 0x6B)
        $escala.MiddleValue.Type = $num; $escala.MiddleValue.Value = 0.9
        $escala.MiddleValue.Color = [System.Drawing.Color]::FromArgb(0xFF, 0xEB, 0x84)
        $escala.HighValue.Type = $num; $escala.HighValue.Value = 1
        $escala.HighValue.Color = [System.Drawing.Color]::FromArgb(0x63, 0xBE, 0x7B)
    }
    CompleteXlSheet $ws ($f - 1) $cols.Count
}

function AddSheetPorRecurso ($Package, $Analysis)
{
    $ws = $Package.Workbook.Worksheets.Add('Costo por recurso')
    $cols = @('Resource group', 'Recurso', 'Tipo', 'Servicio', 'Region', "Costo ($($Analysis.Moneda))") +
        $Analysis.TagsRequeridos + 'Etiquetado'
    SetXlHeaders $ws $cols

    $f = 2
    foreach($r in @($Analysis.PorRecurso | Select-Object -First $script:Xl.MaxFilas)) {
        SetXlCell $ws $f 1 $r.ResourceGroup
        SetXlCell $ws $f 2 $r.Nombre
        SetXlCell $ws $f 3 $r.Tipo
        SetXlCell $ws $f 4 $r.Servicio
        SetXlCell $ws $f 5 $r.Region
        SetXlCell $ws $f 6 $r.Costo -Format $script:Xl.FmtMoneda
        $c = 7
        foreach($tag in $Analysis.TagsRequeridos) {
            SetXlCell $ws $f $c ([string]$r.Tags[$tag])
            $c++
        }
        if($r.Etiquetado) { SetXlCell $ws $f $c 'Si' } else { SetXlCell $ws $f $c 'No' -Color $script:Xl.Rojo }
        $f++
    }
    CompleteXlSheet $ws ($f - 1) $cols.Count
}

function AddSheetInventario ($Package, $Analysis)
{
    $ws = $Package.Workbook.Worksheets.Add('Inventario sin etiquetar')
    SetXlNote $ws 1 ('Recursos que existen en la suscripcion, no cumplen el tagging requerido y ' +
        'no generaron cargo en el periodo. Origen: Azure Resource Graph.') 5

    $cols = 'Resource group', 'Recurso', 'Tipo', 'Ubicacion', 'Tags presentes'
    SetXlHeaders $ws $cols 2

    $f = 3
    foreach($r in @($Analysis.SinEtiquetarSinCosto | Select-Object -First $script:Xl.MaxFilas)) {
        SetXlCell $ws $f 1 $r.ResourceGroup
        SetXlCell $ws $f 2 $r.Name
        SetXlCell $ws $f 3 $r.Type
        SetXlCell $ws $f 4 $r.Location
        SetXlCell $ws $f 5 (FormatTagsText $r.Tags)
        $f++
    }
    CompleteXlSheet $ws ($f - 1) $cols.Count 2
}

function AddSheetSinArm ($Package, $Analysis)
{
    $ws = $Package.Workbook.Worksheets.Add('Cargos sin recurso ARM')
    SetXlNote $ws 1 ('Cargos que no corresponden a un recurso ARM vigente: Marketplace, reservas, ' +
        'soporte, y recursos eliminados durante el periodo. No son hallazgos de tagging, ' +
        'pero si parte del total.') 5
    $ws.Cells['A1'].Style.WrapText = $true
    $ws.Row(1).Height = 30

    $cols = 'Identificador', 'Servicio', 'Tipo', 'Resource group', "Costo ($($Analysis.Moneda))"
    SetXlHeaders $ws $cols 2

    $f = 3
    foreach($r in @($Analysis.SinRecursoArm | Select-Object -First $script:Xl.MaxFilas)) {
        SetXlCell $ws $f 1 $r.ResourceId
        SetXlCell $ws $f 2 $r.Servicio
        SetXlCell $ws $f 3 $r.Tipo
        SetXlCell $ws $f 4 $r.ResourceGroup
        SetXlCell $ws $f 5 $r.Costo -Format $script:Xl.FmtMoneda
        $f++
    }
    CompleteXlSheet $ws ($f - 1) $cols.Count 2
}
