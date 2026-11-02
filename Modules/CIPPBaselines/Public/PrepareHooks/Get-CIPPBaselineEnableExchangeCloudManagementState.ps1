function Get-CIPPBaselineEnableExchangeCloudManagementState {
    <#
    .SYNOPSIS
        Prepare hook for EnableExchangeCloudManagement: directory-synced mailboxes whose
        Exchange attributes are not managed where the baseline wants them.
    .DESCRIPTION
        Only dir-synced mailboxes are in scope: a cloud-only mailbox has no on-premises
        Exchange to manage it, so the property is meaningless there. The write targets
        ExternalDirectoryObjectId, matching the classic standard.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    $Mailboxes = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_ })
    if ($Mailboxes.Count -eq 0) { return @{ Current = $null } }

    $Desired = "$($Item.Variables.state)" -in @('True', 'true', '1')
    $Offending = @($Mailboxes | Where-Object {
            $_.IsDirSynced -eq $true -and [bool]$_.IsExchangeCloudManaged -ne $Desired
        })

    @{
        Current = [PSCustomObject]@{
            offenders = @($Offending.UPN | Sort-Object)
            targets   = @($Offending | ForEach-Object { [PSCustomObject]@{ id = "$($_.ExternalDirectoryObjectId)" } })
        }
    }
}
