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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Results = [System.Collections.Generic.List[string]]@()
    $UserObj = $Request.Body
    $GroupType = $UserObj.groupId.addedFields.groupType ? $UserObj.groupId.addedFields.groupType : $UserObj.groupType
    $GroupName = $UserObj.groupName ? $UserObj.groupName : $UserObj.groupId.addedFields.groupName
    $GroupId = $UserObj.groupId.value ?? $UserObj.groupId
    $OrgGroup = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/$($GroupId)" -tenantid $UserObj.tenantFilter

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
            $Params = @{ Identity = $GroupId; DisplayName = $UserObj.displayName; Description = $UserObj.description; name = $UserObj.mailNickname }
            $ExoBulkRequests.Add(@{
                    CmdletInput = @{
                        CmdletName = 'Set-DistributionGroup'
                        Parameters = $Params
                    }
                })
            $ExoLogs.Add(@{
                    message = "Success - Edited group properties for $($GroupName) group. It might take some time to reflect the changes."
                    target  = $GroupId
                })
        } else {
            $PatchObj = @{
                displayName     = $UserObj.displayName
                description     = $UserObj.description
                mailNickname    = $UserObj.mailNickname
                mailEnabled     = $OrgGroup.mailEnabled
                securityEnabled = $OrgGroup.securityEnabled
            }
            Write-Host "body: $($PatchObj | ConvertTo-Json -Depth 10 -Compress)" -ForegroundColor Yellow
            if ($UserObj.membershipRules) { $PatchObj | Add-Member -MemberType NoteProperty -Name 'membershipRule' -Value $UserObj.membershipRules -Force }
            try {
                $null = New-GraphPOSTRequest -type PATCH -uri "https://graph.microsoft.com/beta/groups/$($GroupId)" -tenantid $UserObj.tenantFilter -body ($PatchObj | ConvertTo-Json -Depth 10 -Compress)
                $Results.Add("Success - Edited group properties for $($GroupName) group. It might take some time to reflect the changes.")
                Write-LogMessage -headers $Headers -API $APIName -tenant $UserObj.tenantFilter -message "Edited group properties for $($GroupName) group" -Sev 'Info'
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
                $Member = $_.value ?? $_
                $MemberID = $_.addedFields.id
                if (!$MemberID) {
                    $MemberID = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$Member" -tenantid $TenantId).id
                }

                if ($GroupType -eq 'Distribution List' -or $GroupType -eq 'Mail-Enabled Security') {
                    $Params = @{ Identity = $GroupId; Member = $Member; BypassSecurityGroupManagerCheck = $true }
                    # Write-Host ($UserObj | ConvertTo-Json -Depth 10) #Debugging line
                    $ExoBulkRequests.Add(@{
                            CmdletInput = @{
                                CmdletName = 'Add-DistributionGroupMember'
                                Parameters = $Params
                            }
                        })
                    $ExoLogs.Add(@{
                            message = "Added member $Member to $($GroupName) group"
                            target  = $Member
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


    $AddContacts = $UserObj.AddContact
    if ($AddContacts) {
        $AddContacts | ForEach-Object {
            try {
                $Member = $_
                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
                    $Params = @{ Identity = $GroupId; Member = $Member.value; BypassSecurityGroupManagerCheck = $true }
                    $ExoBulkRequests.Add(@{
                            CmdletInput = @{
                                CmdletName = 'Add-DistributionGroupMember'
                                Parameters = $Params
                            }
                        })
                    $ExoLogs.Add(@{
                            message = "Added contact $($Member.label) to $($GroupName) group"
                            target  = $Member.value
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
                $Member = $_.value
                $MemberID = $_.addedFields.id
                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
                    $Params = @{ Identity = $GroupId; Member = $MemberID ; BypassSecurityGroupManagerCheck = $true }
                    $ExoBulkRequests.Add(@{
                            CmdletInput = @{
                                CmdletName = 'Remove-DistributionGroupMember'
                                Parameters = $Params
                            }
                        })
                    $ExoLogs.Add(@{
                            message = "Removed contact $Member from $($GroupName) group"
                            target  = $MemberID
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
                $Member = $_.value
                $MemberID = $_.addedFields.id
                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
                    $Params = @{ Identity = $GroupId; Member = $Member ; BypassSecurityGroupManagerCheck = $true }
                    $ExoBulkRequests.Add(@{
                            CmdletInput = @{
                                CmdletName = 'Remove-DistributionGroupMember'
                                Parameters = $Params
                            }
                        })
                    $ExoLogs.Add(@{
                            message = "Removed member $Member from $($GroupName) group"
                            target  = $Member
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
                    $Owner = $_.value
                    $ID = $_.addedFields.id

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
                            message = "Added $Owner to $($GroupName) group"
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
                    $ID = $_.addedFields.id
                    $BulkRequests.Add(@{
                            id     = "removeOwner-$ID"
                            method = 'DELETE'
                            url    = "groups/$($GroupId)/owners/$ID/`$ref"
                        })
                    $GraphLogs.Add(@{
                            message = "Removed $($_.value) from $($GroupName) group"
                            id      = "removeOwner-$ID"
                        })
                }
            }
        }
    } catch {
        Write-Warning "Error in RemoveOwners: $($_.Exception.Message)"
    }

    if ($GroupType -in @( 'Distribution List', 'Mail-Enabled Security') -and ($AddOwners -or $RemoveOwners)) {
        $CurrentOwners = New-ExoRequest -tenantid $TenantId -cmdlet 'Get-DistributionGroup' -cmdParams @{ Identity = $GroupId } -UseSystemMailbox $true | Select-Object -ExpandProperty ManagedBy

        $NewManagedBy = [System.Collections.Generic.List[string]]::new()
        foreach ($CurrentOwner in $CurrentOwners) {
            if ($RemoveOwners -and $RemoveOwners.addedFields.id -contains $CurrentOwner) {
                $OwnerToRemove = $RemoveOwners | Where-Object { $_.addedFields.id -eq $CurrentOwner }
                $ExoLogs.Add(@{
                        message = "Removed owner $($OwnerToRemove.label) from $($GroupName) group"
                        target  = $GroupId
                    })
                continue
            }
            $NewManagedBy.Add($CurrentOwner)
        }
        if ($AddOwners) {
            foreach ($NewOwner in $AddOwners) {
                $NewManagedBy.Add($NewOwner.addedFields.id)
                $ExoLogs.Add(@{
                        message = "Added owner $($NewOwner.label) to $($GroupName) group"
                        target  = $GroupId
                    })
            }
        }

        $NewManagedBy = $NewManagedBy | Sort-Object -Unique
        $Params = @{ Identity = $GroupId; ManagedBy = $NewManagedBy }
        $ExoBulkRequests.Add(@{
                CmdletInput = @{
                    CmdletName = 'Set-DistributionGroup'
                    Parameters = $Params
                }
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
                $Message = Get-NormalizedError -message $GraphError.body.error
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

        $LastError = $RawExoRequest | Select-Object -Last 1

        foreach ($ExoError in $LastError.error) {
            $Sev = 'Error'
            $Results.Add("Error - $ExoError")
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message $ExoError -Sev $Sev
        }

        foreach ($ExoLog in $ExoLogs) {
            $ExoError = $LastError | Where-Object { $ExoLog.target -in $_.target -and $_.error }
            if (!$LastError -or ($LastError.error -and $LastError.target -notcontains $ExoLog.target)) {
                $Message = $ExoLog.message
                $Sev = 'Info'
                $Results.Add("Success - $Message")
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message $Message -Sev $Sev
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

    $body = @{'Results' = @($Results) }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
