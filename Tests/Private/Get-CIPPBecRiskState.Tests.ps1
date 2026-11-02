BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-GraphGetRequest { param($uri, $tenantid, $noPagination, $AsApp) }
    function Get-NormalizedError { param($message) $message }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecCollectorResult.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecRiskState.ps1')

    $script:UserId = '3f2504e0-4f89-41d3-9a0c-0305e82c3301'
    $script:Start = [datetime]::new(2026, 8, 13, 0, 0, 0, [System.DateTimeKind]::Utc)
    $script:RiskyUser = [pscustomobject]@{ id = $script:UserId; riskLevel = 'high'; riskState = 'atRisk'; riskDetail = 'none'; isProcessing = $false; riskLastUpdatedDateTime = '2026-08-18T07:15:00Z' }
    # Two detections plus one without an id, which Graph never returns but the mapper must not turn into a blank row.
    $script:Detections = @(
        [pscustomobject]@{ id = 'd1'; detectedDateTime = '2026-08-18T07:00:00Z'; riskEventType = 'unfamiliarFeatures'; riskLevel = 'medium'; riskState = 'atRisk'; riskDetail = 'none'; detectionTimingType = 'realtime'; activity = 'signin'; ipAddress = '203.0.113.9'; location = [pscustomobject]@{ city = 'Lagos'; countryOrRegion = 'NG' }; source = 'IdentityProtection' }
        [pscustomobject]@{ id = 'd2'; detectedDateTime = '2026-08-17T22:40:00Z'; riskEventType = 'anonymizedIPAddress'; riskLevel = 'high'; riskState = 'atRisk'; riskDetail = 'none'; detectionTimingType = 'offline'; activity = 'signin'; ipAddress = '198.51.100.7'; location = $null; source = 'IdentityProtection' }
        [pscustomobject]@{ detectedDateTime = '2026-08-17T22:40:00Z'; riskEventType = 'ghost' }
    )
}

Describe 'Get-CIPPBecRiskState' {
    BeforeEach {
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/identityProtection/riskyUsers/*' } { $script:RiskyUser }
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/identityProtection/riskDetections*' } { $script:Detections }
    }

    It 'reports a listed risky user with its detections mapped to the report shape, asking Graph for the whole window' {
        $Result = Get-CIPPBecRiskState -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start

        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $uri -eq 'https://graph.microsoft.com/v1.0/identityProtection/riskyUsers/3f2504e0-4f89-41d3-9a0c-0305e82c3301' -and $tenantid -eq 'contoso.com' -and $noPagination -eq $true }
        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $uri -eq "https://graph.microsoft.com/v1.0/identityProtection/riskDetections?`$filter=userId eq '3f2504e0-4f89-41d3-9a0c-0305e82c3301' and detectedDateTime ge 2026-08-13T00:00:00Z&`$orderby=detectedDateTime desc" -and $tenantid -eq 'contoso.com' -and $noPagination -ne $true }
        $Result.Complete | Should -BeTrue
        $Result.Skipped | Should -BeFalse
        $Result.Requirement | Should -BeNullOrEmpty
        $Result.Error | Should -BeNullOrEmpty
        $Result.Count | Should -Be 2
        $Result.Data.Listed | Should -BeTrue
        $Result.Data.RiskLevel | Should -Be 'high'
        $Result.Data.RiskState | Should -Be 'atRisk'
        $Result.Data.RiskDetail | Should -Be 'none'
        $Result.Data.IsProcessing | Should -BeFalse
        $Result.Data.RiskLastUpdatedDateTime | Should -Be '2026-08-18T07:15:00Z'
        $Result.Data.Detections.Count | Should -Be 2 -Because 'a detection without an id is dropped'
        $First = $Result.Data.Detections[0]
        $First.PSObject.Properties.Name | Should -Be @('id', 'DetectedDateTime', 'RiskEventType', 'RiskLevel', 'RiskState', 'RiskDetail', 'DetectionTiming', 'Activity', 'IPAddress', 'Country', 'City', 'Source')
        $First.id | Should -Be 'd1'
        $First.DetectedDateTime | Should -Be '2026-08-18T07:00:00Z'
        $First.RiskEventType | Should -Be 'unfamiliarFeatures'
        $First.RiskLevel | Should -Be 'medium'
        $First.DetectionTiming | Should -Be 'realtime'
        $First.IPAddress | Should -Be '203.0.113.9'
        $First.Country | Should -Be 'NG'
        $First.City | Should -Be 'Lagos'
        $Result.Data.Detections[1].Country | Should -BeNullOrEmpty -Because 'a detection without a location still maps'
    }

    It 'treats a riskyUsers 404 as not listed, stays complete, and still reads the detections without a count cap' {
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/identityProtection/riskyUsers/*' } { throw "Request_ResourceNotFound: Resource '3f2504e0-4f89-41d3-9a0c-0305e82c3301' does not exist or one of its queried reference-property objects are not present." }
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/identityProtection/riskDetections*' } { @() }
        $Result = Get-CIPPBecRiskState -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start

        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $uri -like '*/riskDetections?*' -and $uri -notlike '*top=*' -and $noPagination -ne $true }
        $Result.Complete | Should -BeTrue
        $Result.Error | Should -BeNullOrEmpty
        $Result.Skipped | Should -BeFalse
        $Result.Count | Should -Be 0
        $Result.Data.Listed | Should -BeFalse
        $Result.Data.RiskLevel | Should -BeNullOrEmpty
        $Result.Data.RiskState | Should -BeNullOrEmpty
        $Result.Data.RiskLastUpdatedDateTime | Should -BeNullOrEmpty
        $Result.Data.Detections.Count | Should -Be 0
    }

    It 'classifies a licence error as Skipped with the Entra ID P2 requirement instead of "not risky"' {
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/identityProtection/riskyUsers/*' } { throw 'UnknownError: Tenant is not licensed for this feature' }
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/identityProtection/riskDetections*' } { throw 'UnknownError: Tenant is not licensed for this feature' }
        $Result = Get-CIPPBecRiskState -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start

        $Result.Skipped | Should -BeTrue
        $Result.Complete | Should -BeFalse
        $Result.Requirement | Should -Be 'requires Entra ID P2 (Identity Protection)'
        $Result.Error | Should -Match 'Entra ID P2 licence or consent missing'
        $Result.Error | Should -Match 'riskDetections: UnknownError'
        $Result.Data.Listed | Should -BeFalse
        $Result.Data.Detections.Count | Should -Be 0
        $Result.Count | Should -Be 0
    }

    It 'marks the collector Skipped when only the detections call is denied, keeping the riskyUsers outcome' {
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/identityProtection/riskDetections*' } { throw 'Authorization_RequestDenied: Insufficient privileges to complete the operation.' }
        $Result = Get-CIPPBecRiskState -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start

        $Result.Data.Listed | Should -BeTrue
        $Result.Data.RiskLevel | Should -Be 'high'
        $Result.Data.Detections.Count | Should -Be 0
        $Result.Skipped | Should -BeTrue
        $Result.Requirement | Should -Be 'requires Entra ID P2 (Identity Protection)'
        $Result.Error | Should -Be 'riskDetections: Authorization_RequestDenied: Insufficient privileges to complete the operation.'
        $Result.Complete | Should -BeFalse
    }

    It 'reports an unexpected riskyUsers failure as an error, not a skip, and still collects the detections' {
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/identityProtection/riskyUsers/*' } { throw 'Gateway Timeout' }
        $Result = Get-CIPPBecRiskState -TenantFilter 'contoso.com' -UserId $script:UserId -StartDate $script:Start

        $Result.Complete | Should -BeFalse
        $Result.Skipped | Should -BeFalse
        $Result.Requirement | Should -BeNullOrEmpty
        $Result.Error | Should -Be 'riskyUsers: Gateway Timeout'
        $Result.Data.Listed | Should -BeFalse
        $Result.Data.Detections.Count | Should -Be 2
        $Result.Count | Should -Be 2
    }

    It 'rejects a user id that is not a GUID before calling Graph' {
        { Get-CIPPBecRiskState -TenantFilter 'contoso.com' -UserId "x' or 1 eq 1" -StartDate $script:Start } | Should -Throw -ExpectedMessage '*Invalid GUID*'
        Should -Invoke New-GraphGetRequest -Times 0
    }
}
