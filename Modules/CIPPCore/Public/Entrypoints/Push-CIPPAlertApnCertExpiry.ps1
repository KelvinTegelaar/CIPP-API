function Push-CIPPAlertApnCertExpiry {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $Item
    )

    try {
        $Apn = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/applePushNotificationCertificate' -tenantid $Item.tenant
        if ($Apn.expirationDateTime -lt (Get-Date).AddDays(30) -and $Apn.expirationDateTime -gt (Get-Date).AddDays(-7)) {
            Write-AlertMessage -tenant $($Item.tenant) -message ('Intune: Apple Push Notification certificate for {0} is expiring on {1}' -f $Apn.appleIdentifier, $Apn.expirationDateTime)
        }
    } catch {
        #no error because if a tenant does not have an APN, it'll error anyway.
        #Write-AlertMessage -tenant $($Item.Tenant) -message "Failed to check APN certificate expiry for $($Item.Tenant): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
