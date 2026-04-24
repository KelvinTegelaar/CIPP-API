Function Invoke-ListRoomLists {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Room.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $GroupID = $Request.Query.groupID
    $Members = $Request.Query.members
    $Owners = $Request.Query.owners

    try {
        if ($GroupID) {
            # Get specific room list with detailed information
            $GroupInfo = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DistributionGroup' -cmdParams @{Identity = $GroupID } -useSystemMailbox $true |
                Select-Object -ExcludeProperty *data.type*

            $Result = [PSCustomObject]@{
                groupInfo     = $GroupInfo | Select-Object *, @{ Name = 'primDomain'; Expression = { $_.PrimarySmtpAddress -split '@' | Select-Object -Last 1 } }
                members       = @{}
                owners        = @{}
                allowExternal = (!$GroupInfo.RequireSenderAuthenticationEnabled)
            }

            # Get members if requested
            if ($Members -eq 'true') {
                $RoomListMembers = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DistributionGroupMember' -cmdParams @{Identity = $GroupID } | Select-Object -ExcludeProperty *data.type* -Property @{Name = 'id'; Expression = { $_.ExternalDirectoryObjectId } },
                @{Name = 'displayName'; Expression = { $_.DisplayName } },
                @{Name = 'mail'; Expression = { $_.PrimarySmtpAddress } },
                @{Name = 'mailNickname'; Expression = { $_.Alias } },
                @{Name = 'userPrincipalName'; Expression = { $_.PrimarySmtpAddress } }
                $Result.members = @($RoomListMembers)
            }

            # Get owners if requested
            if ($Owners -eq 'true' -and $GroupInfo.ManagedBy) {
                try {
                    # Separate valid and invalid GUIDs
                    $ValidOwnerIds = [System.Collections.Generic.List[string]]::new()
                    $InvalidOwnerIds = [System.Collections.Generic.List[string]]::new()

                    foreach ($OwnerId in $GroupInfo.ManagedBy) {
                        $OwnerIdString = [string]$OwnerId
                        # Check if it's a valid GUID format
                        if ($OwnerIdString -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
                            $ValidOwnerIds.Add($OwnerIdString)
                        } else {
                            $InvalidOwnerIds.Add($OwnerIdString)
                            Write-Warning "Found invalid GUID for owner: $OwnerIdString"
                        }
                    }

                    $AllOwners = [System.Collections.Generic.List[PSCustomObject]]::new()

                    # Get valid owners from Graph API
                    if ($ValidOwnerIds.Count -gt 0) {
                        $body = ConvertTo-Json -InputObject @{ids = @($ValidOwnerIds) } -Compress
                        $OwnersData = New-GraphPOSTRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/beta/directoryObjects/getByIds' -body $body
                        foreach ($Owner in $OwnersData.value) {
                            $AllOwners.Add($Owner)
                        }
                    }

                    # Add invalid GUIDs as placeholder objects so they can be removed
                    foreach ($InvalidId in $InvalidOwnerIds) {
                        $PlaceholderOwner = [PSCustomObject]@{
                            id                = $InvalidId
                            displayName       = "Invalid Owner ID: $InvalidId"
                            userPrincipalName = "invalid-$InvalidId"
                            '@odata.type'     = '#microsoft.graph.user'
                        }
                        $AllOwners.Add($PlaceholderOwner)
                    }

                    $Result.owners = @($AllOwners)

                } catch {
                    Write-Warning "Failed to get owners: $($_.Exception.Message)"
                    $Result.owners = @()
                }
            }



            $StatusCode = [HttpStatusCode]::OK
            $ResponseBody = $Result
        } else {
            # Get all room lists (original functionality)
            $RoomLists = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DistributionGroup' -cmdParams @{RecipientTypeDetails = 'RoomList'; ResultSize = 'Unlimited' } |
                Select-Object Guid, DisplayName, PrimarySmtpAddress, Alias, Phone, Identity, Notes, Description, Id -ExcludeProperty *data.type*
            $StatusCode = [HttpStatusCode]::OK
            $ResponseBody = @{ Results = @($RoomLists | Sort-Object DisplayName) }
        }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
        $ResponseBody = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $ResponseBody
        })

}
