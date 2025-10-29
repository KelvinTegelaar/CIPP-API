Function Invoke-EditRoomList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Room.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $Results = [System.Collections.Generic.List[string]]::new()
    $RoomListObj = $Request.Body
    $GroupId = $RoomListObj.groupId
    $TenantId = $RoomListObj.tenantFilter

    try {
        # Edit basic room list properties
        if ($RoomListObj.displayName -or $RoomListObj.description -or $RoomListObj.mailNickname) {
            $SetRoomListParams = @{
                Identity = $GroupId
            }

            if ($RoomListObj.displayName) {
                $SetRoomListParams.DisplayName = $RoomListObj.displayName
            }

            if ($RoomListObj.description) {
                $SetRoomListParams.Description = $RoomListObj.description
            }

            if ($RoomListObj.mailNickname) {
                $SetRoomListParams.Name = $RoomListObj.mailNickname
            }

            try {
                $null = New-ExoRequest -tenantid $TenantId -cmdlet 'Set-DistributionGroup' -cmdParams $SetRoomListParams -useSystemMailbox $true
                $Results.Add("Successfully updated room list properties for $($RoomListObj.displayName)")
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Updated room list properties for $($RoomListObj.displayName)" -Sev 'Info'
            } catch {
                $Results.Add("Failed to update room list properties: $($_.Exception.Message)")
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Failed to update room list properties: $($_.Exception.Message)" -Sev 'Error'
            }
        }

        # Add room members
        if ($RoomListObj.AddMember) {
            foreach ($Member in $RoomListObj.AddMember) {
                try {
                    $MemberEmail = if ($Member.value) { $Member.value } else { $Member }
                    $AddMemberParams = @{
                        Identity                        = $GroupId
                        Member                          = $MemberEmail
                        BypassSecurityGroupManagerCheck = $true
                    }

                    $null = New-ExoRequest -tenantid $TenantId -cmdlet 'Add-DistributionGroupMember' -cmdParams $AddMemberParams -useSystemMailbox $true
                    $Results.Add("Successfully added room $MemberEmail to room list")
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Added room $MemberEmail to room list $GroupId" -Sev 'Info'
                } catch {
                    $Results.Add("Failed to add room $MemberEmail : $($_.Exception.Message)")
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Failed to add room $MemberEmail : $($_.Exception.Message)" -Sev 'Error'
                }
            }
        }

        # Remove room members
        if ($RoomListObj.RemoveMember) {
            foreach ($Member in $RoomListObj.RemoveMember) {
                try {
                    $MemberEmail = if ($Member.value) { $Member.value } else { $Member }
                    $RemoveMemberParams = @{
                        Identity                        = $GroupId
                        Member                          = $MemberEmail
                        BypassSecurityGroupManagerCheck = $true
                    }

                    $null = New-ExoRequest -tenantid $TenantId -cmdlet 'Remove-DistributionGroupMember' -cmdParams $RemoveMemberParams -useSystemMailbox $true
                    $Results.Add("Successfully removed room $MemberEmail from room list")
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Removed room $MemberEmail from room list $GroupId" -Sev 'Info'
                } catch {
                    $Results.Add("Failed to remove room $MemberEmail from room list: $($_.Exception.Message)")
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Failed to remove room $MemberEmail from room list: $($_.Exception.Message)" -Sev 'Error'
                }
            }
        }

        # Handle owners (ManagedBy property)
        if ($RoomListObj.AddOwner -or $RoomListObj.RemoveOwner) {
            try {
                # Get current owners
                $CurrentGroup = New-ExoRequest -tenantid $TenantId -cmdlet 'Get-DistributionGroup' -cmdParams @{ Identity = $GroupId } -useSystemMailbox $true
                $CurrentOwners = [System.Collections.Generic.List[string]]::new()

                if ($CurrentGroup.ManagedBy) {
                    # Convert ManagedBy objects to strings explicitly
                    foreach ($ManagedByItem in $CurrentGroup.ManagedBy) {
                        $StringValue = [string]$ManagedByItem
                        $CurrentOwners.Add($StringValue)
                    }
                }

                # Remove owners
                if ($RoomListObj.RemoveOwner) {
                    foreach ($Owner in $RoomListObj.RemoveOwner) {
                        $OwnerToRemove = if ($Owner.addedFields.id) { $Owner.addedFields.id } else { $Owner.value }
                        if ($CurrentOwners -contains $OwnerToRemove) {
                            $CurrentOwners.Remove($OwnerToRemove)
                            $Results.Add("Removed owner $(if ($Owner.label) { $Owner.label } else { $OwnerToRemove }) from room list")
                        }
                    }
                }

                # Add owners
                if ($RoomListObj.AddOwner) {
                    foreach ($Owner in $RoomListObj.AddOwner) {
                        $OwnerToAdd = if ($Owner.addedFields.id) { $Owner.addedFields.id } else { $Owner.value }
                        if ($CurrentOwners -notcontains $OwnerToAdd) {
                            $CurrentOwners.Add($OwnerToAdd)
                            $Results.Add("Added owner $(if ($Owner.label) { $Owner.label } else { $OwnerToAdd }) to room list")
                        }
                    }
                }

                # Update ManagedBy with new owners list
                $SetOwnersParams = @{
                    Identity  = $GroupId
                    ManagedBy = $CurrentOwners.ToArray()
                }

                $null = New-ExoRequest -tenantid $TenantId -cmdlet 'Set-DistributionGroup' -cmdParams $SetOwnersParams -useSystemMailbox $true
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Updated owners for room list $GroupId" -Sev 'Info'
            } catch {
                $Results.Add("Failed to update room list owners: $($_.Exception.Message)")
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Failed to update room list owners: $($_.Exception.Message)" -Sev 'Error'
            }
        }

        # Handle external email settings
        if ($null -ne $RoomListObj.allowExternal) {
            try {
                $SetExternalParams = @{
                    Identity                           = $GroupId
                    RequireSenderAuthenticationEnabled = !$RoomListObj.allowExternal
                }

                $null = New-ExoRequest -tenantid $TenantId -cmdlet 'Set-DistributionGroup' -cmdParams $SetExternalParams -useSystemMailbox $true

                if ($RoomListObj.allowExternal) {
                    $Results.Add('Enabled external email access for room list')
                } else {
                    $Results.Add('Disabled external email access for room list')
                }

                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Updated external email settings for room list $GroupId" -Sev 'Info'
            } catch {
                $Results.Add("Failed to update external email settings: $($_.Exception.Message)")
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Failed to update external email settings: $($_.Exception.Message)" -Sev 'Error'
            }
        }

    } catch {
        $Results.Add("An error occurred while editing the room list: $($_.Exception.Message)")
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message "Failed to edit room list: $($_.Exception.Message)" -Sev 'Error'
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{'Results' = @($Results) }
        })
}
