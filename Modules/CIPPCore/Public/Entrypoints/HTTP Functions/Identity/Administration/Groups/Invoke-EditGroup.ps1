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
    $userobj = $Request.body
    $GroupType = $userobj.groupId.addedFields.groupType ? $userobj.groupId.addedFields.groupType : $userobj.groupType
    $GroupName = $userobj.groupName ? $userobj.groupName : $userobj.groupId.addedFields.groupName

    #Write-Warning ($Request.Body | ConvertTo-Json -Depth 10)

    $AddMembers = $userobj.AddMember
    $userobj.groupId = $userobj.groupId.value ?? $userobj.groupId

    $TenantId = $userobj.tenantid ?? $userobj.tenantFilter

    $MemberODataBindString = 'https://graph.microsoft.com/v1.0/directoryObjects/{0}'
    $BulkRequests = [System.Collections.Generic.List[object]]::new()
    $GraphLogs = [System.Collections.Generic.List[object]]::new()
    $ExoBulkRequests = [System.Collections.Generic.List[object]]::new()
    $ExoLogs = [System.Collections.Generic.List[object]]::new()

    if ($AddMembers) {
        $AddMembers | ForEach-Object {
            try {
                $member = $_.value
                $memberid = $_.addedFields.id
                if (!$memberid) {
                    $memberid = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$member" -tenantid $TenantId).id
                }

                if ($GroupType -eq 'Distribution List' -or $GroupType -eq 'Mail-Enabled Security') {
                    $Params = @{ Identity = $userobj.groupid; Member = $member; BypassSecurityGroupManagerCheck = $true }
                    $ExoBulkRequests.Add(@{
                            CmdletInput = @{
                                CmdletName = 'Add-DistributionGroupMember'
                                Parameters = $Params
                            }
                        })
                    $ExoLogs.Add(@{
                            message = "Added member $member to $($GroupName) group"
                            target  = $member
                        })
                } else {
                    $MemberIDs = $MemberODataBindString -f $memberid
                    $AddMemberBody = @{
                        'members@odata.bind' = @($MemberIDs)
                    }

                    $BulkRequests.Add(@{
                            id      = "addMember-$member"
                            method  = 'PATCH'
                            url     = "groups/$($userobj.groupid)"
                            body    = $AddMemberBody
                            headers = @{
                                'Content-Type' = 'application/json'
                            }
                        })
                    $GraphLogs.Add(@{
                            message = "Added member $member to $($GroupName) group"
                            id      = "addMember-$member"
                        })
                }
            } catch {
                Write-Warning "Error in AddMembers: $($_.Exception.Message)"
            }
        }
    }


    $AddContacts = $userobj.AddContact
    if ($AddContacts) {
        $AddContacts | ForEach-Object {
            try {
                $member = $_
                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
                    $Params = @{ Identity = $userobj.groupid; Member = $member.value; BypassSecurityGroupManagerCheck = $true }
                    $ExoBulkRequests.Add(@{
                            CmdletInput = @{
                                CmdletName = 'Add-DistributionGroupMember'
                                Parameters = $Params
                            }
                        })
                    $ExoLogs.Add(@{
                            message = "Added contact $($member.label) to $($GroupName) group"
                            target  = $member.value
                        })
                } else {
                    Write-LogMessage -API $APINAME -tenant $TenantId -headers $Request.Headers -message 'You cannot add a Contact to a Security Group or a M365 Group' -Sev 'Error'
                    $null = $results.add('Error - You cannot add a contact to a Security Group or a M365 Group')
                }
            } catch {
                Write-Warning "Error in AddContacts: $($_.Exception.Message)"
            }
        }
    }

    $RemoveContact = $userobj.RemoveContact
    try {
        if ($RemoveContact) {
            $RemoveContact | ForEach-Object {
                $member = $_.value
                $memberid = $_.addedFields.id
                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
                    $Params = @{ Identity = $userobj.groupid; Member = $memberid ; BypassSecurityGroupManagerCheck = $true }
                    $ExoBulkRequests.Add(@{
                            CmdletInput = @{
                                CmdletName = 'Remove-DistributionGroupMember'
                                Parameters = $Params
                            }
                        })
                    $ExoLogs.Add(@{
                            message = "Removed contact $member from $($GroupName) group"
                            target  = $memberid
                        })
                } else {
                    Write-LogMessage -API $APINAME -tenant $TenantId -headers $Request.Headers -message 'You cannot remove a contact from a Security Group' -Sev 'Error'
                    $null = $results.add('You cannot remove a contact from a Security Group')
                }
            }
        }
    } catch {
        Write-Warning "Error in RemoveContact: $($_.Exception.Message)"
    }

    $RemoveMembers = $userobj.Removemember
    try {
        if ($RemoveMembers) {
            $RemoveMembers | ForEach-Object {
                $member = $_.value
                $memberid = $_.addedFields.id
                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
                    $Params = @{ Identity = $userobj.groupid; Member = $member ; BypassSecurityGroupManagerCheck = $true }
                    $ExoBulkRequests.Add(@{
                            CmdletInput = @{
                                CmdletName = 'Remove-DistributionGroupMember'
                                Parameters = $Params
                            }
                        })
                    $ExoLogs.Add(@{
                            message = "Removed member $member from $($GroupName) group"
                            target  = $member
                        })
                } else {
                    $BulkRequests.Add(@{
                            id     = "removeMember-$member"
                            method = 'DELETE'
                            url    = "groups/$($userobj.groupid)/members/$memberid/`$ref"
                        })
                    $GraphLogs.Add(@{
                            message = "Removed member $member from $($GroupName) group"
                            id      = "removeMember-$member"
                        })
                }
            }
        }
    } catch {
        Write-Warning "Error in RemoveMembers: $($_.Exception.Message)"
    }

    $AddOwners = $userobj.AddOwner
    try {
        if ($AddOwners) {
            if ($GroupType -notin @('Distribution List', 'Mail-Enabled Security')) {
                $AddOwners | ForEach-Object {
                    $Owner = $_.value
                    $ID = $_.addedFields.id

                    $BulkRequests.Add(@{
                            id      = "addOwner-$Owner"
                            method  = 'POST'
                            url     = "groups/$($userobj.groupid)/owners/`$ref"
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

    $RemoveOwners = $userobj.RemoveOwner
    try {
        if ($RemoveOwners) {
            if ($GroupType -notin @('Distribution List', 'Mail-Enabled Security')) {
                $RemoveOwners | ForEach-Object {
                    $ID = $_.addedFields.id
                    $BulkRequests.Add(@{
                            id     = "removeOwner-$ID"
                            method = 'DELETE'
                            url    = "groups/$($userobj.groupid)/owners/$ID/`$ref"
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
        $CurrentOwners = New-ExoRequest -tenantid $TenantId -cmdlet 'Get-DistributionGroup' -cmdParams @{ Identity = $userobj.groupid } -UseSystemMailbox $true | Select-Object -ExpandProperty ManagedBy

        $NewManagedBy = [system.collections.generic.list[string]]::new()
        foreach ($CurrentOwner in $CurrentOwners) {
            if ($RemoveOwners -and $RemoveOwners.addedFields.id -contains $CurrentOwner) {
                $OwnerToRemove = $RemoveOwners | Where-Object { $_.addedFields.id -eq $CurrentOwner }
                $ExoLogs.Add(@{
                        message = "Removed owner $($OwnerToRemove.label) from $($GroupName) group"
                        target  = $userobj.groupid
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
                        target  = $userobj.groupid
                    })
            }
        }

        $NewManagedBy = $NewManagedBy | Sort-Object -Unique
        $params = @{ Identity = $userobj.groupid; ManagedBy = $NewManagedBy }
        $ExoBulkRequests.Add(@{
                CmdletInput = @{
                    CmdletName = 'Set-DistributionGroup'
                    Parameters = $params
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
            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantId -message $Message -Sev $Sev
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
            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantId -message $Message -Sev $Sev
        }

        foreach ($ExoLog in $ExoLogs) {
            $ExoError = $LastError | Where-Object { $ExoLog.target -in $_.target -and $_.error }
            if (!$LastError -or ($LastError.error -and $LastError.target -notcontains $ExoLog.target)) {
                $Message = $ExoLog.message
                $Sev = 'Info'
                $Results.Add("Success - $Message")
                Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantId -message $Message -Sev $Sev
            }
        }
    }

    if ($userobj.allowExternal -eq $true -and $GroupType -ne 'Security') {
        try {
            Set-CIPPGroupAuthentication -ID $userobj.mail -OnlyAllowInternal (!$userobj.allowExternal) -GroupType $GroupType -tenantFilter $TenantId -APIName $APINAME -Headers $Request.Headers
            $body = $results.add("Allowed external senders to send to $($userobj.mail).")
        } catch {
            $body = $results.add("Failed to allow external senders to send to $($userobj.mail).")
            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantId -message "Failed to allow external senders for $($userobj.mail). Error:$($_.Exception.Message)" -Sev 'Error'
        }

    }

    if ($userobj.sendCopies -eq $true) {
        try {
            $Params = @{ Identity = $userobj.Groupid; subscriptionEnabled = $true; AutoSubscribeNewMembers = $true }
            New-ExoRequest -tenantid $TenantId -cmdlet 'Set-UnifiedGroup' -cmdParams $params -useSystemMailbox $true

            $MemberParams = @{ Identity = $userobj.Groupid; LinkType = 'members' }
            $Members = New-ExoRequest -tenantid $TenantId -cmdlet 'Get-UnifiedGrouplinks' -cmdParams $MemberParams

            $MemberSmtpAddresses = $Members | ForEach-Object { $_.PrimarySmtpAddress }

            if ($MemberSmtpAddresses) {
                $subscriberParams = @{ Identity = $userobj.Groupid; LinkType = 'subscribers'; Links = @($MemberSmtpAddresses | Where-Object { $_ }) }
                New-ExoRequest -tenantid $TenantId -cmdlet 'Add-UnifiedGrouplinks' -cmdParams $subscriberParams -Anchor $userobj.mail
            }

            $body = $results.add("Send Copies of team emails and events to team members inboxes for $($userobj.mail) enabled.")
            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantId -message "Send Copies of team emails and events to team members inboxes for $($userobj.mail) enabled." -Sev 'Info'
        } catch {
            Write-Warning "Error in SendCopies: $($_.Exception.Message) - $($_.InvocationInfo.ScriptLineNumber)"
            Write-Warning ($_.InvocationInfo.PositionMessage)
            $body = $results.add("Failed to Send Copies of team emails and events to team members inboxes for $($userobj.mail).")
            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantId -message "Failed to Send Copies of team emails and events to team members inboxes for $($userobj.mail). Error:$($_.Exception.Message)" -Sev 'Error'
        }
    }

    $body = @{'Results' = @($results) }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
