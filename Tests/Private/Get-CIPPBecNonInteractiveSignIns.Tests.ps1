BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $noPagination) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecCollectorResult.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecNonInteractiveSignIns.ps1')
    $script:UserId = 'c0ffee00-0000-4000-8000-000000000001'
    $script:Start = [datetime]::new(2026, 8, 14, 0, 0, 0, [System.DateTimeKind]::Utc)

    function Get-SignInFixture {
        param([string]$Id, $Country = 'NL', [string]$CaStatus = 'success', $ErrorCode = 0, [string]$When = '2026-08-21T10:00:00Z')
        [pscustomobject]@{
            id                           = $Id
            createdDateTime              = $When
            appDisplayName               = 'Outlook'
            resourceDisplayName          = 'Microsoft Graph'
            clientAppUsed                = 'Mobile Apps and Desktop clients'
            conditionalAccessStatus      = $CaStatus
            status                       = [pscustomobject]@{ errorCode = $ErrorCode; failureReason = 'Other.' }
            ipAddress                    = '203.0.113.9'
            location                     = if ($null -eq $Country) { $null } else { [pscustomobject]@{ city = 'Amsterdam'; countryOrRegion = $Country } }
            userAgent                    = 'Mozilla/5.0'
            incomingTokenType            = 'refreshToken'
            tokenProtectionStatusDetails = [pscustomobject]@{ signInSessionStatus = 'unbound' }
            riskLevelDuringSignIn        = 'none'
            signInEventTypes             = @('nonInteractiveUser')
        }
    }
}

Describe 'Get-CIPPBecNonInteractiveSignIns' {
    BeforeEach {
        Mock New-GraphGetRequest { @($script:SignIns) }
        Mock ConvertTo-CIPPODataFilterValue { $Value }
        $script:SignIns = @()
    }

    It 'queries the beta sign-in log for the user''s non-interactive events inside the window, newest first, paged to the end' {
        $null = Get-CIPPBecNonInteractiveSignIns -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start -UsageLocation 'NL'
        Should -Invoke ConvertTo-CIPPODataFilterValue -Times 1 -ParameterFilter { $Value -eq $script:UserId -and $Type -eq 'Guid' }
        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter {
            $uri -eq "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=userId eq '$($script:UserId)' and signInEventTypes/any(t: t eq 'nonInteractiveUser') and createdDateTime ge 2026-08-14T00:00:00Z&`$top=999&`$orderby=createdDateTime desc" -and
            $tenantid -eq 'contoso.com' -and $AsApp -eq $true -and $noPagination -ne $true
        }
    }

    It 'projects a sign-in row with a UTC timestamp, token details and the location verdict' {
        $script:SignIns = @(Get-SignInFixture -Id 's1' -When '2026-08-21T12:00:00+02:00')
        $Result = Get-CIPPBecNonInteractiveSignIns -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start -UsageLocation 'NL'
        $Result.Complete | Should -BeTrue
        $Result.Cap | Should -BeNullOrEmpty
        $Result.Error | Should -BeNullOrEmpty
        $Result.Count | Should -Be 1
        $Row = $Result.Data[0]
        $Row.CreatedDateTime | Should -Be '2026-08-21T10:00:00Z' -Because 'the offset is folded into UTC'
        $Row.id | Should -Be 's1'
        $Row.AppDisplayName | Should -Be 'Outlook'
        $Row.ResourceDisplayName | Should -Be 'Microsoft Graph'
        $Row.ClientAppUsed | Should -Be 'Mobile Apps and Desktop clients'
        $Row.Status | Should -Be 'Success'
        $Row.ErrorCode | Should -Be 0
        $Row.IPAddress | Should -Be '203.0.113.9'
        $Row.Country | Should -Be 'NL'
        $Row.City | Should -Be 'Amsterdam'
        $Row.UserAgent | Should -Be 'Mozilla/5.0'
        $Row.IncomingTokenType | Should -Be 'refreshToken'
        $Row.TokenProtection | Should -Be 'unbound'
        $Row.RiskLevelDuringSignIn | Should -Be 'none'
        $Row.ForeignLocation | Should -BeOfType [bool]
        $Row.ForeignLocation | Should -BeFalse
    }

    It 'derives Status from the conditional access outcome and the error code' {
        $script:SignIns = @(
            Get-SignInFixture -Id 's-ok' -CaStatus 'success' -ErrorCode 0
            Get-SignInFixture -Id 's-na' -CaStatus 'notApplied' -ErrorCode 0
            Get-SignInFixture -Id 's-pw' -CaStatus 'success' -ErrorCode 50126
            Get-SignInFixture -Id 's-ca' -CaStatus 'failure' -ErrorCode 0
        )
        $Result = Get-CIPPBecNonInteractiveSignIns -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start -UsageLocation 'NL'
        ($Result.Data | Where-Object { $_.id -eq 's-ok' }).Status | Should -Be 'Success'
        ($Result.Data | Where-Object { $_.id -eq 's-na' }).Status | Should -Be 'Success' -Because 'no applicable CA policy is still a successful sign-in'
        ($Result.Data | Where-Object { $_.id -eq 's-pw' }).Status | Should -Be 'Failed' -Because 'a non-zero error code fails the sign-in even when CA passed'
        ($Result.Data | Where-Object { $_.id -eq 's-pw' }).ErrorCode | Should -Be 50126
        ($Result.Data | Where-Object { $_.id -eq 's-ca' }).Status | Should -Be 'Failed' -Because 'a CA failure fails the sign-in even with error code 0'
    }

    It 'compares the sign-in country against the usage location and leaves the verdict undecided when either side is unknown' {
        $script:SignIns = @(
            Get-SignInFixture -Id 's-home' -Country 'NL'
            Get-SignInFixture -Id 's-case' -Country 'nl'
            Get-SignInFixture -Id 's-away' -Country 'US'
            Get-SignInFixture -Id 's-unknown' -Country 'Unknown'
            Get-SignInFixture -Id 's-blank' -Country ''
            Get-SignInFixture -Id 's-noloc' -Country $null
        )
        $Result = Get-CIPPBecNonInteractiveSignIns -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start -UsageLocation 'NL'
        $Result.Count | Should -Be 6
        $InCountry = $Result.Data | Where-Object { $_.id -eq 's-home' }
        $InCountry.ForeignLocation | Should -BeOfType [bool]
        $InCountry.ForeignLocation | Should -BeFalse
        ($Result.Data | Where-Object { $_.id -eq 's-case' }).ForeignLocation | Should -BeFalse -Because 'the country comparison ignores case'
        ($Result.Data | Where-Object { $_.id -eq 's-away' }).ForeignLocation | Should -BeTrue
        ($Result.Data | Where-Object { $_.id -eq 's-unknown' }).ForeignLocation | Should -BeNullOrEmpty
        ($Result.Data | Where-Object { $_.id -eq 's-blank' }).ForeignLocation | Should -BeNullOrEmpty
        $NoLoc = $Result.Data | Where-Object { $_.id -eq 's-noloc' }
        $NoLoc.ForeignLocation | Should -BeNullOrEmpty
        $NoLoc.Country | Should -BeNullOrEmpty
        $NoLoc.City | Should -BeNullOrEmpty

        $script:SignIns = @(Get-SignInFixture -Id 's-away' -Country 'US')
        $Result = Get-CIPPBecNonInteractiveSignIns -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start
        $Result.Data[0].ForeignLocation | Should -BeNullOrEmpty -Because 'without a usage location there is nothing to compare against'
    }

    It 'reports every row Graph paged back as complete - there is no count cap' {
        $script:SignIns = @(1..1200 | ForEach-Object { Get-SignInFixture -Id "s$_" })
        $Result = Get-CIPPBecNonInteractiveSignIns -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start -UsageLocation 'NL'
        $Result.Complete | Should -BeTrue
        $Result.Cap | Should -BeNullOrEmpty
        $Result.Error | Should -BeNullOrEmpty
        $Result.Count | Should -Be 1200
    }

    It 'lets a Graph failure propagate to the caller instead of reporting an empty sign-in list' {
        Mock New-GraphGetRequest { throw 'Graph unavailable' }
        { Get-CIPPBecNonInteractiveSignIns -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start -UsageLocation 'NL' } | Should -Throw -ExpectedMessage '*Graph unavailable*'
    }
}
