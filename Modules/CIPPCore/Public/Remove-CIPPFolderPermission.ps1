function Remove-CIPPFolderPermission {
    <#
    .SYNOPSIS
        Remove a mailbox folder permission, resolving grantees that share a display name.

    .DESCRIPTION
        Get-MailboxFolderPermission reports grantees by display name only, so a display name is all
        CIPP has to send back. Exchange cannot resolve one shared by two recipients and throws
        ManagementObjectAmbiguousException.

        Recover from that with two calls: list the namesakes, then probe them all in a single bulk
        request whose OperationGuid maps each permission entry back to the recipient holding it.
        Namesakes that hold nothing come back as errors. Where more than one holds an entry,
        AccessRights identifies which listed row the caller acted on.

    .PARAMETER AccessRights
        Rights of the entry being removed, used to pick between namesakes who both hold one.

    .OUTPUTS
        The identifier the removal succeeded with.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$FolderIdentity,

        [Parameter(Mandatory = $true)]
        [string]$User,

        [Parameter(Mandatory = $false)]
        [string]$AccessRights,

        [Parameter(Mandatory = $false)]
        [string]$Anchor
    )

    if ([string]::IsNullOrWhiteSpace($Anchor)) { $Anchor = ($FolderIdentity -split ':\\')[0] }
    $Exo = @{ tenantid = $TenantFilter; Anchor = $Anchor }

    try {
        $null = New-ExoRequest @Exo -cmdlet 'Remove-MailboxFolderPermission' -cmdParams @{ Identity = $FolderIdentity; User = $User }
        return $User
    } catch {
        if ($_.Exception.Message -notmatch 'ManagementObjectAmbiguousException') { throw }
    }

    $Candidates = @(New-ExoRequest @Exo -cmdlet 'Get-Recipient' -cmdParams @{
            Filter     = "DisplayName -eq '$($User -replace "'", "''")'"
            ResultSize = 'Unlimited'
        } -Select 'PrimarySmtpAddress,Guid')

    $Probe = @(New-ExoBulkRequest -tenantid $TenantFilter -useSystemMailbox $true -cmdletArray @(
            foreach ($Candidate in $Candidates) {
                @{
                    CmdletInput   = @{ CmdletName = 'Get-MailboxFolderPermission'; Parameters = @{ Identity = $FolderIdentity; User = $Candidate.Guid } }
                    OperationGuid = $Candidate.Guid
                }
            }))
    $Holders = @($Probe | Where-Object { -not $_.error })

    if ($Holders.Count -gt 1 -and $AccessRights) {
        $Matched = @($Holders | Where-Object { ($_.AccessRights -join ', ') -eq $AccessRights })
        if ($Matched.Count -eq 1) { $Holders = $Matched }
    }

    if ($Holders.Count -ne 1) {
        $Addresses = @($Candidates | ForEach-Object { $_.PrimarySmtpAddress }) -join ', '
        throw "'$User' matches $($Candidates.Count) recipients ($Addresses), $($Holders.Count) of which hold matching permissions on $FolderIdentity. The entry cannot be identified - remove it by address in Exchange."
    }

    $Target = $Holders[0].OperationGuid
    $null = New-ExoRequest @Exo -cmdlet 'Remove-MailboxFolderPermission' -cmdParams @{ Identity = $FolderIdentity; User = $Target }
    Write-Information "Resolved '$User' to $(($Candidates | Where-Object { $_.Guid -eq $Target }).PrimarySmtpAddress) on $FolderIdentity"
    return $Target
}
