function Get-CIPPAlertApnCertExpiry {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

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

        $Apn = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/applePushNotificationCertificate' -tenantid $TenantFilter
        $AlertData = if ($Apn.expirationDateTime -lt (Get-Date).AddDays($expiryDays) -and $Apn.expirationDateTime -gt (Get-Date).AddDays(-7)) {
            $Apn | Select-Object -Property appleIdentifier, expirationDateTime
        }
        if ($AlertData) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }

    } catch {
        #no error because if a tenant does not have an APN, it'll error anyway.
        #$ErrorMessage = Get-CippException -Exception $_
        #Write-AlertMessage -tenant $($TenantFilter) -message "Failed to check APN certificate expiry for $($TenantFilter): $($ErrorMessage.NormalizedError)"
    }
}
