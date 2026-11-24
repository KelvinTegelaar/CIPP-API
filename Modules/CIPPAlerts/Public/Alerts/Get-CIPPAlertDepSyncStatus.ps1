function Get-CIPPAlertDepSyncStatus {
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
        $Hours = 0
        if (-not [int]::TryParse("$InputValue", [ref]$Hours) -or $Hours -le 0) { $Hours = 24 }
        $Cutoff = [datetime]::UtcNow.AddHours(-$Hours)
        $SyncErrors = @{
            1 = 'the token has expired'
            2 = 'the sync state is unknown'
            3 = 'new Apple Business Manager terms are waiting to be accepted'
            4 = 'the sync completed with a warning'
        }

        $DepTokens = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings' -tenantid $TenantFilter
        $AlertData = foreach ($Token in $DepTokens) {
            $LastSync = if ($Token.lastSuccessfulSyncDateTime) { ([datetime]$Token.lastSuccessfulSyncDateTime).ToUniversalTime() }
            $ErrorCode = [int]$Token.lastSyncErrorCode
            $Stale = -not $LastSync -or $LastSync -lt $Cutoff
            if ($ErrorCode -eq 0 -and -not $Stale) { continue }

            $Reasons = @(
                if ($ErrorCode -ne 0) { 'the last sync failed: {0} (code {1})' -f ($SyncErrors[$ErrorCode] ?? 'unknown error'), $ErrorCode }
                if ($Stale) { 'it has not synced successfully in over {0} hours' -f $Hours }
            )
            [PSCustomObject]@{
                Id                         = "DepSync-$($Token.id)"
                Message                    = 'Apple Device Enrollment Program token {0} needs attention: {1}. Check it in Intune under Devices > Enrollment > Apple > Enrollment program tokens.' -f $Token.tokenName, ($Reasons -join '; ')
                TokenName                  = $Token.tokenName
                AppleIdentifier            = $Token.appleIdentifier
                LastSyncErrorCode          = $ErrorCode
                LastSuccessfulSyncDateTime = $LastSync
                LastSyncTriggeredDateTime  = $Token.lastSyncTriggeredDateTime
                SyncedDeviceCount          = $Token.syncedDeviceCount
                Tenant                     = $TenantFilter
            }
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Failed to check Apple Device Enrollment Program sync status for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
