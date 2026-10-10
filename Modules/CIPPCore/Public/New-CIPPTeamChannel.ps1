function New-CIPPTeamChannel {
    <#
    .SYNOPSIS
    Create a channel on a Microsoft Team

    .DESCRIPTION
    Creates a public (standard), private, or shared channel via the Graph Teams API, with an
    optional layoutType (post or chat). Private and shared channels include the Site Owner as
    the sole owner member. Shared channel creates are async (202); this helper polls the
    operation then resolves the channel by name. If a channel with the same display name
    already exists it is returned instead. The reserved name "General" is refused.

    .PARAMETER GroupId
    The Team / M365 group id

    .PARAMETER ChannelName
    Display name of the channel

    .PARAMETER MembershipType
    standard (public), private, or shared

    .PARAMETER LayoutType
    post (default) or chat

    .PARAMETER Owner
    UPN of the channel owner. Required for private and shared channels under application permissions.

    .PARAMETER TenantFilter
    The tenant the Team belongs to
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupId,

        [Parameter(Mandatory = $true)]
        [string]$ChannelName,

        [ValidateSet('standard', 'private', 'shared')]
        [string]$MembershipType = 'standard',

        [ValidateSet('post', 'chat')]
        [string]$LayoutType = 'post',

        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        $APIName = 'Create Team Channel',
        $Headers
    )

    $TrimmedName = $ChannelName.Trim()
    if (-not $TrimmedName) {
        throw 'Channel name is required.'
    }
    if ($TrimmedName -ieq 'General') {
        throw 'Channel name "General" is reserved and cannot be created by the template.'
    }

    $PreferShared = @{ Prefer = 'include-unknown-enum-members' }

    # Idempotency: reuse an existing channel with the same display name.
    try {
        $ExistingChannels = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/teams/$GroupId/channels?`$select=id,displayName,membershipType,layoutType" -tenantid $TenantFilter -AsApp $true -extraHeaders $PreferShared
        $Match = @($ExistingChannels) | Where-Object { $_.displayName -ieq $TrimmedName } | Select-Object -First 1
        if ($Match.id) {
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Channel $TrimmedName already exists on team $GroupId, reusing it." -sev Info
            return [PSCustomObject]@{
                ChannelId      = $Match.id
                DisplayName    = $Match.displayName
                MembershipType = $Match.membershipType
                LayoutType     = $Match.layoutType
                Created        = $false
            }
        }
    } catch {
        # Listing can fail transiently right after Team create; fall through to create.
    }

    if (-not $PSCmdlet.ShouldProcess($TrimmedName, "Create $MembershipType ($LayoutType) channel on team $GroupId")) { return }

    $ChannelBody = @{
        displayName    = $TrimmedName
        membershipType = $MembershipType
        layoutType     = $LayoutType
    }
    if ($MembershipType -in @('private', 'shared')) {
        $ChannelBody.members = @(
            @{
                '@odata.type'     = '#microsoft.graph.aadUserConversationMember'
                'roles'           = @('owner')
                'user@odata.bind' = "https://graph.microsoft.com/v1.0/users('$Owner')"
            }
        )
    }
    # Host team can see the shared channel immediately (same pattern as Graph example 7).
    if ($MembershipType -eq 'shared') {
        $ChannelBody.sharedWithTeams = @(
            @{ id = $GroupId }
        )
    }

    try {
        $Body = ConvertTo-Json -Depth 10 -Compress -InputObject $ChannelBody

        if ($MembershipType -eq 'shared') {
            # Shared channel create returns 202 + Content-Location to a teamsAsyncOperation.
            $ResponseHeaders = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/teams/$GroupId/channels" -tenantid $TenantFilter -type POST -body $Body -AsApp $true -returnHeaders $true -AddedHeaders $PreferShared
            $ContentLocation = [string](($ResponseHeaders.'Content-Location' | Select-Object -First 1) ?? ($ResponseHeaders.'Location' | Select-Object -First 1))
            if ($ContentLocation) {
                $OperationUri = if ($ContentLocation -match '^https?://') {
                    $ContentLocation
                } else {
                    "https://graph.microsoft.com/v1.0$ContentLocation"
                }
                $Attempts = 0
                $OperationStatus = $null
                do {
                    $Attempts++
                    try {
                        $Operation = New-GraphGetRequest -uri $OperationUri -tenantid $TenantFilter -AsApp $true
                        $OperationStatus = [string]$Operation.status
                        if ($OperationStatus -in @('succeeded', 'failed', 'failedWithError')) { break }
                    } catch {
                        # Keep polling while the operation resource appears.
                    }
                    if ($Attempts -lt 20) { Start-Sleep -Seconds 3 }
                } while ($Attempts -lt 20)

                if ($OperationStatus -notin @('succeeded', $null, '')) {
                    if ($OperationStatus -in @('failed', 'failedWithError')) {
                        throw "Shared channel '$TrimmedName' async create failed (status: $OperationStatus)."
                    }
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Shared channel $TrimmedName operation still '$OperationStatus' after polling; resolving by name." -sev Warning
                }
            }

            # Resolve the created channel by display name (202 path does not return the channel body).
            $Resolved = $null
            $ResolveAttempts = 0
            do {
                $ResolveAttempts++
                try {
                    $Listed = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/teams/$GroupId/channels?`$select=id,displayName,membershipType,layoutType" -tenantid $TenantFilter -AsApp $true -extraHeaders $PreferShared
                    $Resolved = @($Listed) | Where-Object { $_.displayName -ieq $TrimmedName } | Select-Object -First 1
                } catch {}
                if (-not $Resolved.id -and $ResolveAttempts -lt 10) { Start-Sleep -Seconds 3 }
            } while (-not $Resolved.id -and $ResolveAttempts -lt 10)

            if (-not $Resolved.id) {
                throw "Shared channel '$TrimmedName' was accepted but could not be resolved on team $GroupId yet."
            }

            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully created shared ($LayoutType) channel $TrimmedName on team $GroupId" -sev Info
            return [PSCustomObject]@{
                ChannelId      = $Resolved.id
                DisplayName    = $Resolved.displayName
                MembershipType = $Resolved.membershipType
                LayoutType     = ($Resolved.layoutType ?? $LayoutType)
                Created        = $true
            }
        }

        $NewChannel = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/teams/$GroupId/channels" -tenantid $TenantFilter -type POST -body $Body -AsApp $true -AddedHeaders $PreferShared
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully created $MembershipType ($LayoutType) channel $TrimmedName on team $GroupId" -sev Info
        return [PSCustomObject]@{
            ChannelId      = $NewChannel.id
            DisplayName    = $NewChannel.displayName
            MembershipType = $NewChannel.membershipType
            LayoutType     = ($NewChannel.layoutType ?? $LayoutType)
            Created        = $true
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create channel $TrimmedName on team $GroupId. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        throw $Result
    }
}
