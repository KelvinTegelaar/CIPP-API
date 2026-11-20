BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $RepoRoot 'Modules/CIPPTests/Public/Tests/ZTNA/Identity/Invoke-CippTestZTNA21882.ps1')

    function New-Member($Id, $Upn) { [pscustomobject]@{ id = $Id; displayName = "Name $Id"; userPrincipalName = $Upn } }
    function Get-CIPPTestData {
        param($TenantFilter, $Type, $Fields, [switch]$Stream, [string[]]$Id)
        if ($PSBoundParameters.ContainsKey('Id')) {
            $script:RequestedIds = $Id
            return @($script:Groups).Where({ $Id -contains $_.id })
        }
        # The cached read carries the manifest fields only, never members
        foreach ($G in $script:Groups) { [pscustomobject]@{ id = $G.id; displayName = $G.displayName; isAssignableToRole = $G.isAssignableToRole } }
    }
    function Add-CippTestResult { param($TenantFilter, $TestId, $TestType, $Status, $ResultMarkdown, $Risk, $Name, $UserImpact, $ImplementationEffort, $Category) $script:Result = @{ Status = $Status; Markdown = "$ResultMarkdown" } }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }
}

Describe 'ZTNA21882 nested groups in role-assignable groups' {
    BeforeEach {
        $script:RequestedIds = $null
        $script:Groups = @(
            [pscustomobject]@{ id = 'g-pim'; displayName = 'PIM admins'; isAssignableToRole = $true; members = @((New-Member 'u1' 'u1@contoso.com'), (New-Member 'g-inner' $null)) }
            [pscustomobject]@{ id = 'g-clean'; displayName = 'Clean admins'; isAssignableToRole = $true; members = @(New-Member 'u2' 'u2@contoso.com') }
            [pscustomobject]@{ id = 'g-plain'; displayName = 'Everyone'; isAssignableToRole = $false; members = @(New-Member 'g-x' $null) }
        )
    }

    It 'reads members only for role-assignable groups' {
        Invoke-CippTestZTNA21882 -Tenant 'contoso.com'
        $script:RequestedIds | Should -Be @('g-pim', 'g-clean')
    }

    It 'fails when a role-assignable group has a nested group member' {
        Invoke-CippTestZTNA21882 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
        $script:Result.Markdown | Should -Match '1 of 2 role-assignable group'
        $script:Result.Markdown | Should -Match 'PIM admins'
    }

    It 'passes when no group is role-assignable, without reading members' {
        foreach ($G in $script:Groups) { $G.isAssignableToRole = $false }
        Invoke-CippTestZTNA21882 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
        $script:RequestedIds | Should -BeNullOrEmpty
    }

    It 'skips when the Groups cache is empty' {
        $script:Groups = @()
        Invoke-CippTestZTNA21882 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Skipped'
    }
}
