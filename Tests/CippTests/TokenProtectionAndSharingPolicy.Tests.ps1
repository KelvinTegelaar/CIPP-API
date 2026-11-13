# Pester tests for Invoke-CippTestZTNA21941 and Invoke-CippTestCIS_1_3_3.
#
#   - ZTNA21941 accepted a sign-in frequency control as token protection. Its marker,
#     authenticationType = primaryAndSecondaryAuthentication, is the default on every sign-in
#     frequency policy, so any such policy passed the test.
#   - CIS_1_3_3 picks the default sharing policy by its Default field, which the field manifest did
#     not list. The field came back $null and the test graded whichever policy was first.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($Name in 'Invoke-CippTestZTNA21941', 'Invoke-CippTestCIS_1_3_3', 'Get-CippTestDataFieldManifest') {
        $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter "$Name.ps1" -File -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if (-not $FunctionPath) { throw "Could not locate $Name.ps1 under Modules/" }
        . $FunctionPath
    }

    # Projects rows to the manifest fields, as the real Get-CIPPTestData does
    function Get-CIPPTestData {
        param($TenantFilter, $Type, $Fields, [switch]$Stream)
        $Manifest = Get-CippTestDataFieldManifest $Type
        if ($Manifest) { $script:Data[$Type] | Select-Object -Property $Manifest } else { $script:Data[$Type] }
    }
    function Add-CippTestResult { param($TenantFilter, $TestId, $TestType, $Status, $ResultMarkdown, $Risk, $Name, $UserImpact, $ImplementationEffort, $Category) $script:Result = @{ Status = $Status; Markdown = "$ResultMarkdown" } }
    function Write-LogMessage { }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    function New-CAPolicy {
        param($SessionControls, [string[]]$IncludeUsers = @('All'), [string[]]$IncludeGroups = @())
        [pscustomobject]@{
            id              = [guid]::NewGuid().ToString()
            displayName     = 'Policy'
            state           = 'enabled'
            conditions      = [pscustomobject]@{
                users        = [pscustomobject]@{ includeUsers = $IncludeUsers; includeGroups = $IncludeGroups; includeRoles = @() }
                applications = [pscustomobject]@{ includeApplications = @('All') }
                platforms    = [pscustomobject]@{ includePlatforms = @('windows') }
            }
            grantControls   = $null
            sessionControls = $SessionControls
        }
    }
    $script:TokenProtection = [pscustomobject]@{ secureSignInSession = [pscustomobject]@{ isEnabled = $true } }
    $script:SignInFrequency = [pscustomobject]@{ signInFrequency = [pscustomobject]@{ isEnabled = $true; type = 'hours'; value = 8; authenticationType = 'primaryAndSecondaryAuthentication'; frequencyInterval = 'timeBased' } }
}

Describe 'ZTNA21941 token protection' {
    BeforeEach { $script:Data = @{}; $script:Result = $null }

    It 'fails when the only Windows policy is a sign-in frequency policy' {
        $script:Data.ConditionalAccessPolicies = @(New-CAPolicy -SessionControls $script:SignInFrequency)
        Invoke-CippTestZTNA21941 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
        $script:Result.Markdown | Should -Match 'No token protection policies found'
    }

    It 'passes on a policy with the secureSignInSession control' {
        $script:Data.ConditionalAccessPolicies = @(New-CAPolicy -SessionControls $script:TokenProtection)
        Invoke-CippTestZTNA21941 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
    }

    It 'fails a token protection policy that targets nobody' {
        $script:Data.ConditionalAccessPolicies = @(New-CAPolicy -SessionControls $script:TokenProtection -IncludeUsers @('None'))
        Invoke-CippTestZTNA21941 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
        $script:Result.Markdown | Should -Match 'No users targeted'
    }

    It 'passes a token protection policy that targets a group' {
        $script:Data.ConditionalAccessPolicies = @(New-CAPolicy -SessionControls $script:TokenProtection -IncludeUsers @() -IncludeGroups @('11111111-1111-1111-1111-111111111111'))
        Invoke-CippTestZTNA21941 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
    }
}

Describe 'CIS_1_3_3 default sharing policy' {
    BeforeEach { $script:Data = @{}; $script:Result = $null }

    It 'grades the default policy, not the first one' {
        $script:Data.ExoSharingPolicy = @(
            [pscustomobject]@{ Name = 'Custom restricted policy'; Enabled = $true; Default = $false; Domains = @('contoso.com:ContactsSharing') }
            [pscustomobject]@{ Name = 'Default Sharing Policy'; Enabled = $true; Default = $true; Domains = @('Anonymous:CalendarSharingFreeBusyReviewer', '*:CalendarSharingFreeBusySimple') }
        )
        Invoke-CippTestCIS_1_3_3 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
        $script:Result.Markdown | Should -Match 'Default Sharing Policy'
    }

    It 'passes when the default policy is disabled although another policy shares calendars' {
        $script:Data.ExoSharingPolicy = @(
            [pscustomobject]@{ Name = 'Partner policy'; Enabled = $true; Default = $false; Domains = @('partner.com:CalendarSharingFreeBusySimple') }
            [pscustomobject]@{ Name = 'Default Sharing Policy'; Enabled = $false; Default = $true; Domains = @('Anonymous:CalendarSharingFreeBusyReviewer') }
        )
        Invoke-CippTestCIS_1_3_3 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
        $script:Result.Markdown | Should -Match 'Default Sharing Policy'
    }
}
