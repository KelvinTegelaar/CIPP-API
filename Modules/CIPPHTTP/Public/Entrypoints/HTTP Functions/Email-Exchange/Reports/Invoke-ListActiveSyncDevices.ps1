function Invoke-ListActiveSyncDevices {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.TenantFilter

    try {
        $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MobileDevice' -cmdParams @{ ResultSize = 'Unlimited' } |
            Select-Object @{ Name = 'userDisplayName'; Expression = { $_.UserDisplayName } },
            @{ Name = 'userPrincipalName'; Expression = { ($_.Identity -split '\\')[0] } },
            @{ Name = 'deviceFriendlyName'; Expression = { if ([string]::IsNullOrEmpty($_.FriendlyName)) { 'Unknown' } else { $_.FriendlyName } } },
            @{ Name = 'deviceModel'; Expression = { $_.DeviceModel } },
            @{ Name = 'deviceOS'; Expression = { $_.DeviceOS } },
            @{ Name = 'deviceType'; Expression = { $_.DeviceType } },
            @{ Name = 'clientType'; Expression = { $_.ClientType } },
            @{ Name = 'clientVersion'; Expression = { $_.ClientVersion } },
            @{ Name = 'deviceAccessState'; Expression = { $_.DeviceAccessState } },
            @{ Name = 'firstSyncTime'; Expression = { if ($_.FirstSyncTime) { $_.FirstSyncTime.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null } } },
            @{ Name = 'lastSyncAttemptTime'; Expression = { if ($_.LastSyncAttemptTime) { $_.LastSyncAttemptTime.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null } } },
            @{ Name = 'lastSuccessSync'; Expression = { if ($_.LastSuccessSync) { $_.LastSuccessSync.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null } } },
            @{ Name = 'syncInfoNote'; Expression = { if ($_.DeviceModel -match 'Outlook' -or $_.DeviceType -eq 'Outlook' -or $_.ClientType -eq 'Outlook') { 'Outlook for iOS and Android uses modern authentication and does not report ActiveSync sync times.' } else { $null } } },
            @{ Name = 'deviceID'; Expression = { $_.DeviceId } },
            @{ Name = 'identity'; Expression = { $_.Identity } },
            @{ Name = 'Guid'; Expression = { $_.Guid } }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}
