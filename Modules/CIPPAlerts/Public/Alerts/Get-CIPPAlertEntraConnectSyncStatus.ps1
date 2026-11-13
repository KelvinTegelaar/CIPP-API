
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
            # Get the older of the two sync times. Password sync is null on PTA/federated tenants, so skip missing ones.
            $Oldest = @(
                [PSCustomObject]@{ Cause = 'PasswordSync'; Time = $LastPasswordSync }
                [PSCustomObject]@{ Cause = 'DirectorySync'; Time = $SyncDateTime }
            ) | Where-Object { $_.Time } | Sort-Object Time | Select-Object -First 1
            $LastSync = $Oldest.Time
            $Cause = $Oldest.Cause

            if ($LastSync -and $LastSync -lt (Get-Date).AddHours(-$Hours).ToUniversalTime()) {

                $AlertData = @{
                    Id                = "EntraConnectSync-$Cause" # stable identity; Message carries live hours
                    Message           = "Entra Connect $Cause for $($TenantFilter) has not run for over $Hours hours. Last sync was at $($LastSync.ToString('o'))"
                    LastSync          = $LastSync
                    Cause             = $Cause
                    LastPasswordSync  = $LastPasswordSync
                    LastDirectorySync = $SyncDateTime
                    Tenant            = $TenantFilter
                }
            }
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Could not get Entra Connect Sync Status for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
