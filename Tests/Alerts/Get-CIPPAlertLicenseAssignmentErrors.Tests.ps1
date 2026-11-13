# License assignment errors alert: every failed assignment alerts whatever its error code; a healthy
# assignment (error null or 'None') does not.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CIPPLicenseSkuName { param($SkuIds, $TenantFilter) }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $LogData) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }

    . (Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertLicenseAssignmentErrors.ps1')
}

Describe 'Get-CIPPAlertLicenseAssignmentErrors' {
    BeforeEach {
        Mock Get-CIPPLicenseSkuName { }
        Mock Write-LogMessage { }
        Mock Write-AlertTrace { }
    }

    It 'alerts on DependencyViolation and ignores healthy assignments' {
        Mock New-GraphGetRequest {
            [PSCustomObject]@{
                id = 'u1'; userPrincipalName = 'alice@contoso.com'; displayName = 'Alice'
                licenseAssignmentStates = @(
                    [PSCustomObject]@{ skuId = 'sku-broken'; error = 'DependencyViolation'; state = 'Error' }
                    [PSCustomObject]@{ skuId = 'sku-ok'; error = 'None'; state = 'Active' }
                )
            }
            [PSCustomObject]@{
                id = 'u2'; userPrincipalName = 'bob@contoso.com'; displayName = 'Bob'
                licenseAssignmentStates = @([PSCustomObject]@{ skuId = 'sku-ok'; error = $null; state = 'Active' })
            }
        }
        Get-CIPPAlertLicenseAssignmentErrors -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Write-AlertTrace -Times 1 -Exactly -ParameterFilter {
            @($data).Count -eq 1 -and $data.SkuId -eq 'sku-broken' -and $data.Error -like 'Missing dependency*'
        }
        Should -Invoke Write-LogMessage -Times 0 -Exactly
    }
}
