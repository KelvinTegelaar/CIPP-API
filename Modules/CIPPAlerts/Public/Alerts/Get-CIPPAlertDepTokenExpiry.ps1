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
            $expiryDays = 30
            if ($InputValue -is [hashtable] -or $InputValue -is [pscustomobject]) {
                if ($null -ne $InputValue.DaysUntilExpiry -and $InputValue.DaysUntilExpiry -ne '') {
                    $parsedDays = 0
                    if ([int]::TryParse($InputValue.DaysUntilExpiry.ToString(), [ref]$parsedDays) -and $parsedDays -gt 0) {
                        $expiryDays = $parsedDays
                    }
                }
            }

            $DepTokens = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings' -tenantid $TenantFilter
            $AlertData = foreach ($Dep in $DepTokens) {
                if ($Dep.tokenExpirationDateTime -lt (Get-Date).AddDays($expiryDays) -and $Dep.tokenExpirationDateTime -gt (Get-Date).AddDays(-7)) {
                    $Message = 'Apple Device Enrollment Program token expiring on {0}' -f ([datetime]$Dep.tokenExpirationDateTime).ToString('yyyy-MM-dd')
                    $Dep | Select-Object -Property tokenName, @{Name = 'Message'; Expression = { $Message } }
                }
            }
            if ($AlertData) {
                Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
            }

        } catch {}


    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Failed to check Apple Device Enrollment Program token expiry for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
