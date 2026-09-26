function GetCostDetailOrigin ([string]$Path)
{
    # detalle-<suscripcion>-<yyyy-MM>-partN.csv, el nombre que usa Get-CostDetail.
    $nombre = Split-Path $Path -Leaf
    if($nombre -match '^detalle-(?<sub>[0-9a-fA-F-]{36})-(?<mes>\d{4}-\d{2})-part\d+\.csv$') {
        return @{ SubscriptionId = $Matches.sub; Month = $Matches.mes }
    }
    if($nombre -match '(?<mes>\d{4}-\d{2})') {
        return @{ SubscriptionId = $null; Month = $Matches.mes }
    }
    @{ SubscriptionId = $null; Month = $null }
}

function ReadCostRows ([string[]]$Path)
{
    # Devuelve @{ Filas; Encabezados }. Los encabezados salen del primer archivo: los parts
    # de un mismo reporte comparten esquema.
    $filas = [System.Collections.Generic.List[object]]::new()
    $encabezados = $null
    foreach($archivo in $Path) {
        $lote = Import-Csv -Path $archivo -Encoding utf8
        if(!$encabezados -and $lote) {
            $encabezados = @($lote[0].PSObject.Properties.Name)
        }
        foreach($f in $lote) { $filas.Add($f) }
    }
    @{ Filas = $filas; Encabezados = @($encabezados) }
}

function InvokeCostAnalysis
{
    param(
        [string]$Month,
        [System.Collections.Generic.List[object]]$Rows,
        [string[]]$Headers,
        [object[]]$Inventory,
        [string[]]$RequiredTags,
        [string]$FallbackCurrency = 'USD'
    )

    $mapa = NewColumnMap $Headers
    $col = { param($fila, $campo) $c = $mapa[$campo]; $c ? "$($fila.$c)".Trim() : '' }

    $diag = [ordered]@{
        ColumnasDisponibles     = @(SortOrdinal $Headers)
        ColumnaCosto            = $mapa.costo
        ColumnaTags             = $mapa.tags
        ColumnaRG               = $mapa.resource_group
        ColumnaResourceId       = $mapa.resource_id
        FilasLeidas             = 0
        FilasSinResourceId      = 0
        RecursosConCargo        = 0
        RecursosEnArg           = 0
        CruzadosOk              = 0
        SinCorrespondenciaArg   = 0
        SubrecursosAlPadre      = 0
        CostoSubrecursosAlPadre = 0.0
        MonedaDetectada         = ''
        FrecuenciaTags          = [ordered]@{}
        Advertencias            = [System.Collections.Generic.List[string]]::new()
    }

    if(!$mapa.costo) {
        $diag.Advertencias.Add("No se encontro ninguna columna de costo reconocible. Candidatas buscadas: $($script:CandidatasColumnas.costo -join ', ')")
    }
    if(!$mapa.tags) {
        $diag.Advertencias.Add("No hay columna 'Tags'. Todo va a aparecer como sin etiquetar.")
    }

    $porArg = @{}
    foreach($r in $Inventory) { $porArg[$r.IdNorm] = $r }
    $diag.RecursosEnArg = $porArg.Count

    # --- acumular costo por recurso ------------------------------------------------
    # Los tags se toman de la ultima fila no vacia: el export repite tags por dia y a veces
    # vienen vacios en filas de ajuste. Las llaves son ResourceId en minusculas.
    $accCosto = [ordered]@{}
    $accTags = @{}
    # Tags de sub-recursos sumados al padre: solo cuentan si el padre no trajo los suyos
    # ni esta en ARG.
    $accTagsHijos = @{}
    $accMuestra = @{}
    $muestraDeHijo = [System.Collections.Generic.HashSet[string]]::new()
    $hijosSumados = [System.Collections.Generic.HashSet[string]]::new()
    # El mismo texto de tags se repite en miles de filas: parsearlo una vez.
    $cacheTags = [System.Collections.Generic.Dictionary[string, hashtable]]::new()

    foreach($fila in $Rows) {
        $diag.FilasLeidas++

        $ridNorm = (& $col $fila 'resource_id').ToLowerInvariant()
        $padre = $ridNorm ? (GetParentResourceId $ridNorm) : $null
        $costo = ConvertToCostNumber (& $col $fila 'costo')

        if(!$ridNorm) {
            $diag.FilasSinResourceId++
            # Cargos sin ResourceId (soporte, algunos Marketplace) se agrupan bajo una clave
            # sintetica para no perderlos del total.
            $clave = "(sin resourceid)/$(& $col $fila 'servicio')/$(& $col $fila 'charge')"
        }
        elseif($padre) {
            $clave = $padre
            $null = $hijosSumados.Add($ridNorm)
            $diag.CostoSubrecursosAlPadre += $costo
        }
        else {
            $clave = $ridNorm
        }

        $accCosto[$clave] = ($accCosto[$clave] ?? 0.0) + $costo
        # La muestra da nombre y servicio cuando el recurso no esta en ARG: la del propio
        # padre gana sobre la de un hijo.
        if(!$accMuestra.ContainsKey($clave) -or (!$padre -and $muestraDeHijo.Contains($clave))) {
            $accMuestra[$clave] = $fila
            if($padre) { $null = $muestraDeHijo.Add($clave) } else { $null = $muestraDeHijo.Remove($clave) }
        }

        $textoTags = & $col $fila 'tags'
        if($textoTags) {
            if(!$cacheTags.TryGetValue($textoTags, [ref]$null)) {
                $cacheTags[$textoTags] = ConvertFromTagsText $textoTags
            }
            $tags = $cacheTags[$textoTags]
            if($tags.Count) {
                if($padre) { $accTagsHijos[$clave] = $tags } else { $accTags[$clave] = $tags }
            }
        }

        if(!$diag.MonedaDetectada) {
            $diag.MonedaDetectada = & $col $fila 'moneda'
        }
    }

    $moneda = $diag.MonedaDetectada ? $diag.MonedaDetectada : $FallbackCurrency
    $diag.SubrecursosAlPadre = $hijosSumados.Count

    # --- resolver tags efectivos y presencia en ARG ----------------------------------
    $porRecurso = [System.Collections.Generic.List[object]]::new()

    foreach($clave in $accCosto.Keys) {
        $recursoArg = $porArg[$clave]
        $muestra = $accMuestra[$clave]

        # Los tags del export ya reflejan tag inheritance si esta activa. Si el export no
        # trajo ninguno, se cae a los de ARG, que son la foto de hoy y no la del mes
        # cerrado: por eso el export manda.
        $tags = $accTags[$clave]
        if(!$tags.Count) { $tags = $recursoArg.Tags }
        if(!$tags.Count) { $tags = $accTagsHijos[$clave] }
        if(!$tags) { $tags = @{} }

        $faltantes = @($RequiredTags | Where-Object { !(TestTagValue $tags $_) })

        $nombre = $muestraDeHijo.Contains($clave) ? '' : (& $col $muestra 'resource_name')
        if(!$nombre -and $clave.StartsWith('/')) {
            $nombre = $clave.Substring($clave.LastIndexOf('/') + 1)
        }
        $rg = & $col $muestra 'resource_group'
        if(!$rg) { $rg = GetResourceGroupFromId $clave }

        $porRecurso.Add([PSCustomObject]@{
            ResourceId    = $clave
            Nombre        = $recursoArg ? $recursoArg.Name : ($nombre ? $nombre : $clave)
            Tipo          = $recursoArg ? $recursoArg.Type : (& $col $muestra 'resource_type')
            ResourceGroup = $recursoArg ? $recursoArg.ResourceGroup : $rg
            Servicio      = & $col $muestra 'servicio'
            Region        = $recursoArg ? $recursoArg.Location : (& $col $muestra 'region')
            Costo         = $accCosto[$clave]
            Tags          = $tags
            TagsFaltantes = $faltantes
            ExisteEnArg   = [bool]$recursoArg
            Etiquetado    = $faltantes.Count -eq 0
        })
    }

    $porRecurso = @($porRecurso | Sort-Object Costo -Descending -Stable)

    $diag.RecursosConCargo = $porRecurso.Count
    $diag.CruzadosOk = @($porRecurso | Where-Object ExisteEnArg).Count
    $diag.SinCorrespondenciaArg = $diag.RecursosConCargo - $diag.CruzadosOk

    if($diag.RecursosConCargo -and $diag.CruzadosOk -eq 0 -and $Inventory) {
        $diag.Advertencias.Add(
            'NINGUN recurso con cargo cruzo con Resource Graph. Suele indicar que la columna ' +
            'de ResourceId no es la esperada o que el inventario es de otra suscripcion.')
    }

    # --- frecuencia de tags ----------------------------------------------------------
    # Lo mas util del diagnostico: que etiquetas existen de verdad hoy, para decidir
    # cuales exigir.
    $cuenta = [ordered]@{}
    $costoPorTag = @{}
    foreach($r in $porRecurso) {
        foreach($k in $r.Tags.Keys) {
            if(TestTagValue $r.Tags $k) {
                $cuenta[$k] = ($cuenta[$k] ?? 0) + 1
                $costoPorTag[$k] = ($costoPorTag[$k] ?? 0.0) + $r.Costo
            }
        }
    }
    foreach($rec in $Inventory) {
        if($accCosto.Contains($rec.IdNorm)) { continue }
        foreach($k in $rec.Tags.Keys) {
            if(TestTagValue $rec.Tags $k) { $cuenta[$k] = ($cuenta[$k] ?? 0) + 1 }
        }
    }
    # Empates por numero de recursos: primero el que representa mas costo, luego por nombre.
    $porNombre = @(SortOrdinal @($cuenta.Keys))
    foreach($k in @($porNombre | Sort-Object { $cuenta[$_] }, { $costoPorTag[$_] ?? 0.0 } -Descending -Stable)) {
        $diag.FrecuenciaTags[$k] = [PSCustomObject]@{
            Recursos = $cuenta[$k]
            Costo    = [math]::Round(($costoPorTag[$k] ?? 0.0), 2)
        }
    }

    # --- cortes ------------------------------------------------------------------------
    $sinRecursoArm = @($porRecurso | Where-Object { !$_.ExisteEnArg })
    $sinEtiquetarConCosto = @($porRecurso | Where-Object { !$_.Etiquetado -and $_.Costo -gt 0 })
    $sinEtiquetarSinCosto = @(SortOrdinal @($Inventory |
        Where-Object {
            $rec = $_
            !$accCosto.Contains($rec.IdNorm) -and
            @($RequiredTags | Where-Object { !(TestTagValue $rec.Tags $_) }).Count
        }) { "$($_.ResourceGroup.ToLowerInvariant())`0$($_.Name.ToLowerInvariant())" })

    # --- por resource group --------------------------------------------------------------
    $grupos = [ordered]@{}
    foreach($r in $porRecurso) {
        $nombreRg = $r.ResourceGroup ? $r.ResourceGroup : '(sin resource group)'
        $g = $grupos[$nombreRg]
        if(!$g) {
            $g = [PSCustomObject]@{ ResourceGroup = $nombreRg; Costo = 0.0; CostoSinEtiquetar = 0.0; Recursos = 0; RecursosSinEtiquetar = 0 }
            $grupos[$nombreRg] = $g
        }
        $g.Costo += $r.Costo
        $g.Recursos++
        if(!$r.Etiquetado) {
            $g.CostoSinEtiquetar += $r.Costo
            $g.RecursosSinEtiquetar++
        }
    }
    $porRg = @($grupos.Values | Sort-Object Costo -Descending -Stable)

    $cobertura = @($porRg | ForEach-Object {
        $etiquetados = $_.Recursos - $_.RecursosSinEtiquetar
        [PSCustomObject]@{
            ResourceGroup   = $_.ResourceGroup
            Recursos        = $_.Recursos
            Etiquetados     = $etiquetados
            PctRecursos     = $_.Recursos ? $etiquetados / $_.Recursos : 0.0
            Costo           = $_.Costo
            CostoEtiquetado = $_.Costo - $_.CostoSinEtiquetar
            PctCosto        = $_.Costo ? ($_.Costo - $_.CostoSinEtiquetar) / $_.Costo : 0.0
        }
    } | Sort-Object PctCosto -Stable)

    $costoTotal = ($porRecurso | Measure-Object Costo -Sum).Sum ?? 0.0
    $costoSin = (@($porRecurso | Where-Object { !$_.Etiquetado }) | Measure-Object Costo -Sum).Sum ?? 0.0

    [PSCustomObject]@{
        Mes                  = $Month
        Moneda               = $moneda
        TagsRequeridos       = $RequiredTags
        PorRecurso           = $porRecurso
        SinEtiquetarConCosto = $sinEtiquetarConCosto
        SinEtiquetarSinCosto = $sinEtiquetarSinCosto
        SinRecursoArm        = $sinRecursoArm
        PorResourceGroup     = $porRg
        Cobertura            = $cobertura
        Resumen              = [PSCustomObject]@{
            Mes                            = $Month
            Moneda                         = $moneda
            CostoTotal                     = $costoTotal
            CostoSinEtiquetar              = $costoSin
            PctSinEtiquetar                = $costoTotal ? $costoSin / $costoTotal : 0.0
            RecursosConCargo               = $diag.CruzadosOk
            RecursosSinEtiquetar           = $sinEtiquetarConCosto.Count
            InventarioSinEtiquetarSinCosto = $sinEtiquetarSinCosto.Count
            CargosSinRecursoArm            = $sinRecursoArm.Count
        }
        Diagnostico          = [PSCustomObject]$diag
    }
}
