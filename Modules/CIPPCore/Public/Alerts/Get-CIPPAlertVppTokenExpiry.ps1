function Get-CIPPAlertVppTokenExpiry {
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
            $VppTokens = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceAppManagement/vppTokens' -tenantid $TenantFilter
            $AlertData = foreach ($Vpp in $VppTokens) {
                if ($Vpp.state -ne 'valid') {
                    $Message = 'Apple Volume Purchase Program Token is not valid, new token required'
                    $Vpp | Select-Object -Property organizationName, appleId, vppTokenAccountType, @{Name = 'Message'; Expression = { $Message } }
                } elseif ($Vpp.expirationDateTime -lt (Get-Date).AddDays(30).ToUniversalTime() -and $Vpp.expirationDateTime -gt (Get-Date).AddDays(-7).ToUniversalTime()) {
                    $Message = 'Apple Volume Purchase Program token expiring on {0}' -f $Vpp.expirationDateTime
                    $Vpp | Select-Object -Property organizationName, appleId, vppTokenAccountType, @{Name = 'Message'; Expression = { $Message } }
                }
            }
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

        } catch {}

    } catch {
        # Error handling
    }
}
