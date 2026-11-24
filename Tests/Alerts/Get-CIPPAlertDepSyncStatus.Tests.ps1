BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $LogData) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }

    . (Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertDepSyncStatus.ps1')

    function New-Token($Id, $HoursAgo, $ErrorCode = 0) {
        [PSCustomObject]@{
            id                         = $Id
            tokenName                  = "Token $Id"
            lastSuccessfulSyncDateTime = if ($null -ne $HoursAgo) { [datetime]::UtcNow.AddHours(-$HoursAgo).ToString('o') }
            lastSyncErrorCode          = $ErrorCode
            syncedDeviceCount          = 5
        }
    }
}

Describe 'Get-CIPPAlertDepSyncStatus' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Write-AlertTrace { }
    }

    It 'reports only stale, never-synced and failed tokens, keyed on the token id' {
        Mock New-GraphGetRequest { @(
                New-Token 'healthy' 2
                New-Token 'stale' 30
                New-Token 'never' $null
                New-Token 'terms' 1 3
            ) }
        Get-CIPPAlertDepSyncStatus -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Write-AlertTrace -Times 1 -Exactly -ParameterFilter {
            (@($data.Id) -join ',') -eq 'DepSync-stale,DepSync-never,DepSync-terms' -and
            $data[0].Message -like '*over 24 hours*' -and
            $data[2].Message -like '*terms are waiting to be accepted (code 3)*' -and
            $data[2].Message -notlike '*hours*'
        }
    }

    It 'uses the configured hours' {
        Mock New-GraphGetRequest { New-Token 'a' 30 }
        Get-CIPPAlertDepSyncStatus -TenantFilter 'contoso.onmicrosoft.com' -InputValue 48
        Should -Invoke Write-AlertTrace -Times 1 -Exactly -ParameterFilter { -not $data }
    }

    It 'reports an empty result when every token is healthy or there are none' {
        Mock New-GraphGetRequest { }
        Get-CIPPAlertDepSyncStatus -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Write-AlertTrace -Times 1 -Exactly -ParameterFilter { -not $data }
    }

    It 'does not resolve open alerts when Graph fails' {
        Mock New-GraphGetRequest { throw 'Forbidden' }
        Get-CIPPAlertDepSyncStatus -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Write-AlertTrace -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly
    }
}
