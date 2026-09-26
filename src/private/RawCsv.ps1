function WriteRawCsv
{
    # Mismo formato que Export-Csv de PowerShell 7 (todos los campos entre comillas, UTF-8 sin
    # BOM), pero escribiendo directo: un mes de una suscripcion grande son decenas de miles de
    # filas con ~60 columnas, y crear un PSCustomObject por fila lo hace varias veces mas lento.
    param(
        [string]$Path,
        [string[]]$Headers,
        [object[]]$TagColumns,
        [System.Collections.Generic.List[object]]$Items
    )

    # foreach y no pipeline: $null | ForEach-Object corre una vez y agregaria una columna nula
    # cuando no hay tags que exportar.
    $tagNames = @(foreach($column in $TagColumns) { $column.Tag })
    $fields = [string[]]::new($Headers.Count + $tagNames.Count)

    $writer = [IO.StreamWriter]::new($Path, $false, [Text.UTF8Encoding]::new($false))
    try {
        $columnNames = @($Headers) + @(foreach($column in $TagColumns) { $column.Column })
        $writer.WriteLine((ConvertToCsvLine $columnNames))

        foreach($item in $Items) {
            $row = $item.Row
            $tags = $item.Tags
            $i = 0
            foreach($header in $Headers) { $fields[$i++] = "$($row.$header)" }
            foreach($tag in $tagNames) { $fields[$i++] = "$($tags[$tag])" }
            $writer.WriteLine((ConvertToCsvLine $fields))
        }
    }
    finally {
        $writer.Dispose()
    }
}

function ConvertToCsvLine ([string[]]$Fields)
{
    '"' + [string]::Join('","', [string[]]$Fields.ForEach({ $_.Replace('"', '""') })) + '"'
}
