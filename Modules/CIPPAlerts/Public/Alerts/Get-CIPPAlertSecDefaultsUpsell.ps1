function Get-CIPPAlertSecDefaultsUpsell {
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
            $SecDefaults = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $TenantFilter)
            if ($SecDefaults.isEnabled -eq $false -and $SecDefaults.securityDefaultsUpsell.action -in @('autoEnable', 'autoEnabledNotify')) {
                $AlertData = [PSCustomObject]@{
                    Message        = ('Security Defaults will be automatically enabled on {0}' -f $SecDefaults.securityDefaultsUpsell.dueDateTime)
                    EnablementDate = $SecDefaults.securityDefaultsUpsell.dueDateTime
                    Action         = $SecDefaults.securityDefaultsUpsell.action
                    Tenant         = $TenantFilter
                }
                Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

            }
        } catch {
            Write-Warning "Security Defaults upsell check skipped for $TenantFilter (feature may not be available): $($_.Exception.Message)"
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Failed to check Security Defaults upsell for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}

