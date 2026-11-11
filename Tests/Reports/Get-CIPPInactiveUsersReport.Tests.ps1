# Pester tests for Get-CIPPInactiveUsersReport and the mfaCoverage preset of Get-CippReportSankeyData.
#
# Both turned missing data into a definite negative:
#   - signInActivity is only cached for tenants licensed for sign-in logs. Without it every member
#     user read as never signed in, so the report listed the whole tenant as inactive.
#   - a user whose Conditional Access or security defaults state could not be read was counted
#     under "No enforcement".

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    foreach ($Name in 'Get-CIPPInactiveUsersReport', 'Get-CippReportSankeyData') {
        $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter "$Name.ps1" -File -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if (-not $FunctionPath) { throw "Could not locate $Name.ps1 under Modules/" }
        . $FunctionPath
    }

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Rows) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$ByTenant, [switch]$CountsOnly) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }

    $script:Tenant = 'contoso.onmicrosoft.com'
    function New-User {
        param($Upn, $LastSignIn, [switch]$NoSignInActivity)
        $User = [ordered]@{ id = $Upn; userPrincipalName = $Upn; displayName = $Upn; userType = 'Member'; accountEnabled = $true; assignedLicenses = @() }
        if (-not $NoSignInActivity) { $User.signInActivity = [pscustomobject]@{ lastSignInDateTime = $LastSignIn; lastNonInteractiveSignInDateTime = $null; lastSuccessfulSignInDateTime = $null } }
        [pscustomobject]$User
    }
}

Describe 'Get-CIPPInactiveUsersReport' {
    BeforeEach {
        Mock New-CIPPDbRequest { $script:Users }
        Mock Get-CIPPDbItem { }
        Mock Get-Tenants { [pscustomobject]@{ displayName = 'Contoso' } }
        Mock Write-LogMessage { }
    }

    It 'returns no rows when no cached user carries sign-in activity' {
        $script:Users = @((New-User 'a@contoso.com' -NoSignInActivity), (New-User 'b@contoso.com' -NoSignInActivity))

        @(Get-CIPPInactiveUsersReport -TenantFilter $script:Tenant -InactiveDays 90 6>$null).Count | Should -Be 0
    }

    It 'lists stale and never-signed-in users when the tenant has sign-in activity' {
        $script:Users = @(
            (New-User 'active@contoso.com' -LastSignIn (Get-Date).AddDays(-2).ToString('o')),
            (New-User 'stale@contoso.com' -LastSignIn (Get-Date).AddDays(-200).ToString('o')),
            (New-User 'never@contoso.com' -NoSignInActivity)
        )

        $Result = @(Get-CIPPInactiveUsersReport -TenantFilter $script:Tenant -InactiveDays 90 6>$null)

        @($Result.userPrincipalName | Sort-Object) | Should -Be @('never@contoso.com', 'stale@contoso.com')
    }
}

Describe 'Get-CippReportSankeyData mfaCoverage' {
    BeforeAll {
        function Get-LinkValue { param($Data, $Source, $Target) @($Data.links | Where-Object { $_.source -eq $Source -and $_.target -eq $Target }).value }
        function New-MfaRow { param($Registered, $CoveredByCA, $CoveredBySD) [pscustomobject]@{ AccountEnabled = $true; MFARegistration = $Registered; CoveredByCA = $CoveredByCA; CoveredBySD = $CoveredBySD; PerUser = 'disabled' } }
    }

    It 'puts users whose enforcement could not be read under Unknown, not No enforcement' {
        $Rows = @(
            (New-MfaRow $true 'CA policies not available: Forbidden' $false),
            (New-MfaRow $false 'Unknown - external tenant lookup failed' $false),
            (New-MfaRow $false 'Not Enforced' $null),
            (New-MfaRow $false 'Not Enforced' $false),
            (New-MfaRow $true 'Enforced - All Apps' $null)
        )

        $Data = Get-CippReportSankeyData -Preset 'mfaCoverage' -Rows $Rows

        Get-LinkValue $Data 'MFA registered' 'Unknown' | Should -Be 1
        Get-LinkValue $Data 'Not registered' 'Unknown' | Should -Be 2
        Get-LinkValue $Data 'Not registered' 'No enforcement' | Should -Be 1
        Get-LinkValue $Data 'MFA registered' 'CA policy' | Should -Be 1
        Get-LinkValue $Data 'MFA registered' 'No enforcement' | Should -BeNullOrEmpty
    }
}
