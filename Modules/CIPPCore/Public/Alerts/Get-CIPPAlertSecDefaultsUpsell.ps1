function Get-CIPPAlertSecDefaultsUpsell {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        $input,
        $TenantFilter
    )

    try {
        try {
            $SecDefaults = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $TenantFilter)
            if ($SecDefaults.isEnabled -eq $false -and $SecDefaults.securityDefaultsUpsell.action -in @('autoEnable', 'autoEnabledNotify')) {
                $AlertData = 'Security Defaults will be automatically enabled on {0}' -f $SecDefaults.securityDefaultsUpsell.dueDateTime
                Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

            }
        } catch {}

    } catch {
        # Error handling
    }
}

