function ResolvePeriod
{
    # Convierte -Month o -StartDate/-EndDate en la lista de meses que hay que tener en
    # cache. El cache siempre guarda meses completos; Start/End recortan despues las filas
    # cuando el rango no cubre el mes entero.
    param(
        [string[]]$Month,
        [Nullable[datetime]]$StartDate,
        [Nullable[datetime]]$EndDate
    )

    $today = [datetime]::UtcNow.Date
    $periods = [System.Collections.Generic.List[object]]::new()

    if($Month) {
        foreach($value in $Month | Select-Object -Unique) {
            $first = [datetime]::ParseExact("$value-01", 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
            $periods.Add([PSCustomObject]@{ Month = $value; First = $first; Start = $null; End = $null })
        }
    }
    else {
        $start = $StartDate.Date
        $end = $EndDate.Date
        if($start -gt $end) {
            throw "-StartDate ($($start.ToString('yyyy-MM-dd'))) es posterior a -EndDate ($($end.ToString('yyyy-MM-dd')))."
        }
        $first = [datetime]::new($start.Year, $start.Month, 1)
        while($first -le $end) {
            $last = $first.AddMonths(1).AddDays(-1)
            $periods.Add([PSCustomObject]@{
                Month = $first.ToString('yyyy-MM')
                First = $first
                # Solo se recorta si el rango no cubre el mes completo.
                Start = $start -gt $first ? $start : $null
                End   = $end -lt $last ? $end : $null
            })
            $first = $first.AddMonths(1)
        }
    }

    foreach($period in $periods) {
        if($period.First -gt $today) {
            throw "El mes $($period.Month) todavia no empieza: no hay costos que consultar."
        }
    }
    $periods
}

function TestDateInPeriod ([Nullable[datetime]]$Date, $Period)
{
    if(!$Period.Start -and !$Period.End) { return $true }
    # Sin fecha no se puede ubicar la fila: dentro de un rango recortado se descarta.
    if(!$Date) { return $false }
    if($Period.Start -and $Date -lt $Period.Start) { return $false }
    if($Period.End -and $Date -gt $Period.End) { return $false }
    return $true
}
