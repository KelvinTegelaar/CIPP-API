BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }

    . (Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertAppleTerms.ps1')
}

Describe 'Get-CIPPAlertAppleTerms' {
    BeforeEach { Mock Write-AlertTrace { } }

    It 'reports only the token waiting on new terms when a tenant has several' {
        Mock New-GraphGetRequest { @(
                [PSCustomObject]@{ tokenName = 'Healthy'; lastSyncErrorCode = 0 }
                [PSCustomObject]@{ tokenName = 'Blocked'; lastSyncErrorCode = 3 }
            ) }
        Get-CIPPAlertAppleTerms -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Write-AlertTrace -Times 1 -Exactly -ParameterFilter { @($data).Count -eq 1 -and "$($data.TokenName)" -eq 'Blocked' }
    }
}
