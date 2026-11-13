BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-Tenants { param($TenantFilter) }
    function New-GraphGETRequest { param($uri, $tenantid) }
    function New-GraphBulkRequest { param($Requests, $tenantid) }
    function Get-CippException { param($Exception) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertAdminPassword.ps1')
}

Describe 'Get-CIPPAlertAdminPassword' {
    BeforeEach {
        $script:Captured = $null
        $Now = [datetime]::UtcNow
        $script:Users = @(
            @{ UserPrincipalName = 'changed@contoso.com'; createdDateTime = $Now.AddDays(-30).ToString('o'); lastPasswordChangeDateTime = $Now.AddHours(-2).ToString('o') }
            @{ UserPrincipalName = 'new@contoso.com'; createdDateTime = $Now.AddHours(-3).ToString('o'); lastPasswordChangeDateTime = $Now.AddHours(-3).AddSeconds(1).ToString('o') }
            @{ UserPrincipalName = 'old@contoso.com'; createdDateTime = $Now.AddDays(-30).ToString('o'); lastPasswordChangeDateTime = $Now.AddDays(-3).ToString('o') }
        )
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'tid' } }
        Mock New-GraphGETRequest { $script:Users | ForEach-Object { [pscustomobject]@{ principalId = $_.UserPrincipalName; principalOrganizationId = 'tid' } } }
        Mock New-GraphBulkRequest { $script:Users | ForEach-Object { [pscustomobject]@{ id = $_.UserPrincipalName; status = 200; body = [pscustomobject]$_ } } }
        Mock Write-LogMessage {}
        Mock Write-AlertTrace {
            param($cmdletName, $tenantFilter, $data)
            $script:Captured = @($data | Where-Object { $null -ne $_ })
        }
    }

    It 'alerts on a recent change but not on a new account or an old change' {
        Get-CIPPAlertAdminPassword -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Write-LogMessage -Times 0 -Exactly
        $script:Captured.UserPrincipalName | Should -Be @('changed@contoso.com')
    }
}
