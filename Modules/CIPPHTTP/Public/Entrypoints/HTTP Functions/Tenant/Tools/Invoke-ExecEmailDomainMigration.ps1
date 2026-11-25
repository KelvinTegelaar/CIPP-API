function Invoke-ExecEmailDomainMigration {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.DomainMigration.ReadWrite
    .SYNOPSIS
        Move users' and groups' sign-in names and primary email addresses from one domain to another
    .DESCRIPTION
        Plans or applies a move of users (and optionally shared mailboxes and groups) from SourceDomain to TargetDomain in
        one tenant. With Preview, returns the planned change per user or group without writing anything, flagging users
        whose sign-in name and primary email address differ (mismatch). Otherwise changes the selected Users: the sign-in
        name through Graph and the primary email address through Exchange, always together, keeping the old address as an
        alias. Groups only have their primary email address moved. Users whose sign-in name and primary email address
        would differ after the move, objects Entra still syncs from on-premises, and objects whose new address is already in use
        (unless SkipCollisions is false), are skipped with the reason. Users with a privileged admin role are skipped for
        callers without Identity.PrivilegedUser.ReadWrite. Action UseSignInNameAsEmail instead makes each selected
        mismatched user's sign-in name its primary email address, and UseEmailAsSignInName makes its primary email address
        its sign-in name; neither removes an address. Action AddAlias instead adds the TargetDomain address as an extra
        email address to each mailbox and group whose primary email address is on SourceDomain, changing neither its
        sign-in name nor its primary email address.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # The domain the sign-in names and addresses move from
    $SourceDomain = "$($Request.Body.SourceDomain)".Trim().ToLowerInvariant()
    # A verified domain the sign-in names and addresses move to
    $TargetDomain = "$($Request.Body.TargetDomain)".Trim().ToLowerInvariant()
    # Move (the default) moves to TargetDomain; AddAlias only adds the TargetDomain address as an alias; the other two make a mismatched sign-in name and primary email address match
    $Action = switch ("$($Request.Body.Action)") {
        '' { 'Move' }
        'Move' { 'Move' }
        'AddAlias' { 'AddAlias' }
        'UseSignInNameAsEmail' { 'UseSignInNameAsEmail' }
        'UseEmailAsSignInName' { 'UseEmailAsSignInName' }
    }
    $SkipCollisions = $Request.Body.SkipCollisions -ne $false
    $IncludeSharedMailboxes = [bool]$Request.Body.IncludeSharedMailboxes
    # Also move Microsoft 365 groups, distribution lists, mail-enabled security groups and dynamic distribution lists
    $IncludeGroups = [bool]$Request.Body.IncludeGroups
    # Return the plan without changing anything
    $Preview = [bool]$Request.Body.Preview
    # Ids of the users and groups to change, as the preview returns them; required unless Preview is set
    $SelectedIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@(foreach ($Id in $Request.Body.Users) { "$Id" }), [System.StringComparer]::OrdinalIgnoreCase)

    $DomainPattern = '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'
    $Invalid = if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
        'Choose a single tenant.'
    } elseif ($SourceDomain -notmatch $DomainPattern -or $TargetDomain -notmatch $DomainPattern) {
        'Choose the domain to move from and the domain to move to.'
    } elseif ($SourceDomain -eq $TargetDomain) {
        'The domain to move to must be different from the domain to move from.'
    } elseif (-not $Action) {
        'Choose Move, AddAlias, UseSignInNameAsEmail or UseEmailAsSignInName as the action.'
    } elseif (-not $Preview -and $SelectedIds.Count -eq 0) {
        'Choose at least one user or group to change.'
    } elseif ($SelectedIds.Count -gt 500) {
        'Change up to 500 users or groups at a time.'
    }
    if ($Invalid) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = $Invalid }
            })
    }

    try {
        $Domains = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/domains?$select=id,isVerified' -tenantid $TenantFilter)
        $VerifiedDomains = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Domains.Where({ $_.isVerified }).id), [System.StringComparer]::OrdinalIgnoreCase)
        if (-not $Domains.Where({ $_.id -eq $SourceDomain }, 'First')) {
            throw [System.ArgumentException]::new("$SourceDomain is not a domain of this tenant.")
        }
        if (-not $VerifiedDomains.Contains($TargetDomain)) {
            throw [System.ArgumentException]::new("$TargetDomain is not a verified domain of this tenant.")
        }

        $GraphUsers = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users?`$filter=endswith(userPrincipalName,'@$SourceDomain') or endswith(userPrincipalName,'@$TargetDomain')&`$select=id,displayName,userPrincipalName,userType&`$count=true&`$top=999" -tenantid $TenantFilter -ComplexFilter
        # Entra decides whether an object is still synced; Exchange's IsDirSynced can lag behind a source of authority switch
        $SyncedIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@(@(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/users?$filter=onPremisesSyncEnabled eq true&$select=id&$count=true&$top=999' -tenantid $TenantFilter -ComplexFilter).id), [System.StringComparer]::OrdinalIgnoreCase)
        if ($IncludeGroups) {
            foreach ($Group in (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/groups?$filter=onPremisesSyncEnabled eq true&$select=id&$count=true&$top=999' -tenantid $TenantFilter -ComplexFilter)) { [void]$SyncedIds.Add($Group.id) }
        }
        $Recipients = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Recipient' -cmdParams @{
            Filter     = "EmailAddresses -like '*@$SourceDomain' -or EmailAddresses -like '*@$TargetDomain'"
            ResultSize = 'Unlimited'
        } -Select 'ExternalDirectoryObjectId,Guid,DisplayName,WindowsLiveID,PrimarySmtpAddress,EmailAddresses,RecipientTypeDetails,IsExchangeCloudManaged'

        $GroupCmdlets = @{
            GroupMailbox                   = 'Set-UnifiedGroup'
            MailUniversalDistributionGroup = 'Set-DistributionGroup'
            MailUniversalSecurityGroup     = 'Set-DistributionGroup'
            MailNonUniversalGroup          = 'Set-DistributionGroup'
            DynamicDistributionGroup       = 'Set-DynamicDistributionGroup'
        }
        $SourceSuffix = "@$SourceDomain"
        $TargetSuffix = "@$TargetDomain"
        $Comparison = [System.StringComparison]::OrdinalIgnoreCase
        # Every sign-in name and email address already in use, and whose it is
        $Taken = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $UsersById = @{}
        $RecipientsById = @{}
        $CandidateIds = [System.Collections.Generic.List[string]]::new()
        foreach ($User in $GraphUsers) {
            $Taken[$User.userPrincipalName] = $User.id
            if ($User.userType -ne 'Guest' -and $User.userPrincipalName.EndsWith($SourceSuffix, $Comparison)) {
                $UsersById[$User.id] = $User
                $CandidateIds.Add($User.id)
            }
        }
        foreach ($Recipient in $Recipients) {
            $OwnerId = if ($Recipient.ExternalDirectoryObjectId) { [string]$Recipient.ExternalDirectoryObjectId } else { [string]$Recipient.Guid }
            foreach ($Address in $Recipient.EmailAddresses) {
                if ($Address.StartsWith('smtp:', $Comparison)) { $Taken[$Address.Substring(5)] = $OwnerId }
            }
            # Dynamic distribution lists have no Entra object, so they are keyed on their Exchange Guid
            $RecipientsById[$OwnerId] = $Recipient
            if (-not $UsersById.ContainsKey($OwnerId) -and "$($Recipient.PrimarySmtpAddress)".EndsWith($SourceSuffix, $Comparison)) { $CandidateIds.Add($OwnerId) }
        }

        $Rows = [System.Collections.Generic.List[object]]::new()
        $NewAddressLists = @{}
        foreach ($Id in $CandidateIds) {
            $User = $UsersById[$Id]
            $Recipient = $RecipientsById[$Id]
            $Type = if ($Recipient) { $Recipient.RecipientTypeDetails } else { 'User' }
            $IsGroup = $GroupCmdlets.ContainsKey($Type)
            if ($IsGroup) {
                if (-not $IncludeGroups) { continue }
            } elseif ($Type -notin 'User', 'UserMailbox', 'SharedMailbox' -or ($Type -eq 'SharedMailbox' -and -not $IncludeSharedMailboxes)) { continue }

            $Upn = if ($User) { $User.userPrincipalName } else { [string]$Recipient.WindowsLiveID }
            $NewUpn = if ($User) { $Upn.Substring(0, $Upn.LastIndexOf('@')) + $TargetSuffix }
            $Primary = if ($Recipient) { [string]$Recipient.PrimarySmtpAddress }
            $NewPrimary = if ($Type -ne 'User' -and $Primary.EndsWith($SourceSuffix, $Comparison)) { $Primary.Substring(0, $Primary.LastIndexOf('@')) + $TargetSuffix }
            $NewAlias = $null
            if ($Action -eq 'AddAlias') { $NewAlias = $NewPrimary; $NewUpn = $null; $NewPrimary = $null }
            if (-not $NewUpn -and -not $NewPrimary -and -not $NewAlias) { continue }
            # Microsoft no longer supports a mailbox whose sign-in name differs from its primary email address
            $FinalUpn = $NewUpn ?? $Upn
            $FinalPrimary = $NewPrimary ?? $Primary
            $Mismatch = -not $IsGroup -and $Type -ne 'User' -and -not [string]::Equals($FinalUpn, $FinalPrimary, $Comparison)
            switch ($Action) {
                'UseSignInNameAsEmail' { $NewUpn = $null; $NewPrimary = if ($Mismatch) { $Upn } }
                'UseEmailAsSignInName' { $NewUpn = if ($Mismatch) { $Primary }; $NewPrimary = $null }
            }

            $Collision = foreach ($Address in $NewUpn, $NewPrimary, $NewAlias) {
                if ($Address -and $Taken.ContainsKey($Address) -and $Taken[$Address] -ne $Id) { $Address; break }
            }
            $Reason = if ($SyncedIds.Contains($Id) -and $NewAlias -and $Recipient.IsExchangeCloudManaged -ne $true) {
                'Synced from on-premises Active Directory. Add the address there, or manage its Exchange attributes in the cloud.'
            } elseif ($SyncedIds.Contains($Id) -and -not $NewAlias) {
                'Synced from on-premises Active Directory. Change the sign-in name and email addresses there, or move its source of authority to the cloud.'
            } elseif ($Action -in 'UseSignInNameAsEmail', 'UseEmailAsSignInName' -and -not $Mismatch) {
                'Its sign-in name and primary email address already match.'
            } elseif ($NewAlias -and $Recipient.EmailAddresses -contains "smtp:$NewAlias") {
                "It already has $NewAlias."
            } elseif ($Action -eq 'UseEmailAsSignInName' -and -not $VerifiedDomains.Contains($NewUpn.Substring($NewUpn.LastIndexOf('@') + 1))) {
                "$NewUpn is not on a verified domain of this tenant, so it cannot be a sign-in name."
            } elseif ($Collision -and $SkipCollisions) {
                "$Collision is already used by another user, group or contact."
            } elseif ($Action -eq 'Move' -and $Mismatch) {
                "The sign-in name ($FinalUpn) and primary email address ($FinalPrimary) would not match after the move, which Microsoft no longer supports. Make them match first, then move this user."
            } elseif (($NewPrimary -or $NewAlias) -and ([string]::Join(' ', @($Recipient.EmailAddresses))).Contains('%')) {
                'One of its email addresses contains a % sign. Change it in the Exchange admin center.'
            }
            if (-not $Reason) {
                foreach ($Address in $NewUpn, $NewPrimary, $NewAlias) { if ($Address) { $Taken[$Address] = $Id } }
                if ($NewAlias) { $NewAddressLists[$Id] = @(@($Recipient.EmailAddresses) + "smtp:$NewAlias") }
                if ($NewPrimary) {
                    $Addresses = [System.Collections.Generic.List[string]]::new()
                    $Addresses.Add("SMTP:$NewPrimary")
                    foreach ($Address in $Recipient.EmailAddresses) {
                        if ($Address -eq "smtp:$NewPrimary") { continue }
                        if ($Address.StartsWith('SMTP:', [System.StringComparison]::Ordinal)) {
                            $Addresses.Add('smtp:' + $Address.Substring(5))
                            continue
                        }
                        $Addresses.Add($Address)
                    }
                    $NewAddressLists[$Id] = $Addresses.ToArray()
                }
            }
            $Rows.Add([PSCustomObject]@{
                    id                    = $Id
                    displayName           = if ($User) { $User.displayName } else { $Recipient.DisplayName }
                    type                  = if ($IsGroup) { 'Group' } elseif ($Type -eq 'SharedMailbox') { 'Shared mailbox' } else { 'User' }
                    userPrincipalName     = $Upn
                    newUserPrincipalName  = $NewUpn
                    primarySmtpAddress    = $Primary
                    newPrimarySmtpAddress = $NewPrimary
                    newAlias              = $NewAlias
                    status               = if ($Reason) { 'Skipped' } else { 'Ready' }
                    reason                = $Reason
                    mismatch              = $Mismatch
                    exchangeIdentity      = if ($Recipient) { [string]$Recipient.Guid }
                })
        }

        if ($Preview) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @{ Results = @($Rows) }
                })
        }

        $RowsById = @{}
        $Ready = [System.Collections.Generic.List[object]]::new()
        foreach ($Row in $Rows) {
            if (-not $SelectedIds.Contains($Row.id)) { continue }
            $RowsById[$Row.id] = $Row
            if ($Row.status -eq 'Ready') { $Ready.Add($Row) }
        }
        $Privileged = [System.Collections.Generic.HashSet[string]]::new([string[]]@(Assert-CippPrivilegedUserAccess -TenantFilter $TenantFilter -UserId @($Ready.Where({ $_.type -ne 'Group' }).id) -PassThru), [System.StringComparer]::OrdinalIgnoreCase)

        $Errors = @{}
        $UpnDone = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $UpnRequests = @(foreach ($Row in $Ready) {
                if ($Row.newUserPrincipalName -and -not $Privileged.Contains($Row.id)) {
                    @{ id = $Row.id; method = 'PATCH'; url = "users/$($Row.id)"; body = @{ userPrincipalName = $Row.newUserPrincipalName }; headers = @{ 'Content-Type' = 'application/json' } }
                }
            })
        if ($UpnRequests.Count -gt 0) {
            $UpnError = 'Could not change the sign-in name: Microsoft 365 did not answer.'
            try {
                foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests $UpnRequests -Version 'v1.0' -MaxConcurrency 4)) {
                    if ([int]$Response.status -ge 200 -and [int]$Response.status -lt 300) {
                        [void]$UpnDone.Add([string]$Response.id)
                    } else {
                        $Errors[[string]$Response.id] = "Could not change the sign-in name: $($Response.body.error.message ?? "status $($Response.status)")"
                    }
                }
            } catch {
                $UpnError = "Could not change the sign-in name: $((Get-CippException -Exception $_).NormalizedError)"
            }
            foreach ($UpnRequest in $UpnRequests) {
                if (-not $UpnDone.Contains($UpnRequest.id) -and -not $Errors.ContainsKey($UpnRequest.id)) { $Errors[$UpnRequest.id] = $UpnError }
            }
        }

        $MailboxRequests = @(foreach ($Row in $Ready) {
                if ($NewAddressLists.ContainsKey($Row.id) -and -not $Privileged.Contains($Row.id) -and -not $Errors.ContainsKey($Row.id)) {
                    $CmdletName = $GroupCmdlets[[string]$RecipientsById[$Row.id].RecipientTypeDetails] ?? 'Set-Mailbox'
                    @{ OperationGuid = $Row.id; CmdletInput = @{ CmdletName = $CmdletName; Parameters = @{ Identity = $Row.exchangeIdentity; EmailAddresses = $NewAddressLists[$Row.id] } } }
                }
            })
        if ($MailboxRequests.Count -gt 0) {
            $MailboxDone = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $MailboxError = 'Could not change the email address: Exchange did not answer.'
            try {
                foreach ($Response in @(New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray $MailboxRequests -useSystemMailbox $true -MaxConcurrency 4)) {
                    if (-not $Response.OperationGuid) { continue }
                    if ($Response.error) {
                        $Errors[[string]$Response.OperationGuid] = "Could not change the email address: $(Get-NormalizedError -Message $Response.error)"
                    } else {
                        [void]$MailboxDone.Add([string]$Response.OperationGuid)
                    }
                }
            } catch {
                $MailboxError = "Could not change the email address: $((Get-CippException -Exception $_).NormalizedError)"
            }
            foreach ($MailboxRequest in $MailboxRequests) {
                if (-not $MailboxDone.Contains($MailboxRequest.OperationGuid) -and -not $Errors.ContainsKey($MailboxRequest.OperationGuid)) { $Errors[$MailboxRequest.OperationGuid] = $MailboxError }
            }
        }

        $Failed = 0
        $Results = [System.Collections.Generic.List[object]]::new()
        foreach ($Id in $SelectedIds) {
            $Row = $RowsById[$Id]
            $Changes = if ($Row) {
                @(
                    if ($UpnDone.Contains($Id)) { "sign-in name is now $($Row.newUserPrincipalName)" }
                    if ($Row.newPrimarySmtpAddress -and -not $Errors.ContainsKey($Id)) { "primary email address is now $($Row.newPrimarySmtpAddress) ($($Row.primarySmtpAddress) kept as an alias)" }
                    if ($Row.newAlias -and -not $Errors.ContainsKey($Id)) { "added $($Row.newAlias) as an alias" }
                ) -join ', '
            }
            if (-not $Row) {
                $Results.Add(@{ resultText = "$Id`: skipped. Its sign-in name or primary email address is no longer on $SourceDomain."; state = 'warning' })
            } elseif ($Row.status -ne 'Ready') {
                $Results.Add(@{ resultText = "$($Row.displayName): skipped. $($Row.reason)"; state = 'warning' })
            } elseif ($Privileged.Contains($Id)) {
                $Results.Add(@{ resultText = "$($Row.displayName): skipped. They hold a privileged admin role, and changing them needs the Identity.PrivilegedUser.ReadWrite permission."; state = 'warning' })
            } elseif ($Errors.ContainsKey($Id)) {
                $Failed++
                $Message = if ($Changes) { "$Changes, but $($Errors[$Id].Substring(0, 1).ToLowerInvariant())$($Errors[$Id].Substring(1))" } else { $Errors[$Id] }
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to change $($Row.displayName): $Message" -Sev Error
                $Results.Add(@{ resultText = "$($Row.displayName): $Message"; state = 'error' })
            } else {
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Changed $($Row.displayName): $Changes" -Sev Info
                $Results.Add(@{ resultText = "$($Row.displayName): $Changes."; state = 'success' })
            }
        }
        $Body = @{ Results = @($Results) }
        $StatusCode = Get-CippBulkStatusCode -Total ($Ready.Count - $Privileged.Count) -Failed $Failed
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Email domain move failed: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Body = @{ Results = "Email domain move failed: $($ErrorMessage.NormalizedError)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
