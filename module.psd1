@{
    ModuleName      = 'KnowIT.AzureCosts'
    ModuleId        = 'abc91076-c63c-418c-b713-4e7ff5363fbd'
    Description     = 'Reporte de costos y etiquetado de suscripciones de Azure: Cost Details API, Resource Graph y generacion del xlsx'
    Author          = 'KnowIT'
    Version         = '0.1.x-beta'

    PSSourceFiles   = 'public', 'private'
    ExtraContent    = '*.ps1xml'
    ExternalModules = 'Az.Accounts', 'ImportExcel'

    Manifest = @{
        PowerShellVersion = 7.4
        CompanyName       = 'KnowIT Soluciones'
        Copyright         = '(c) 2026 KnowIT Soluciones'
        Tags              = 'Azure', 'CostManagement', 'FinOps', 'Tagging', 'Excel'
    }
}
