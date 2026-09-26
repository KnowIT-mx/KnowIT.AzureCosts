#region === .Source files ===
$moduleData = Get-KnowITModuleInfo (Split-Path $PSScriptRoot)
$sourceFolders = $moduleData.PSSourceFiles.ForEach({ Join-Path $PSScriptRoot $_ })
foreach($scriptFile in Get-ChildItem $sourceFolders -Filter '*.ps1' -Recurse) {
    Write-Debug "Dot sourcing file: $scriptFile..."
    . $scriptFile.FullName
}
#endregion

#region === Module initialization ===

$script:ArmEndpoint = 'https://management.azure.com'

# EPPlus 5+ exige licencia comercial y el xlsx es un entregable para terceros. ImportExcel
# 7.x trae EPPlus 4.5 (LGPL); se revisa la version de EPPlus cargada y no la de ImportExcel
# porque lo que importa es la licencia de la libreria que escribe el archivo.
$epplus = [AppDomain]::CurrentDomain.GetAssemblies().Where({ $_.GetName().Name -eq 'EPPlus' }, 'First')
if($epplus -and $epplus[0].GetName().Version.Major -ge 5) {
    throw ("ImportExcel cargo EPPlus $($epplus[0].GetName().Version), que requiere licencia comercial. " +
        'Instala ImportExcel 7.x (EPPlus 4.5, LGPL): Install-PSResource ImportExcel -Version "[7.8,8.0)"')
}

#endregion
