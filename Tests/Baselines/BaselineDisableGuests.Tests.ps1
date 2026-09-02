# Get-CIPPBaselineDisableGuestsState mirrors the DisableGuests standard: the same newest-attempt
# rule, the same IncludeNeverSignedIn switch (off by default and off for templates that predate
# it) and the same 7-day grace after an admin re-enables an account. Each test pins one of those,
# because drift between the standard and the baseline shows up as a guest one path disables and
# the other reports compliant.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines'

    function New-GraphGetRequest { param($uri, $tenantid, $scope, $AsApp) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPLastSignInDateTime.ps1')
    . (Join-Path $Baselines 'Get-CIPPBaselineDisableGuestsState.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Now = (Get-Date).ToUniversalTime()

    # Guests go through ConvertFrom-Json, the shape New-GraphGetRequest hands the hook. Each
    # *DaysAgo is how far back that signInActivity timestamp sits; leave all three out for a guest
    # with no sign-in on record.
    function script:New-Guest {
        param(
            [string]$Id,
            [string]$Upn,
            [int]$CreatedDaysAgo = 400,
            [Nullable[int]]$InteractiveDaysAgo,
            [Nullable[int]]$NonInteractiveDaysAgo,
            [Nullable[int]]$SuccessfulDaysAgo
        )
        $Stamp = { param($DaysAgo) if ($null -ne $DaysAgo) { $script:Now.AddDays(-$DaysAgo).ToString('o') } else { $null } }
        $Guest = [ordered]@{
            id                = $Id
            userPrincipalName = $Upn
            mail              = $Upn
            userType          = 'Guest'
            accountEnabled    = $true
            createdDateTime   = $script:Now.AddDays(-$CreatedDaysAgo).ToString('o')
        }
        if ($null -ne $InteractiveDaysAgo -or $null -ne $NonInteractiveDaysAgo -or $null -ne $SuccessfulDaysAgo) {
            $Guest.signInActivity = [ordered]@{
                lastSignInDateTime               = & $Stamp $InteractiveDaysAgo
                lastNonInteractiveSignInDateTime = & $Stamp $NonInteractiveDaysAgo
                lastSuccessfulSignInDateTime     = & $Stamp $SuccessfulDaysAgo
            }
        }
        $Guest | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    }

    # A rendered template item. Omit -IncludeNeverSignedIn to model a template saved before the
    # switch existed.
    function script:New-DisableGuestsItem {
        param([Nullable[int]]$Days, [Nullable[bool]]$IncludeNeverSignedIn)
        $Variables = [PSCustomObject]@{}
        if ($null -ne $Days) { $Variables | Add-Member -NotePropertyName days -NotePropertyValue $Days }
        if ($null -ne $IncludeNeverSignedIn) { $Variables | Add-Member -NotePropertyName IncludeNeverSignedIn -NotePropertyValue $IncludeNeverSignedIn }
        [PSCustomObject]@{ Variables = $Variables }
    }
}

Describe 'Get-CIPPBaselineDisableGuestsState' {
    BeforeEach {
        $script:guests = @()
        $script:audits = @()
        Mock New-GraphGetRequest {
            param($uri)
            if ($uri -like '*directoryAudits*') { return $script:audits }
            return $script:guests
        }
    }

    It 'judges inactivity on the newest sign-in attempt, not the last successful sign-in' {
        $script:guests = @(
            New-Guest -Id 'g1' -Upn 'bas_example.com#EXT#@contoso.onmicrosoft.com' -SuccessfulDaysAgo 300 -InteractiveDaysAgo 154 -NonInteractiveDaysAgo 3
            New-Guest -Id 'stale' -Upn 'stale@example.com' -SuccessfulDaysAgo 250 -InteractiveDaysAgo 200 -NonInteractiveDaysAgo 190
        )

        $Prepared = Get-CIPPBaselineDisableGuestsState -Item (New-DisableGuestsItem -Days 180) -TenantFilter $script:Tenant

        @($Prepared.Current.offenders) | Should -Be @('stale@example.com')
        @($Prepared.Current.targets).id | Should -Be @('stale')
    }

    It 'skips guests with no sign-in on record unless IncludeNeverSignedIn is on' {
        $script:guests = @(New-Guest -Id 'pending' -Upn 'pending@example.com')

        $Legacy = Get-CIPPBaselineDisableGuestsState -Item (New-DisableGuestsItem -Days 90) -TenantFilter $script:Tenant
        @($Legacy.Current.offenders) | Should -BeNullOrEmpty

        $Off = Get-CIPPBaselineDisableGuestsState -Item (New-DisableGuestsItem -Days 90 -IncludeNeverSignedIn $false) -TenantFilter $script:Tenant
        @($Off.Current.offenders) | Should -BeNullOrEmpty

        $On = Get-CIPPBaselineDisableGuestsState -Item (New-DisableGuestsItem -Days 90 -IncludeNeverSignedIn $true) -TenantFilter $script:Tenant
        @($On.Current.offenders) | Should -Be @('pending@example.com')
        @($On.Current.targets).id | Should -Be @('pending')
    }

    It 'leaves a guest an admin re-enabled in the last 7 days alone' {
        $script:guests = @(New-Guest -Id 'stale' -Upn 'stale@example.com' -InteractiveDaysAgo 200)
        $script:audits = @([pscustomobject]@{ targetResources = @([pscustomobject]@{ id = 'stale' }) })

        $Prepared = Get-CIPPBaselineDisableGuestsState -Item (New-DisableGuestsItem -Days 90) -TenantFilter $script:Tenant

        @($Prepared.Current.offenders) | Should -BeNullOrEmpty
        @($Prepared.Current.targets) | Should -BeNullOrEmpty
    }

    It 'falls back to 90 days when the template carries no value' {
        $script:guests = @(
            New-Guest -Id 'over' -Upn 'over@example.com' -InteractiveDaysAgo 100
            New-Guest -Id 'under' -Upn 'under@example.com' -InteractiveDaysAgo 80
        )

        $Prepared = Get-CIPPBaselineDisableGuestsState -Item (New-DisableGuestsItem) -TenantFilter $script:Tenant

        @($Prepared.Current.offenders) | Should -Be @('over@example.com')
    }
}
