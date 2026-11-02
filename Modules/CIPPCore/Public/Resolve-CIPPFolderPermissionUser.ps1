function Resolve-CIPPFolderPermissionUser {
    <#
    .SYNOPSIS
        Attach a unique recipient id to each mailbox folder permission entry.

    .DESCRIPTION
        Get-MailboxFolderPermission identifies grantees by display name, which Exchange cannot
        resolve when two recipients share one. Resolve every grantee in a single bulk request. Names
        matching several recipients need a second bulk request that probes each candidate against
        the folder, so an entry can be attributed to the recipient actually holding it - including
        when two namesakes hold entries with identical rights, since each row is handed a distinct
        holder and stays individually removable.

        Rows keep a null UserId when nothing resolves, which leaves callers on the display-name path.

    .OUTPUTS
        The permission entries, each with a UserId property added.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$FolderIdentity,

        [Parameter(Mandatory = $false)]
        $Permissions
    )

    $Rows = @($Permissions)
    $Names = @($Rows | Where-Object { $_.User -notin 'Default', 'Anonymous', 'NT AUTHORITY\SELF' } | Select-Object -ExpandProperty User -Unique)
    if ($Names.Count -eq 0) { return $Rows }

    $Recipients = @(New-ExoBulkRequest -tenantid $TenantFilter -useSystemMailbox $true -Select 'PrimarySmtpAddress,Guid' -cmdletArray @(
            foreach ($Name in $Names) {
                @{
                    CmdletInput   = @{ CmdletName = 'Get-Recipient'; Parameters = @{ Filter = "DisplayName -eq '$($Name -replace "'", "''")'"; ResultSize = 'Unlimited' } }
                    OperationGuid = $Name
                }
            }) | Where-Object { $_.Guid })

    $ByName = @{}
    foreach ($Group in $Recipients | Group-Object OperationGuid) { $ByName[$Group.Name] = @($Group.Group) }

    $Ambiguous = @($ByName.Keys | Where-Object { $ByName[$_].Count -gt 1 })
    $Holders = @{}
    if ($Ambiguous.Count -gt 0) {
        $Probe = @(New-ExoBulkRequest -tenantid $TenantFilter -useSystemMailbox $true -cmdletArray @(
                foreach ($Name in $Ambiguous) {
                    foreach ($Candidate in $ByName[$Name]) {
                        @{
                            CmdletInput   = @{ CmdletName = 'Get-MailboxFolderPermission'; Parameters = @{ Identity = $FolderIdentity; User = $Candidate.Guid } }
                            OperationGuid = $Candidate.Guid
                        }
                    }
                }))
        foreach ($Entry in $Probe | Where-Object { -not $_.error }) {
            $Key = '{0}|{1}' -f $Entry.User, ($Entry.AccessRights -join ', ')
            if (-not $Holders.ContainsKey($Key)) { $Holders[$Key] = [System.Collections.Generic.Queue[string]]::new() }
            $Holders[$Key].Enqueue($Entry.OperationGuid)
        }
    }

    foreach ($Row in $Rows) {
        $UserId = $null
        $Resolved = $ByName[[string]$Row.User]
        if ($Resolved.Count -eq 1) {
            $UserId = $Resolved[0].Guid
        } elseif ($Resolved.Count -gt 1) {
            $Key = '{0}|{1}' -f $Row.User, ($Row.AccessRights -join ', ')
            if ($Holders.ContainsKey($Key) -and $Holders[$Key].Count -gt 0) { $UserId = $Holders[$Key].Dequeue() }
        }
        $Row | Add-Member -NotePropertyName 'UserId' -NotePropertyValue $UserId -Force
    }

    return $Rows
}
