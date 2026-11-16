function Get-CIPPMobileDevice {
    <#
    .SYNOPSIS
        Exchange mobile devices for a tenant, with the owning mailbox's address and allow/block list entry
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $Devices = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MobileDevice' -cmdParams @{ ResultSize = 'Unlimited' })
    if ($Devices.Count -eq 0) { return }

    # A device's Identity starts with its mailbox's Name, the only link back to the mailbox
    $MailboxNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Device in $Devices) { $null = $MailboxNames.Add(([string]$Device.Identity -split '\\')[0]) }
    $Mailboxes = @{}
    New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-CASMailbox' -Select 'Name,PrimarySmtpAddress,ActiveSyncAllowedDeviceIDs,ActiveSyncBlockedDeviceIDs' -StreamPages | ForEach-Object {
        foreach ($Mailbox in $_.Value) {
            if ($MailboxNames.Contains([string]$Mailbox.Name)) { $Mailboxes[[string]$Mailbox.Name] = $Mailbox }
        }
    }

    foreach ($Device in $Devices) {
        $MailboxName = ([string]$Device.Identity -split '\\')[0]
        $Mailbox = $Mailboxes[$MailboxName]
        [PSCustomObject]@{
            userDisplayName         = $Device.UserDisplayName
            primarySmtpAddress      = if ($Mailbox.PrimarySmtpAddress) { [string]$Mailbox.PrimarySmtpAddress } else { $MailboxName }
            deviceFriendlyName      = if ([string]::IsNullOrEmpty($Device.FriendlyName)) { 'Unknown' } else { $Device.FriendlyName }
            deviceModel             = $Device.DeviceModel
            deviceOS                = $Device.DeviceOS
            deviceType              = $Device.DeviceType
            clientType              = $Device.ClientType
            clientVersion           = $Device.ClientVersion
            deviceAccessState       = $Device.DeviceAccessState
            # Why the state applies: Global (tenant default), Individual (the mailbox's allow/block list), DeviceRule, Policy
            deviceAccessStateReason = $Device.DeviceAccessStateReason
            deviceAccessControlRule = $Device.DeviceAccessControlRule
            mailboxAccessList       = if ($Device.DeviceId -and $Device.DeviceId -in $Mailbox.ActiveSyncAllowedDeviceIDs) { 'Allowed' } elseif ($Device.DeviceId -and $Device.DeviceId -in $Mailbox.ActiveSyncBlockedDeviceIDs) { 'Blocked' } else { $null }
            firstSyncTime           = if ($Device.FirstSyncTime) { ([datetime]$Device.FirstSyncTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
            lastSyncAttemptTime     = if ($Device.LastSyncAttemptTime) { ([datetime]$Device.LastSyncAttemptTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
            lastSuccessSync         = if ($Device.LastSuccessSync) { ([datetime]$Device.LastSuccessSync).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
            syncInfoNote            = if ($Device.DeviceModel -match 'Outlook' -or $Device.DeviceType -eq 'Outlook' -or $Device.ClientType -eq 'Outlook') { 'Outlook for iOS and Android uses modern authentication and does not report ActiveSync sync times.' } else { $null }
            deviceID                = $Device.DeviceId
            identity                = $Device.Identity
            Guid                    = $Device.Guid
        }
    }
}
