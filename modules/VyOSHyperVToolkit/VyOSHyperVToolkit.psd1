@{
    RootModule = 'VyOSHyperVToolkit.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'c0f5f63b-1d14-4c9e-a4a0-8f2abf7b8c58'
    Author = 'Copilot'
    CompanyName = ''
    Copyright = '(c) 2026'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'New-VyosSeedIso',
        'New-VyosHyperVVm',
        'Start-VyosHyperVVm',
        'Remove-VyosLab',
        'Invoke-VyosRouterLab'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('VyOS', 'Hyper-V', 'NoCloud', 'PowerShell')
        }
    }
}