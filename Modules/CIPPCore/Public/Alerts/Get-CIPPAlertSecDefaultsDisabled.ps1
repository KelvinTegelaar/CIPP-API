function Get-CIPPAlertSecDefaultsDisabled {
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
        # Check if Security Defaults is disabled
        $SecDefaults = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $TenantFilter)

        if ($SecDefaults.isEnabled -eq $false) {
            # Security Defaults is disabled, now check if there are any CA policies
            $CAPolicies = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' -tenantid $TenantFilter)

            if (!$CAPolicies -or $CAPolicies.Count -eq 0) {
                # Security Defaults is off AND no CA policies exist
                $AlertData = [PSCustomObject]@{
                    Message = 'Security Defaults is disabled and no Conditional Access policies are configured. This tenant has no baseline security protection.'
                    Tenant  = $TenantFilter
                }

                Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
            }
        }
    } catch {
        Write-LogMessage -API 'Alerts' -tenant $($TenantFilter) -message "Security Defaults Disabled Alert: Error occurred: $(Get-NormalizedError -message $_.Exception.message)" -sev Error
    }
}
