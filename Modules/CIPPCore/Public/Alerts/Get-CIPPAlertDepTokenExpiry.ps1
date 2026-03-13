function Get-CIPPAlertDepTokenExpiry {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        try {
            $DepTokens = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings' -tenantid $TenantFilter
            $AlertData = foreach ($Dep in $DepTokens) {
                if ($Dep.tokenExpirationDateTime -lt (Get-Date).AddDays(30) -and $Dep.tokenExpirationDateTime -gt (Get-Date).AddDays(-7)) {
                    $Message = 'Apple Device Enrollment Program token expiring on {0}' -f $Dep.tokenExpirationDateTime
                    $Dep | Select-Object -Property tokenName, @{Name = 'Message'; Expression = { $Message } }
                }
            }
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

        } catch {}


    } catch {
        Write-LogMessage -API 'Alerts' -tenant $($TenantFilter) -message "Failed to check Apple Device Enrollment Program token expiry for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)" -sev Error
    }
}
