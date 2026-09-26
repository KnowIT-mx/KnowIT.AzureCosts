@{
    ModuleName      = 'KnowIT.AzureCosts'
    ModuleId        = 'abc91076-c63c-418c-b713-4e7ff5363fbd'
    Description     = 'Consulta y analisis de costos de Azure por recurso, resource group y tag: Cost Details API y Resource Graph con cache local'
    Author          = 'KnowIT'
    Version         = '0.2.x-beta'

    PSSourceFiles   = 'public', 'private'
    ExtraContent    = '*.ps1xml'
    ExternalModules = 'Az.Accounts'

    Manifest = @{
        PowerShellVersion = 7.4
        CompanyName       = 'KnowIT Soluciones'
        Copyright         = '(c) 2026 KnowIT Soluciones'
        Tags              = 'Azure', 'CostManagement', 'FinOps', 'Tagging', 'Cost'
    }
}
