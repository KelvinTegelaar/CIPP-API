using namespace System.Net

function Invoke-ListUserMailboxDetails {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $UserID = $Request.Query.UserID

    try {
        $Requests = @(
            @{
                CmdletInput = @{
                    CmdletName = 'Get-Mailbox'
                    Parameters = @{ Identity = $UserID }
                }
            },
            @{
                CmdletInput = @{
                    CmdletName = 'Get-MailboxPermission'
                    Parameters = @{ Identity = $UserID }
                }
            },
            @{
                CmdletInput = @{
                    CmdletName = 'Get-CASMailbox'
                    Parameters = @{ Identity = $UserID }
                }
            },
            @{
                CmdletInput = @{
                    CmdletName = 'Get-OrganizationConfig'
                }
            },
            @{
                CmdletInput = @{
                    CmdletName = 'Get-MailboxStatistics'
                    Parameters = @{ Identity = $UserID; Archive = $true }
                }
            },
            @{
                CmdletInput = @{
                    CmdletName = 'Get-BlockedSenderAddress'
                    Parameters = @{ Identity = $UserID }
                }
            },
            @{
                CmdletInput = @{
                    CmdletName = 'Get-RecipientPermission'
                    Parameters = @{ Identity = $UserID }
                }
            }
        )
        Write-Host $UserID
        $usernames = New-GraphGetRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/beta/users?$select=id,userPrincipalName&$top=999'
        $Results = New-ExoBulkRequest -TenantId $TenantFilter -CmdletArray $Requests -returnWithCommand $true -Anchor $username
        Write-Host "First line of usernames is $($usernames[0] | ConvertTo-Json)"

        # Assign variables from $Results
        $MailboxDetailedRequest = $Results.'Get-Mailbox'
        $PermsRequest = $Results.'Get-MailboxPermission'
        $CASRequest = $Results.'Get-CASMailbox'
        $OrgConfig = $Results.'Get-OrganizationConfig'
        $ArchiveSizeRequest = $Results.'Get-MailboxStatistics'
        $BlockedSender = $Results.'Get-BlockedSenderAddress'
        $PermsRequest2 = $Results.'Get-RecipientPermission'

        $StatsRequest = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($TenantFilter)/Mailbox('$($UserID)')/Exchange.GetMailboxStatistics()" -Tenantid $TenantFilter -scope ExchangeOnline -noPagination $true


        # Handle ArchiveEnabled and AutoExpandingArchiveEnabled
        try {
            if ($MailboxDetailedRequest.ArchiveGuid -ne '00000000-0000-0000-0000-000000000000') {
                $ArchiveEnabled = $true
            } else {
                $ArchiveEnabled = $false
            }

            # Get organization config of auto-expanding archive if it's disabled on user level
            if (-not $MailboxDetailedRequest.AutoExpandingArchiveEnabled -and $ArchiveEnabled) {
                $AutoExpandingArchiveEnabled = $OrgConfig.AutoExpandingArchiveEnabled
            } else {
                $AutoExpandingArchiveEnabled = $MailboxDetailedRequest.AutoExpandingArchiveEnabled
            }
        } catch {
            $ArchiveEnabled = $false
            $ArchiveSizeRequest = @{
                TotalItemSize = '0'
                ItemCount     = '0'
            }
        }


        # Determine if the user is blocked for spam
        if ($BlockedSender -and $BlockedSender.Count -gt 0) {
            $BlockedForSpam = $false
        } else {
            $BlockedForSpam = $true
        }
    } catch {
        Write-Error "Failed Fetching Data $($_.Exception.message): $($_.InvocationInfo.ScriptLineNumber)"
    }

    # Parse permissions

    #Implemented as an arraylist that uses .add().
    $ParsedPerms = [System.Collections.ArrayList]::new()
    foreach ($PermSet in @($PermsRequest, $PermsRequest2)) {
        foreach ($Perm in $PermSet) {
            # Check if Trustee or User is not NT AUTHORITY\SELF
            $user = $Perm.Trustee ? $Perm.Trustee : $Perm.User
            if ($user -and $user -ne 'NT AUTHORITY\SELF') {
                $null = $ParsedPerms.Add([PSCustomObject]@{
                        User         = $user
                        AccessRights = ($Perm.AccessRights) -join ', '
                    })
            }
        }
    }
    if ($MailboxDetailedRequest.GrantSendOnBehalfTo) {
        $MailboxDetailedRequest.GrantSendOnBehalfTo | ForEach-Object {
            $id = $_
            $username = $usernames | Where-Object { $_.id -eq $id }

            $null = $ParsedPerms.Add([PSCustomObject]@{
                    User         = $username.UserPrincipalName ? $username.UserPrincipalName : $_
                    AccessRights = 'SendOnBehalf'
                })
        }
    }
    if ($ParsedPerms.Count -eq 0) {
        $ParsedPerms = @()
    }

    # Get forwarding address
    $ForwardingAddress = if ($MailboxDetailedRequest.ForwardingAddress) {
        try {
            (New-GraphGetRequest -TenantId $TenantFilter -Uri "https://graph.microsoft.com/beta/users/$($MailboxDetailedRequest.ForwardingAddress)").UserPrincipalName
        } catch {
            try {
                '{0} ({1})' -f $MailboxDetailedRequest.ForwardingAddress, (($((New-GraphGetRequest -TenantId $TenantFilter -Uri "https://graph.microsoft.com/beta/users?`$filter=displayName eq '$($MailboxDetailedRequest.ForwardingAddress)'") | Select-Object -First 1 -ExpandProperty UserPrincipalName)))
            } catch {
                $MailboxDetailedRequest.ForwardingAddress
            }
        }
    } elseif ($MailboxDetailedRequest.ForwardingSmtpAddress -and $MailboxDetailedRequest.ForwardingAddress) {
        "$($MailboxDetailedRequest.ForwardingAddress) $($MailboxDetailedRequest.ForwardingSmtpAddress)"
    } else {
        $MailboxDetailedRequest.ForwardingSmtpAddress
    }

    $ProhibitSendQuotaString = $MailboxDetailedRequest.ProhibitSendQuota -split ' '
    $ProhibitSendReceiveQuotaString = $MailboxDetailedRequest.ProhibitSendReceiveQuota -split ' '
    $TotalItemSizeString = $StatsRequest.TotalItemSize -split ' '
    $TotalArchiveItemSizeString = $ArchiveSizeRequest.TotalItemSize -split ' '

    $ProhibitSendQuota = try { [math]::Round([float]($ProhibitSendQuotaString[0]), 2) } catch { 0 }
    $ProhibitSendReceiveQuota = try { [math]::Round([float]($ProhibitSendReceiveQuotaString[0]), 2) } catch { 0 }

    $ItemSizeType = '1{0}' -f ($TotalItemSizeString[1] ?? 'Gb')
    $TotalItemSize = try { [math]::Round([float]($TotalItemSizeString[0]) / $ItemSizeType, 2) } catch { 0 }

    if ($ArchiveEnabled -eq $true) {
        $TotalArchiveItemSize = try { [math]::Round([float]($TotalArchiveItemSizeString[0]), 2) } catch { 0 }
        $TotalArchiveItemCount = try { [math]::Round($ArchiveSizeRequest.ItemCount, 2) } catch { 0 }
    }

    # Build the GraphRequest object
    $GraphRequest = [ordered]@{
        ForwardAndDeliver        = $MailboxDetailedRequest.DeliverToMailboxAndForward
        ForwardingAddress        = $ForwardingAddress
        LitigationHold           = $MailboxDetailedRequest.LitigationHoldEnabled
        HiddenFromAddressLists   = $MailboxDetailedRequest.HiddenFromAddressListsEnabled
        EWSEnabled               = $CASRequest.EwsEnabled
        MailboxMAPIEnabled       = $CASRequest.MAPIEnabled
        MailboxOWAEnabled        = $CASRequest.OWAEnabled
        MailboxImapEnabled       = $CASRequest.ImapEnabled
        MailboxPopEnabled        = $CASRequest.PopEnabled
        MailboxActiveSyncEnabled = $CASRequest.ActiveSyncEnabled
        Permissions              = @($ParsedPerms)
        ProhibitSendQuota        = $ProhibitSendQuota
        ProhibitSendReceiveQuota = $ProhibitSendReceiveQuota
        ItemCount                = [math]::Round($StatsRequest.ItemCount, 2)
        TotalItemSize            = $TotalItemSize
        TotalArchiveItemSize     = $TotalArchiveItemSize
        TotalArchiveItemCount    = $TotalArchiveItemCount
        BlockedForSpam           = $BlockedForSpam
        ArchiveMailBox           = $ArchiveEnabled
        AutoExpandingArchive     = $AutoExpandingArchiveEnabled
        RecipientTypeDetails     = $MailboxDetailedRequest.RecipientTypeDetails
        Mailbox                  = $MailboxDetailedRequest
        MailboxActionsData       = ($MailboxDetailedRequest | Select-Object id, ExchangeGuid, ArchiveGuid, WhenSoftDeleted, @{ Name = 'UPN'; Expression = { $_.'UserPrincipalName' } },
            @{ Name = 'displayName'; Expression = { $_.'DisplayName' } },
            @{ Name = 'primarySmtpAddress'; Expression = { $_.'PrimarySMTPAddress' } },
            @{ Name = 'recipientType'; Expression = { $_.'RecipientType' } },
            @{ Name = 'recipientTypeDetails'; Expression = { $_.'RecipientTypeDetails' } },
            @{ Name = 'AdditionalEmailAddresses'; Expression = { ($_.'EmailAddresses' | Where-Object { $_ -clike 'smtp:*' }).Replace('smtp:', '') -join ', ' } },
            @{Name = 'ForwardingSmtpAddress'; Expression = { $_.'ForwardingSmtpAddress' -replace 'smtp:', '' } },
            @{Name = 'InternalForwardingAddress'; Expression = { $_.'ForwardingAddress' } },
            DeliverToMailboxAndForward,
            HiddenFromAddressListsEnabled,
            ExternalDirectoryObjectId,
            MessageCopyForSendOnBehalfEnabled,
            MessageCopyForSentAsEnabled)
    } # Select statement taken from ListMailboxes to save a EXO request

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })
}
