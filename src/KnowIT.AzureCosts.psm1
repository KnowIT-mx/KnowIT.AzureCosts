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

# En el perfil del usuario, en carpeta .knowit persistiendo reinicios
# donde cada modulo KnowIT tiene su propia subcarpeta.
$script:CacheRoot = Join-Path $HOME '.knowit' 'KnowIT.AzureCosts'

#endregion
