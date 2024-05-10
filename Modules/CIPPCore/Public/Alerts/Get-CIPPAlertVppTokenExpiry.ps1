function Get-CIPPAlertVppTokenExpiry {
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
            $VppTokens = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceAppManagement/vppTokens' -tenantid $TenantFilter).value
            foreach ($Vpp in $VppTokens) {
                if ($Vpp.state -ne 'valid') {
                    'Apple Volume Purchase Program Token is not valid, new token required'
                }
                if ($Vpp.expirationDateTime -lt (Get-Date).AddDays(30) -and $Vpp.expirationDateTime -gt (Get-Date).AddDays(-7)) {
                    'Apple Volume Purchase Program token expiring on {0}' -f $Vpp.expirationDateTime
                }
            }
        } catch {}
        
    } catch {
        # Error handling
    }
}