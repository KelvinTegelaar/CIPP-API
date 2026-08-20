function Invoke-EditGroup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Group.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $Results = [System.Collections.Generic.List[string]]@()
    $UserObj = $Request.Body
    $GroupType = $UserObj.groupId.addedFields.groupType ? $UserObj.groupId.addedFields.groupType : $UserObj.groupType
    # groupName is used in the Add to Group user action, displayName is used in the Edit Group page
    $GroupName = $UserObj.groupName ?? $UserObj.displayName ?? $UserObj.groupId.addedFields.groupName
    $GroupId = $UserObj.groupId.value ?? $UserObj.groupId
    $OrgGroup = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/$($GroupId)" -tenantid $UserObj.tenantFilter

    # The type above is whatever the form posted, and it decides every Exchange-vs-Graph branch
    # below. Graph cannot change membership on a classic distribution list or a mail-enabled
    # security group - it answers "Cannot Update a mail-enabled security groups and or distribution
    # list" - so a missing or stale type on a stored option sends the request down a path that
    # cannot work. $OrgGroup is the group itself, so let it settle the question and keep the posted
    # value only for when the lookup came back without the flags.
    if ($null -ne $OrgGroup.mailEnabled -or $null -ne $OrgGroup.securityEnabled) {
        $GroupType = if ($OrgGroup.groupTypes -contains 'Unified') { 'Microsoft 365' }
        elseif ($OrgGroup.mailEnabled -and $OrgGroup.securityEnabled) { 'Mail-Enabled Security' }
        elseif ($OrgGroup.mailEnabled) { 'Distribution List' }
        else { 'Security' }
    }

    $AddMembers = $UserObj.AddMember

    $TenantId = $UserObj.tenantId ?? $UserObj.tenantFilter

    $MemberODataBindString = 'https://graph.microsoft.com/v1.0/directoryObjects/{0}'
    $BulkRequests = [System.Collections.Generic.List[object]]::new()
    $GraphLogs = [System.Collections.Generic.List[object]]::new()
    $ExoBulkRequests = [System.Collections.Generic.List[object]]::new()
    $ExoLogs = [System.Collections.Generic.List[object]]::new()

    if ($UserObj.displayName -or $UserObj.description -or $UserObj.mailNickname -or $UserObj.membershipRules) {
        #Edit properties:
        if ($GroupType -eq 'Distribution List' -or $GroupType -eq 'Mail-Enabled Security') {
            # OperationGuid ties this request to its result; see Resolve-CippExoBulkResult.
            $PropertiesGuid = [Guid]::NewGuid().ToString()
            $Params = @{ Identity = $GroupId; DisplayName = $UserObj.displayName; Description = $UserObj.description; name = $UserObj.mailNickname }
            $ExoBulkRequests.Add(@{
                    CmdletInput   = @{
                        CmdletName = 'Set-DistributionGroup'
                        Parameters = $Params
                    }
                    OperationGuid = $PropertiesGuid
                })
            $ExoLogs.Add(@{
                    message       = "Edited group properties for $($GroupName) group. It might take some time to reflect the changes."
                    target        = $GroupId
                    OperationGuid = $PropertiesGuid
                })
        } else {
            # Use new securityEnabled value if provided, otherwise keep original
            $SecurityEnabled = $null -ne $UserObj.securityEnabled ? $UserObj.securityEnabled : $OrgGroup.securityEnabled

            $PatchObj = @{
                displayName     = $UserObj.displayName
                description     = $UserObj.description
                mailNickname    = $UserObj.mailNickname
                mailEnabled     = $OrgGroup.mailEnabled
                securityEnabled = $SecurityEnabled
            }
            Write-Host "body: $($PatchObj | ConvertTo-Json -Depth 10 -Compress)" -ForegroundColor Yellow
            if ($UserObj.membershipRules) { $PatchObj | Add-Member -MemberType NoteProperty -Name 'membershipRule' -Value $UserObj.membershipRules -Force }
            try {
                $null = New-GraphPOSTRequest -type PATCH -uri "https://graph.microsoft.com/beta/groups/$($GroupId)" -tenantid $UserObj.tenantFilter -body ($PatchObj | ConvertTo-Json -Depth 10 -Compress)
                $Results.Add("Success - Edited group properties for $($GroupName) group. It might take some time to reflect the changes.")
                Write-LogMessage -headers $Headers -API $APIName -tenant $UserObj.tenantFilter -message "Edited group properties for $($GroupName) group" -Sev 'Info'

                # Log securityEnabled changes specifically
                if ($null -ne $UserObj.securityEnabled -and $UserObj.securityEnabled -ne $OrgGroup.securityEnabled) {
                    $securityStatusText = "Security capabilities $($UserObj.securityEnabled ? 'enabled' : 'disabled') for group $($GroupName)"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $UserObj.tenantFilter -message $securityStatusText -Sev 'Info'
                    $Results.Add($securityStatusText)
                }
            } catch {
                $Results.Add("Error - Failed to edit group properties: $($_.Exception.Message)")
                Write-LogMessage -headers $Headers -API $APIName -tenant $UserObj.tenantFilter -message "Failed to patch group: $($_.Exception.Message)" -Sev 'Error'
            }
        }
    }

    if ($AddMembers) {
        $AddMembers | ForEach-Object {
            try {
                # Add to group user action and edit group page sends in different formats, so we need to handle both
                $Member = $_.addedFields.userPrincipalName ?? $_.value ?? $_
                $MemberID = $_.value
                if (!$MemberID) {
                    $MemberID = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$Member" -tenantid $TenantId).id
                }

                if ($GroupType -eq 'Distribution List' -or $GroupType -eq 'Mail-Enabled Security') {
                    $AddMemberGuid = [Guid]::NewGuid().ToString()
                    $Params = @{ Identity = $GroupId; Member = $Member; BypassSecurityGroupManagerCheck = $true }
                    # Write-Host ($UserObj | ConvertTo-Json -Depth 10) #Debugging line
                    $ExoBulkRequests.Add(@{
                            CmdletInput   = @{
                                CmdletName = 'Add-DistributionGroupMember'
                                Parameters = $Params
                            }
                            OperationGuid = $AddMemberGuid
                        })
                    $ExoLogs.Add(@{
                            message       = "Added member $Member to $($GroupName) group"
                            target        = $Member
                            OperationGuid = $AddMemberGuid
                        })
                } else {
                    $MemberIDs = $MemberODataBindString -f $MemberID
                    $AddMemberBody = @{
                        'members@odata.bind' = @($MemberIDs)
                    }

                    $BulkRequests.Add(@{
                            id      = "addMember-$Member"
                            method  = 'PATCH'
                            url     = "groups/$($GroupId)"
                            body    = $AddMemberBody
                            headers = @{
                                'Content-Type' = 'application/json'
                            }
                        })
                    $GraphLogs.Add(@{
                            message = "Added member $Member to $($GroupName) group"
                            id      = "addMember-$Member"
                        })
                }
            } catch {
                Write-Warning "Error in AddMembers: $($_.Exception.Message)"
            }
        }
    }

    $AddDevices = $UserObj.AddDevice
    if ($AddDevices) {
        $AddDevices | ForEach-Object {
            $Device = $_
            try {
                $DeviceLabel = $Device.label ?? $Device.addedFields.deviceName ?? $Device.value
                if ($GroupType -eq 'Distribution List' -or $GroupType -eq 'Mail-Enabled Security') {
                    $Results.Add("Error - Devices cannot be added to a $GroupType group")
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Cannot add device $DeviceLabel to $($GroupName): devices are not supported in a $GroupType group" -Sev 'Error'
                } else {
                    # Intune device rows carry the Entra deviceId (azureADDeviceId) rather than the
                    # directory object id - resolve it via the devices alternate key
                    $DeviceID = $Device.value
                    if ($Device.addedFields.azureADDeviceId) {
                        $DeviceID = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/devices(deviceId='$($Device.addedFields.azureADDeviceId)')?`$select=id" -tenantid $TenantId).id
                    }

                    $AddDeviceBody = @{
                        'members@odata.bind' = @($MemberODataBindString -f $DeviceID)
                    }
                    $BulkRequests.Add(@{
                            id      = "addDevice-$DeviceID"
                            method  = 'PATCH'
                            url     = "groups/$($GroupId)"
                            body    = $AddDeviceBody
                            headers = @{
                                'Content-Type' = 'application/json'
                            }
                        })
                    $GraphLogs.Add(@{
                            message = "Added device $DeviceLabel to $($GroupName) group"
                            id      = "addDevice-$DeviceID"
                        })
                }
            } catch {
                Write-Warning "Error in AddDevices: $($_.Exception.Message)"
                $Results.Add("Error - Failed to add device $DeviceLabel to $($GroupName): $($_.Exception.Message)")
            }
        }
    }

    $AddContacts = $UserObj.AddContact
    if ($AddContacts) {
        $AddContacts | ForEach-Object {
            try {
                $Member = $_
                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
                    $AddContactGuid = [Guid]::NewGuid().ToString()
                    $Params = @{ Identity = $GroupId; Member = $Member.value; BypassSecurityGroupManagerCheck = $true }
                    $ExoBulkRequests.Add(@{
                            CmdletInput   = @{
                                CmdletName = 'Add-DistributionGroupMember'
                                Parameters = $Params
                            }
                            OperationGuid = $AddContactGuid
                        })
                    $ExoLogs.Add(@{
                            message       = "Added contact $($Member.label) to $($GroupName) group"
                            target        = $Member.value
                            OperationGuid = $AddContactGuid
                        })
                } else {
                    Write-LogMessage -API $APIName -tenant $TenantId -headers $Headers -message 'You cannot add a Contact to a Security Group or a M365 Group' -Sev 'Error'
                    $Results.Add('Error - You cannot add a contact to a Security Group or a M365 Group')
                }
            } catch {
                Write-Warning "Error in AddContacts: $($_.Exception.Message)"
            }
        }
    }

    $RemoveContact = $UserObj.RemoveContact
    try {
        if ($RemoveContact) {
            $RemoveContact | ForEach-Object {
                $Member = $_.addedFields.userPrincipalName ?? $_.value
                $MemberID = $_.value
                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
                    $RemoveContactGuid = [Guid]::NewGuid().ToString()
                    $Params = @{ Identity = $GroupId; Member = $MemberID ; BypassSecurityGroupManagerCheck = $true }
                    $ExoBulkRequests.Add(@{
                            CmdletInput   = @{
                                CmdletName = 'Remove-DistributionGroupMember'
                                Parameters = $Params
                            }
                            OperationGuid = $RemoveContactGuid
                        })
                    $ExoLogs.Add(@{
                            message       = "Removed contact $Member from $($GroupName) group"
                            target        = $MemberID
                            OperationGuid = $RemoveContactGuid
                        })
                } else {
                    Write-LogMessage -API $APIName-tenant $TenantId -headers $Headers -message 'You cannot remove a contact from a Security Group' -Sev 'Error'
                    $Results.Add('You cannot remove a contact from a Security Group')
                }
            }
        }
    } catch {
        Write-Warning "Error in RemoveContact: $($_.Exception.Message)"
    }

    $RemoveMembers = $UserObj.RemoveMember
    try {
        if ($RemoveMembers) {
            $RemoveMembers | ForEach-Object {
                $Member = $_.addedFields.userPrincipalName ?? $_.value
                $MemberID = $_.value
                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
                    $RemoveMemberGuid = [Guid]::NewGuid().ToString()
                    $Params = @{ Identity = $GroupId; Member = $Member ; BypassSecurityGroupManagerCheck = $true }
                    $ExoBulkRequests.Add(@{
                            CmdletInput   = @{
                                CmdletName = 'Remove-DistributionGroupMember'
                                Parameters = $Params
                            }
                            OperationGuid = $RemoveMemberGuid
                        })
                    $ExoLogs.Add(@{
                            message       = "Removed member $Member from $($GroupName) group"
                            target        = $Member
                            OperationGuid = $RemoveMemberGuid
                        })
                } else {
                    $BulkRequests.Add(@{
                            id     = "removeMember-$Member"
                            method = 'DELETE'
                            url    = "groups/$($GroupId)/members/$MemberID/`$ref"
                        })
                    $GraphLogs.Add(@{
                            message = "Removed member $Member from $($GroupName) group"
                            id      = "removeMember-$Member"
                        })
                }
            }
        }
    } catch {
        Write-Warning "Error in RemoveMembers: $($_.Exception.Message)"
    }

    $AddOwners = $UserObj.AddOwner
    try {
        if ($AddOwners) {
            if ($GroupType -notin @('Distribution List', 'Mail-Enabled Security')) {
                $AddOwners | ForEach-Object {
                    $Owner = $_.addedFields.userPrincipalName ?? $_.value
                    $ID = $_.value

                    $BulkRequests.Add(@{
                            id      = "addOwner-$Owner"
                            method  = 'POST'
                            url     = "groups/$($GroupId)/owners/`$ref"
                            body    = @{
                                '@odata.id' = $MemberODataBindString -f $ID
                            }
                            headers = @{
                                'Content-Type' = 'application/json'
                            }
                        })
                    $GraphLogs.Add(@{
                            message = "Added owner $($Owner) to $($GroupName) group"
                            id      = "addOwner-$Owner"
                        })
                }
            }
        }
    } catch {
        Write-Warning "Error in AddOwners: $($_.Exception.Message)"
    }

    $RemoveOwners = $UserObj.RemoveOwner
    try {
        if ($RemoveOwners) {
            if ($GroupType -notin @('Distribution List', 'Mail-Enabled Security')) {
                $RemoveOwners | ForEach-Object {
                    $ID = $_.value
                    $Owner = $_.addedFields.userPrincipalName ?? $_.value
                    $BulkRequests.Add(@{
                            id     = "removeOwner-$ID"
                            method = 'DELETE'
                            url    = "groups/$($GroupId)/owners/$ID/`$ref"
                        })
                    $GraphLogs.Add(@{
                            message = "Removed owner $($Owner) from $($GroupName) group"
                            id      = "removeOwner-$ID"
                        })
                }
            }
        }
    } catch {
        Write-Warning "Error in RemoveOwners: $($_.Exception.Message)"
    }

    if ($GroupType -in @( 'Distribution List', 'Mail-Enabled Security') -and ($AddOwners -or $RemoveOwners)) {
        $CurrentOwnersRaw = @(
            New-ExoRequest -tenantid $TenantId -cmdlet 'Get-DistributionGroup' -cmdParams @{ Identity = $GroupId } -UseSystemMailbox $true |
                Select-Object -ExpandProperty ManagedBy
        )
        $CurrentResolved = @(Resolve-CIPPDirectoryId -Identity $CurrentOwnersRaw -TenantFilter $TenantId)

        $RemoveIds = @()
        if ($RemoveOwners) {
            $RemoveIds = @(
                Resolve-CIPPDirectoryId -Identity @($RemoveOwners.value) -TenantFilter $TenantId |
                    Where-Object { $_.Resolved -and $_.Id } |
                    ForEach-Object { $_.Id }
            )
        }
        $AddResolved = @()
        if ($AddOwners) {
            $AddResolved = @(Resolve-CIPPDirectoryId -Identity @($AddOwners.value) -TenantFilter $TenantId)
        }

        # Every owner change here is carried by the one Set-DistributionGroup call below, so they
        # share an OperationGuid: the ManagedBy rewrite either applies in full or not at all, and
        # reporting per-owner outcomes that disagree with each other would be a lie.
        $OwnersGuid = [Guid]::NewGuid().ToString()
        $NewManagedBy = [System.Collections.Generic.List[string]]::new()
        $RemoveIdSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$RemoveIds, [StringComparer]::OrdinalIgnoreCase)

        foreach ($Entry in $CurrentResolved) {
            if ($Entry.Resolved -and $Entry.Id) {
                if ($RemoveIdSet.Contains($Entry.Id)) {
                    $OwnerToRemove = $RemoveOwners | Where-Object {
                        $_.value -eq $Entry.Id -or $_.value -eq $Entry.Input -or $_.addedFields.userPrincipalName -eq $Entry.UserPrincipalName
                    } | Select-Object -First 1
                    $ExoLogs.Add(@{
                            message       = "Removed owner $($OwnerToRemove.label ?? $Entry.UserPrincipalName ?? $Entry.Id) from $($GroupName) group"
                            target        = $GroupId
                            OperationGuid = $OwnersGuid
                        })
                    continue
                }
                $NewManagedBy.Add($Entry.Id)
            } else {
                # Keep unresolved ManagedBy entries so a failed lookup cannot strip an owner.
                if ($RemoveOwners -and ($RemoveOwners.value -contains $Entry.Input)) {
                    $OwnerToRemove = $RemoveOwners | Where-Object { $_.value -eq $Entry.Input } | Select-Object -First 1
                    $ExoLogs.Add(@{
                            message       = "Removed owner $($OwnerToRemove.label) from $($GroupName) group"
                            target        = $GroupId
                            OperationGuid = $OwnersGuid
                        })
                    continue
                }
                $NewManagedBy.Add($Entry.Input)
            }
        }
        foreach ($NewOwner in $AddResolved) {
            if (-not $NewOwner.Resolved -or -not $NewOwner.Id) { continue }
            $NewManagedBy.Add($NewOwner.Id)
            $OwnerLabel = ($AddOwners | Where-Object { $_.value -eq $NewOwner.Input -or $_.value -eq $NewOwner.Id } | Select-Object -First 1).label
            $ExoLogs.Add(@{
                    message       = "Added owner $($OwnerLabel ?? $NewOwner.UserPrincipalName ?? $NewOwner.Id) to $($GroupName) group"
                    target        = $GroupId
                    OperationGuid = $OwnersGuid
                })
        }

        $NewManagedBy = $NewManagedBy | Sort-Object -Unique
        # BypassSecurityGroupManagerCheck as everywhere else we write to Exchange: without it the
        # check applies to mail-enabled security groups and Set-DistributionGroup refuses with
        # "The executing user is not in the current organization", so owner changes on those groups
        # silently do nothing. Plain distribution lists are unaffected, which is why this only
        # showed up on mail-enabled security groups.
        $Params = @{ Identity = $GroupId; ManagedBy = $NewManagedBy; BypassSecurityGroupManagerCheck = $true }
        $ExoBulkRequests.Add(@{
                CmdletInput   = @{
                    CmdletName = 'Set-DistributionGroup'
                    Parameters = $Params
                }
                OperationGuid = $OwnersGuid
            })
    }



    Write-Information "Graph Bulk Requests: $($BulkRequests.Count)"
    if ($BulkRequests.Count -gt 0) {
        #Write-Warning 'EditUser - Executing Graph Bulk Requests'
        #Write-Information ($BulkRequests | ConvertTo-Json -Depth 10)
        $RawGraphRequest = New-GraphBulkRequest -tenantid $TenantId -scope 'https://graph.microsoft.com/.default' -Requests @($BulkRequests) -asapp $true
        #Write-Warning 'EditUser - Executing Graph Bulk Requests - Completed'
        #Write-Information ($RawGraphRequest | ConvertTo-Json -Depth 10)

        foreach ($GraphLog in $GraphLogs) {
            $GraphError = $RawGraphRequest | Where-Object { $_.id -eq $GraphLog.id -and $_.status -notmatch '^2[0-9]+' }
            if ($GraphError) {
                # body.error is an object; handing it to Get-NormalizedError whole renders it as
                # "@{code=Request_BadRequest; message=...; innerError=}" in the operator's face.
                $Message = Get-NormalizedError -message (Get-CippExoErrorText -ErrorRecord $GraphError.body)
                $Sev = 'Error'
                $Results.Add("Error - $Message")
            } else {
                $Message = $GraphLog.message
                $Sev = 'Info'
                $Results.Add("Success - $Message")
            }
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message $Message -Sev $Sev
        }
    }

    Write-Information "Exo Bulk Requests: $($ExoBulkRequests.Count)"
    if ($ExoBulkRequests.Count -gt 0) {
        #Write-Warning 'EditUser - Executing Exo Bulk Requests'
        #Write-Information ($ExoBulkRequests | ConvertTo-Json -Depth 10)
        $RawExoRequest = New-ExoBulkRequest -tenantid $TenantId -cmdletArray @($ExoBulkRequests)
        #Write-Warning 'EditUser - Executing Exo Bulk Requests - Completed'
        #Write-Information ($RawExoRequest | ConvertTo-Json -Depth 10)

        # Match each result back to the operation that produced it. Correlating by hand here used to
        # report an operation as succeeded whenever the error carried no matching target - which is
        # exactly what Set-DistributionGroup does - so a rejected owner change was shown to the
        # operator as "Success - Added owner ..." while nothing had actually happened.
        $ExoResults = Resolve-CippExoBulkResult -Response $RawExoRequest -Operations $ExoLogs

        foreach ($ExoResult in $ExoResults) {
            if ($ExoResult.Success) {
                $Results.Add("Success - $($ExoResult.Operation.message)")
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message $ExoResult.Operation.message -Sev 'Info'
            } else {
                $Results.Add("Error - $($ExoResult.ErrorMessage)")
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "$($ExoResult.Operation.message) failed: $($ExoResult.ErrorMessage)" -Sev 'Error'
            }
        }
    }

    # Only process licenses for Security groups
    if ($GroupType -eq 'Security') {
        $AddLicenses = @($UserObj.AddLicenses | Where-Object { $_ } | ForEach-Object { $_.value ?? $_ })
        $RemoveLicenses = @($UserObj.RemoveLicenses | Where-Object { $_ } | ForEach-Object { $_.value ?? $_ })

        if ($AddLicenses.Count -gt 0 -or $RemoveLicenses.Count -gt 0) {
            try {
                $LicResults = Set-CIPPGroupLicense -GroupId $GroupId -GroupName $GroupName -AddLicenses $AddLicenses -RemoveLicenses $RemoveLicenses -TenantFilter $TenantId -Headers $Headers -APIName $APIName
                foreach ($LicResult in $LicResults) { $Results.Add("Success - $LicResult") }
            } catch {
                $Results.Add("Error - $($_.Exception.Message)")
            }
        }
    }

    # Only process allowExternal if it was explicitly sent
    if ($null -ne $UserObj.allowExternal -and $GroupType -ne 'Security') {
        try {
            $OnlyAllowInternal = $UserObj.allowExternal -eq $true ? $false : $true
            Set-CIPPGroupAuthentication -ID $UserObj.mail -OnlyAllowInternal $OnlyAllowInternal -GroupType $GroupType -tenantFilter $TenantId -APIName $APIName -Headers $Headers
            if ($UserObj.allowExternal -eq $true) {
                $Results.Add("Allowed external senders to send to $($UserObj.mail).")
            } else {
                $Results.Add("Blocked external senders from sending to $($UserObj.mail).")
            }
        } catch {
            $action = if ($UserObj.allowExternal -eq $true) { 'allow' } else { 'block' }
            $Results.Add("Failed to $action external senders for $($UserObj.mail).")
        }
    }

    # Only process visibility if it was explicitly sent for Microsoft 365 groups
    if ($GroupType -eq 'Microsoft 365' -and -not [string]::IsNullOrWhiteSpace($UserObj.visibility)) {
        try {
            $VisibilityValue = $UserObj.visibility
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/groups/$($GroupID)" -type PATCH -tenantid $TenantId -body (@{'visibility' = $VisibilityValue } | ConvertTo-Json)

            $Results.Add("Set group visibility to $VisibilityValue for $($GroupName).")
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-Warning "Error in visibility: $($ErrorMessage.NormalizedError) - $($_.InvocationInfo.ScriptLineNumber)"
            $Results.Add("Failed to set group visibility for $($GroupName): $($ErrorMessage.NormalizedError)")
        }
    }

    # Only process sendCopies if it was explicitly sent
    if ($null -ne $UserObj.sendCopies) {
        try {
            if ($UserObj.sendCopies -eq $true) {
                $Params = @{ Identity = $GroupId; subscriptionEnabled = $true; AutoSubscribeNewMembers = $true }
                New-ExoRequest -tenantid $TenantId -cmdlet 'Set-UnifiedGroup' -cmdParams $Params -useSystemMailbox $true

                $MemberParams = @{ Identity = $GroupId; LinkType = 'members' }
                $Members = New-ExoRequest -tenantid $TenantId -cmdlet 'Get-UnifiedGroupLinks' -cmdParams $MemberParams

                $MembershipIds = $Members | ForEach-Object { $_.ExternalDirectoryObjectId }
                if ($MembershipIds) {
                    $subscriberParams = @{ Identity = $GroupId; LinkType = 'subscribers'; Links = @($MembershipIds | Where-Object { $_ }) }

                    try {
                        New-ExoRequest -tenantid $TenantId -cmdlet 'Add-UnifiedGroupLinks' -cmdParams $subscriberParams -Anchor $UserObj.mail
                    } catch {
                        $ErrorMessage = Get-CippException -Exception $_
                        Write-Warning "Error in SendCopies: Add-UnifiedGroupLinks $($ErrorMessage.NormalizedError) - $($_.InvocationInfo.ScriptLineNumber)"
                        throw "Error in SendCopies: Add-UnifiedGroupLinks $($ErrorMessage.NormalizedError)"
                    }

                }

                $Results.Add("Send Copies of team emails and events to team members inboxes for $($UserObj.mail) enabled.")
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Send Copies of team emails and events to team members inboxes for $($UserObj.mail) enabled." -Sev 'Info'
            } else {
                # Disable send copies. Has to be done in 2 calls, otherwise it fails saying AutoSubscribeNewMembers cannot be true when subscriptionEnabled is false.
                # Why this happens and can't be done in one call, only Bill Gates and the mystical gods of Exchange knows.
                $Params = @{ Identity = $GroupId; AutoSubscribeNewMembers = $false }
                $null = New-ExoRequest -tenantid $TenantId -cmdlet 'Set-UnifiedGroup' -cmdParams $Params -useSystemMailbox $true
                $Params = @{ Identity = $GroupId; subscriptionEnabled = $false }
                $null = New-ExoRequest -tenantid $TenantId -cmdlet 'Set-UnifiedGroup' -cmdParams $Params -useSystemMailbox $true

                $Results.Add("Send Copies of team emails and events to team members inboxes for $($UserObj.mail) disabled.")
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Send Copies of team emails and events to team members inboxes for $($UserObj.mail) disabled." -Sev 'Info'
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-Warning "Error in SendCopies: $($ErrorMessage.NormalizedError) - $($_.InvocationInfo.ScriptLineNumber)"
            $action = if ($UserObj.sendCopies -eq $true) { 'enable' } else { 'disable' }
            $Results.Add("Failed to $action Send Copies of team emails and events to team members inboxes for $($UserObj.mail).")
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Failed to $action Send Copies of team emails and events to team members inboxes for $($UserObj.mail). Error:$($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        }
    }

    # Only process hideFromOutlookClients if it was explicitly sent and is a Microsoft 365 group
    if ($null -ne $UserObj.hideFromOutlookClients -and $GroupType -eq 'Microsoft 365') {
        try {
            $Params = @{ Identity = $GroupId; HiddenFromExchangeClientsEnabled = $UserObj.hideFromOutlookClients }
            $null = New-ExoRequest -tenantid $TenantId -cmdlet 'Set-UnifiedGroup' -cmdParams $Params -useSystemMailbox $true

            if ($UserObj.hideFromOutlookClients -eq $true) {
                $Results.Add("Successfully hidden group mailbox from Outlook for $($GroupName).")
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Successfully hidden group mailbox from Outlook for $($GroupName)." -Sev 'Info'
            } else {
                $Results.Add("Successfully made group mailbox visible in Outlook for $($GroupName).")
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Successfully made group mailbox visible in Outlook for $($GroupName)." -Sev 'Info'
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-Warning "Error in hideFromOutlookClients: $($ErrorMessage.NormalizedError) - $($_.InvocationInfo.ScriptLineNumber)"
            $action = if ($UserObj.hideFromOutlookClients -eq $true) { 'hide' } else { 'show' }
            $Results.Add("Failed to $action group mailbox in Outlook for $($GroupName).")
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Failed to $action group mailbox in Outlook for $($GroupName). Error:$($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        }
    }

    $body = @{'Results' = @($Results) }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
