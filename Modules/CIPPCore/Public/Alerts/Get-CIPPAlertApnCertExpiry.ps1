function Get-CIPPAlertApnCertExpiry {
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
        $Apn = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/applePushNotificationCertificate' -tenantid $TenantFilter
        $AlertData = if ($Apn.expirationDateTime -lt (Get-Date).AddDays(30) -and $Apn.expirationDateTime -gt (Get-Date).AddDays(-7)) {
            $Apn | Select-Object -Property appleIdentifier, expirationDateTime
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
        #no error because if a tenant does not have an APN, it'll error anyway.
        #Write-AlertMessage -tenant $($TenantFilter) -message "Failed to check APN certificate expiry for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
