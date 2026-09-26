function SortOrdinal
{
    # Orden estable por comparacion ordinal. Sort-Object usa reglas de la cultura y ordena
    # distinto ('_' antes que los digitos), lo que cambiaria el orden de filas entre
    # maquinas con distinta configuracion regional.
    param([object[]]$Items, [scriptblock]$Key = { $_ })

    $pairs = [Tuple[string, int][]]::new($Items.Count)
    for($i = 0; $i -lt $Items.Count; $i++) {
        $_ = $Items[$i]
        $pairs[$i] = [Tuple]::Create([string](& $Key), $i)
    }
    [Array]::Sort($pairs, [Comparison[Tuple[string, int]]] {
        param($a, $b)
        $result = [string]::CompareOrdinal($a.Item1, $b.Item1)
        $result ? $result : $a.Item2.CompareTo($b.Item2)
    })
    foreach($pair in $pairs) { $Items[$pair.Item2] }
}
