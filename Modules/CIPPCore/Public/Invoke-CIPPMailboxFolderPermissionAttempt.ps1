function Invoke-CIPPMailboxFolderPermissionAttempt {
    <#
    .SYNOPSIS
        Run Remove/Set/Add-MailboxFolderPermission trying each resolved identity candidate.

    .DESCRIPTION
        Used when folder permission User values are display names that may collide.
        Tries each candidate until one Exchange cmdlets succeeds.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Remove', 'Set', 'Add')]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$FolderIdentity,

        [Parameter(Mandatory = $true)]
        [string[]]$Candidates,

        [Parameter(Mandatory = $false)]
        $Anchor,

        [Parameter(Mandatory = $false)]
        [string[]]$AccessRights,

        [Parameter(Mandatory = $false)]
        [bool]$SendNotificationToUser = $false,

        [Parameter(Mandatory = $false)]
        [string]$SharingPermissionFlags
    )

    $LastError = $null
    $UniqueCandidates = @($Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

    if ($UniqueCandidates.Count -eq 0) {
        throw 'No identity candidates available for mailbox folder permission operation'
    }

    foreach ($Candidate in $UniqueCandidates) {
        try {
            switch ($Action) {
                'Remove' {
                    $CmdParams = @{
                        Identity = $FolderIdentity
                        User     = $Candidate
                    }
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-MailboxFolderPermission' -cmdParams $CmdParams -Anchor $Anchor
                }
                'Set' {
                    $CmdParams = @{
                        Identity               = $FolderIdentity
                        User                   = $Candidate
                        AccessRights           = @($AccessRights)
                        SendNotificationToUser = $SendNotificationToUser
                    }
                    if ($SharingPermissionFlags) {
                        $CmdParams['SharingPermissionFlags'] = $SharingPermissionFlags
                    }
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxFolderPermission' -cmdParams $CmdParams -Anchor $Anchor
                }
                'Add' {
                    $CmdParams = @{
                        Identity               = $FolderIdentity
                        User                   = $Candidate
                        AccessRights           = @($AccessRights)
                        SendNotificationToUser = $SendNotificationToUser
                    }
                    if ($SharingPermissionFlags) {
                        $CmdParams['SharingPermissionFlags'] = $SharingPermissionFlags
                    }
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Add-MailboxFolderPermission' -cmdParams $CmdParams -Anchor $Anchor
                }
            }
            return [PSCustomObject]@{
                Success   = $true
                UsedUser  = $Candidate
                TriedUser = $UniqueCandidates
            }
        } catch {
            $Normalized = (Get-CippException -Exception $_).NormalizedError
            $Retryable = $Normalized -match 'UserNotFoundInPermissionEntryException|InvalidExternalUserIdException|Couldn.?t find user|couldn.?t be found|no existing permission entry'
            $LastError = $_
            if (-not $Retryable) {
                throw
            }
            Write-Information "Folder permission $Action failed for candidate '$Candidate': $Normalized — trying next identity"
        }
    }

    $Tried = $UniqueCandidates -join ', '
    $Msg = (Get-CippException -Exception $LastError).NormalizedError
    throw "Failed after trying identities [$Tried]: $Msg"
}
