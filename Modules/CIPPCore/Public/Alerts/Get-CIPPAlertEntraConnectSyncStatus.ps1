
function Get-CIPPAlertEntraConnectSyncStatus {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {
        # Set Hours with fallback to 72 hours
        $Hours = if ($InputValue) { [int]$InputValue } else { 72 }
        $ConnectSyncStatus = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/organization?$select=onPremisesLastPasswordSyncDateTime,onPremisesLastSyncDateTime,onPremisesSyncEnabled' -tenantid $TenantFilter

        if ($ConnectSyncStatus.onPremisesSyncEnabled -eq $true) {
            $LastPasswordSync = $ConnectSyncStatus.onPremisesLastPasswordSyncDateTime
            $SyncDateTime = $ConnectSyncStatus.onPremisesLastSyncDateTime
            # Get the older of the two sync times
            $LastSync = if ($SyncDateTime -lt $LastPasswordSync) { $SyncDateTime; $Cause = 'DirectorySync' } else { $LastPasswordSync; $Cause = 'PasswordSync' }

            if ($LastSync -lt (Get-Date).AddHours(-$Hours).ToUniversalTime()) {

                $AlertData = @{
                    Message           = "Entra Connect $Cause for $($TenantFilter) has not run for over $Hours hours. Last sync was at $($LastSync.ToString('o'))"
                    LastSync          = $LastSync
                    Cause             = $Cause
                    LastPasswordSync  = $LastPasswordSync
                    LastDirectorySync = $SyncDateTime
                    Tenant            = $TenantFilter
                }
                Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
            }
        }
    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Could not get Entra Connect Sync Status for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
