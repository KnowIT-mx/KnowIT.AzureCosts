#requires -Modules ImportExcel

$script:Xl = @{
    Azul        = [System.Drawing.Color]::FromArgb(0x1F, 0x38, 0x64)
    Rojo        = [System.Drawing.Color]::FromArgb(0xC0, 0x00, 0x00)
    Verde       = [System.Drawing.Color]::FromArgb(0x2E, 0x7D, 0x32)
    Gris        = [System.Drawing.Color]::FromArgb(0x6B, 0x72, 0x80)
    Blanco      = [System.Drawing.Color]::White
    Editable    = [System.Drawing.Color]::FromArgb(0xFF, 0xF2, 0xCC)
    FmtMoneda   = '#,##0.00'
    FmtPct      = '0.0%'
    # Tope de filas por hoja: el xlsx lo abre gente de finanzas en Excel, no un pipeline.
    MaxFilas    = 200000
}

function SetXlCell
{
    param(
        $Sheet, [int]$Row, [int]$Column, $Value,
        [string]$Format, $Color, [switch]$Bold, [switch]$Italic, [int]$Size
    )
    $celda = $Sheet.Cells[$Row, $Column]
    # EPPlus recibe el objeto base: un PSObject envuelto terminaria como texto.
    $celda.Value = switch ($Value) {
        { $null -eq $_ } { $null; break }
        { $_ -is [ValueType] -and $_ -isnot [bool] } { [double]$_; break }
        default { [string]$_ }
    }
    if($Format) { $celda.Style.Numberformat.Format = $Format }
    if($Color) { $celda.Style.Font.Color.SetColor($Color) }
    if($Bold) { $celda.Style.Font.Bold = $true }
    if($Italic) { $celda.Style.Font.Italic = $true }
    if($Size) { $celda.Style.Font.Size = $Size }
}

function SetXlNote ($Sheet, [int]$Row, [string]$Text, [int]$ToColumn = 0)
{
    # Texto explicativo en gris; opcionalmente combinado hasta $ToColumn.
    SetXlCell $Sheet $Row 1 $Text -Color $script:Xl.Gris -Italic
    if($ToColumn -gt 1) {
        $Sheet.Cells[$Row, 1, $Row, $ToColumn].Merge = $true
    }
}

function SetXlHeaders ($Sheet, [string[]]$Columns, [int]$Row = 1)
{
    for($i = 0; $i -lt $Columns.Count; $i++) {
        $celda = $Sheet.Cells[$Row, ($i + 1)]
        $celda.Value = $Columns[$i]
        $celda.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
        $celda.Style.Fill.BackgroundColor.SetColor($script:Xl.Azul)
        $celda.Style.Font.Color.SetColor($script:Xl.Blanco)
        $celda.Style.Font.Bold = $true
    }
}

function CompleteXlSheet ($Sheet, [int]$LastRow, [int]$Columns, [int]$HeaderRow = 1)
{
    # Autofiltro, panel congelado y anchos acotados.
    if($LastRow -gt $HeaderRow) {
        $Sheet.Cells[$HeaderRow, 1, $LastRow, $Columns].AutoFilter = $true
    }
    $Sheet.View.FreezePanes($HeaderRow + 1, 1)
    SetXlWidths $Sheet $LastRow $Columns
}

function SetXlWidths ($Sheet, [int]$LastRow, [int]$Columns)
{
    # Ajuste por contenido, acotado entre 10 y 60: los ResourceId son larguisimos.
    # AutoFitColumns de EPPlus depende de GDI+, que no siempre existe en Linux.
    for($c = 1; $c -le $Columns; $c++) {
        $mayor = 0
        for($r = 1; $r -le $LastRow; $r++) {
            $valor = $Sheet.Cells[$r, $c].Value
            if($null -ne $valor) { $mayor = [math]::Max($mayor, "$valor".Length) }
        }
        $Sheet.Column($c).Width = [math]::Clamp($mayor + 2, 10, 60)
    }
}

function FormatTagsText ([hashtable]$Tags)
{
    if(!$Tags -or !$Tags.Count) { return '' }
    (@($Tags.Keys | Sort-Object -CaseSensitive) | ForEach-Object { "$_=$($Tags[$_])" }) -join '; '
}

function NewXlPackage ([string]$Path)
{
    # Open-ExcelPackage -Create abriria el archivo existente en vez de reemplazarlo.
    if(Test-Path $Path) { Remove-Item $Path -Force }
    Open-ExcelPackage -Path $Path -Create
}
