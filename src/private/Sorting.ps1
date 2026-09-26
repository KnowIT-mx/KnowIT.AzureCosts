function SortOrdinal
{
    # Orden estable por comparacion ordinal. Sort-Object usa reglas de la cultura y ordena
    # distinto ('_' antes que los digitos), lo que cambiaria el orden de filas entre
    # maquinas con distinta configuracion regional.
    param([object[]]$Items, [scriptblock]$Key = { $_ })

    $pares = [Tuple[string, int][]]::new($Items.Count)
    for($i = 0; $i -lt $Items.Count; $i++) {
        $_ = $Items[$i]
        $pares[$i] = [Tuple]::Create([string](& $Key), $i)
    }
    [Array]::Sort($pares, [Comparison[Tuple[string, int]]] {
        param($a, $b)
        $c = [string]::CompareOrdinal($a.Item1, $b.Item1)
        $c ? $c : $a.Item2.CompareTo($b.Item2)
    })
    foreach($p in $pares) { $Items[$p.Item2] }
}
