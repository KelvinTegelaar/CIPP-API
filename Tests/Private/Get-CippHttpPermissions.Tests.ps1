BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Get-CIPPHttpFunctions { param([switch]$ByRole, [switch]$ByRoleGroup) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Test-CippHttpPermissionUniverse.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Get-CippHttpPermissions.ps1')

    # A plausible universe: 60 names shaped Area.Object.Read/ReadWrite, including the core one.
    $script:FullUniverse = @(
        'CIPP.Core.Read'
        'CIPP.Core.ReadWrite'
        foreach ($Area in 'Identity', 'Exchange', 'Tenant', 'Endpoint', 'Security', 'Teams', 'Sharepoint') {
            foreach ($Object in 'User', 'Group', 'Device', 'Mailbox', 'Policy') {
                "$Area.$Object.Read"
                "$Area.$Object.ReadWrite"
            }
        }
    )

    $env:CIPPNG = 'true'
    $env:APP_VERSION = '10.9.1'
}

Describe 'Test-CippHttpPermissionUniverse' {
    It 'accepts a full universe' {
        Test-CippHttpPermissionUniverse -Permissions $script:FullUniverse | Should -BeTrue
    }

    It 'accepts the None placeholder among real permissions' {
        Test-CippHttpPermissionUniverse -Permissions (@('None') + $script:FullUniverse) | Should -BeTrue
    }

    It 'rejects an empty or missing list' {
        Test-CippHttpPermissionUniverse -Permissions @() | Should -BeFalse
        Test-CippHttpPermissionUniverse -Permissions $null | Should -BeFalse
    }

    It 'rejects a truncated enumeration' {
        Test-CippHttpPermissionUniverse -Permissions ($script:FullUniverse | Select-Object -First 12) | Should -BeFalse
    }

    It 'rejects a universe without the core read permission' {
        $NoCore = @($script:FullUniverse | Where-Object { $_ -ne 'CIPP.Core.Read' })
        Test-CippHttpPermissionUniverse -Permissions $NoCore | Should -BeFalse
    }

    It 'rejects an error string persisted as a permission' {
        $WithError = @('Function Error Exception of type System.OutOfMemoryException was thrown') + $script:FullUniverse
        Test-CippHttpPermissionUniverse -Permissions $WithError | Should -BeFalse
    }
}

Describe 'Get-CippHttpPermissions' {
    BeforeEach {
        $script:CippHttpPermissions = $null
        $script:CippHttpPermissionsVersion = $null
        Mock Add-CIPPAzDataTableEntity {}
    }

    It 'serves a valid cached universe without enumerating' {
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ Permissions = ($script:FullUniverse | ConvertTo-Json -Compress) } }
        Mock Get-CIPPHttpFunctions { throw 'should not enumerate' }

        $Result = Get-CippHttpPermissions

        @($Result).Count | Should -Be $script:FullUniverse.Count
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'recomputes and replaces a cached universe that is an error string' {
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ Permissions = '"Function Error Exception of type System.OutOfMemoryException was thrown"' } }
        Mock Get-CIPPHttpFunctions { $script:FullUniverse | ForEach-Object { [PSCustomObject]@{ Permission = $_; Count = 1 } } }

        $Result = Get-CippHttpPermissions 3>$null

        $Result | Should -Contain 'CIPP.Core.Read'
        @($Result).Count | Should -Be $script:FullUniverse.Count
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'recomputes a cached universe that is too short to be real' {
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ Permissions = (@('CIPP.Core.Read', 'Identity.User.Read') | ConvertTo-Json -Compress) } }
        Mock Get-CIPPHttpFunctions { $script:FullUniverse | ForEach-Object { [PSCustomObject]@{ Permission = $_; Count = 1 } } }

        $Result = Get-CippHttpPermissions 3>$null

        @($Result).Count | Should -Be $script:FullUniverse.Count
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'serves but does not persist a truncated enumeration' {
        Mock Get-CIPPAzDataTableEntity { $null }
        Mock Get-CIPPHttpFunctions { @('CIPP.Core.Read', 'Identity.User.Read', 'None') | ForEach-Object { [PSCustomObject]@{ Permission = $_; Count = 1 } } }

        $Result = Get-CippHttpPermissions 3>$null

        @($Result).Count | Should -Be 3
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        # Nothing memoized either: the next call must try again.
        $script:CippHttpPermissions | Should -BeNullOrEmpty
    }

    It 'lets an enumeration failure surface instead of caching it' {
        Mock Get-CIPPAzDataTableEntity { $null }
        Mock Get-CIPPHttpFunctions { throw 'Failed to enumerate HTTP function permissions: boom' }

        { Get-CippHttpPermissions } | Should -Throw -ExpectedMessage '*Failed to enumerate*'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }
}
