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

# Junto a los archivos de Az (tokens, contextos): el mismo lugar que el usuario ya asocia con
# su sesion de Azure, y persiste entre reinicios.
$script:CacheRoot = Join-Path $HOME '.Azure' 'KnowIT.AzureCosts'

#endregion
