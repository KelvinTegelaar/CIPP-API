# Pester tests for Get-CIPPAppPackageStorage: a connected storage account or the instance's own, remembered per process.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Get-ExtensionAPIKey { param($Extension) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPAppPackageStorage.ps1')
    $script:SavedEnv = @{}
    foreach ($Name in 'CIPP_APPPACKAGESTORAGE', 'CIPP_HOSTED', 'AzureWebJobsStorage') { $script:SavedEnv[$Name] = [System.Environment]::GetEnvironmentVariable($Name) }
}

AfterAll {
    foreach ($Name in $script:SavedEnv.Keys) { [System.Environment]::SetEnvironmentVariable($Name, $script:SavedEnv[$Name]) }
}

Describe 'Get-CIPPAppPackageStorage' {
    BeforeEach {
        [System.Environment]::SetEnvironmentVariable('CIPP_APPPACKAGESTORAGE', $null)
        [System.Environment]::SetEnvironmentVariable('AzureWebJobsStorage', 'own')
        [System.Environment]::SetEnvironmentVariable('CIPP_HOSTED', $null)
        Mock Get-CIPPAzDataTableEntity { }
        Mock Get-ExtensionAPIKey { 'AccountName=mine;AccountKey=k' }
    }

    It 'uses the instance storage with a limit only when hosted' -ForEach @(
        @{ Hosted = 'true'; Limit = 10GB }
        @{ Hosted = $null; Limit = 0 }
    ) {
        [System.Environment]::SetEnvironmentVariable('CIPP_HOSTED', $Hosted)

        $Storage = Get-CIPPAppPackageStorage

        $Storage.ConnectionString | Should -Be 'own'
        $Storage.Custom | Should -BeFalse
        $Storage.LimitBytes | Should -Be $Limit
        Should -Invoke Get-ExtensionAPIKey -Times 0 -Exactly
    }

    It 'uses a connected account without a limit, reading the table once per process' {
        [System.Environment]::SetEnvironmentVariable('CIPP_HOSTED', 'true')
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ AccountName = 'mine' } }

        $null = Get-CIPPAppPackageStorage
        $Storage = Get-CIPPAppPackageStorage

        $Storage.ConnectionString | Should -Be 'AccountName=mine;AccountKey=k'
        $Storage.LimitBytes | Should -Be 0
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'finds a package without a row in the instance storage, even while an account is connected' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ AccountName = 'mine' } } -ParameterFilter { $Filter -like "*'AppPackageStorage'*" }

        $Storage = Get-CIPPAppPackageStorage -PackageId '6f1c2a3b-1111-2222-3333-444455556666'

        $Storage.ConnectionString | Should -Be 'own'
        $Storage.Custom | Should -BeFalse
        Should -Invoke Get-ExtensionAPIKey -Times 0 -Exactly
    }

    It 'finds a package in the connected account it was uploaded to, without a limit' {
        [System.Environment]::SetEnvironmentVariable('CIPP_HOSTED', 'true')
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ AccountName = 'mine' } }

        $Storage = Get-CIPPAppPackageStorage -PackageId '6f1c2a3b-1111-2222-3333-444455556666'

        $Storage.ConnectionString | Should -Be 'AccountName=mine;AccountKey=k'
        $Storage.AccountName | Should -Be 'mine'
        $Storage.LimitBytes | Should -Be 0
    }

    It 'refuses a package stored in an account that is no longer connected' -ForEach @(
        @{ Case = 'disconnected'; Connected = $null }
        @{ Case = 'replaced'; Connected = 'other' }
    ) {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ AccountName = 'mine' } } -ParameterFilter { $Filter -like "*'AppPackage' and*" }
        Mock Get-CIPPAzDataTableEntity { if ($Connected) { [pscustomobject]@{ AccountName = $Connected } } } -ParameterFilter { $Filter -like "*'AppPackageStorage'*" }
        Mock Get-ExtensionAPIKey { "AccountName=$Connected;AccountKey=k" }

        { Get-CIPPAppPackageStorage -PackageId '6f1c2a3b-1111-2222-3333-444455556666' } | Should -Throw '*storage account mine*no longer connected*' -ExceptionType ([System.Management.Automation.ItemNotFoundException])
    }

    It 'throws instead of falling back when the connected account cannot be read' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ AccountName = 'mine' } }
        Mock Get-ExtensionAPIKey { }

        { Get-CIPPAppPackageStorage } | Should -Throw '*key vault*'
        [System.Environment]::GetEnvironmentVariable('CIPP_APPPACKAGESTORAGE') | Should -BeNullOrEmpty
    }
}
