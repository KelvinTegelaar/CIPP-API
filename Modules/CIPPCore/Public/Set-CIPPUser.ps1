function Set-CIPPUser {
    <#
    .SYNOPSIS
        Edits a user. Shared by the EditUser HTTP endpoint and scheduled tasks
        (Add-CIPPScheduledTask with Command = 'Set-CIPPUser').
    .NOTES
        Manage365: body built from the fork's Invoke-EditUser, preserving the granular
        property handling, clearProperties support and UPN-conflict lookups.
    #>
    [CmdletBinding()]
    param (
        $UserObj,
        $APIName = 'Edit User',
        $Headers
    )

    $Results = [System.Collections.Generic.List[object]]::new()
    $licenses = ($UserObj.licenses).value
    $Aliases = if ($UserObj.AddedAliases) { ($UserObj.AddedAliases) -split '\s' }
    $AddToGroups = $UserObj.AddToGroups
    $RemoveFromGroups = $UserObj.RemoveFromGroups

    $UseExchangeForGroup = {
        param($AddedFields)
        $Calculated = $AddedFields.calculatedGroupType
        if ($Calculated) {
            return $Calculated -in @('distributionList', 'security')
        }
        return $AddedFields.groupType -in @('Distribution List', 'Mail-Enabled Security', 'distributionList')
    }


    #Edit the user
    try {
        Write-Host "$([boolean]$UserObj.MustChangePass)"
        # Use provided userPrincipalName if username is not available (e.g., inline edits)
        $UserPrincipalName = if ($UserObj.username) {
            "$($UserObj.username)@$($UserObj.Domain ? $UserObj.Domain : $UserObj.primDomain.value)"
        } else {
            $UserObj.userPrincipalName
        }
        $BodyToship = @{}

        if ($null -ne $UserObj.givenName) { $BodyToship['givenName'] = $UserObj.givenName }
        if ($null -ne $UserObj.surname) { $BodyToship['surname'] = $UserObj.surname }
        if ($null -ne $UserObj.displayName) { $BodyToship['displayName'] = $UserObj.displayName }
        if ($null -ne $UserObj.department) { $BodyToship['department'] = $UserObj.department }
        if ($UserObj.username -or $UserObj.mailNickname) {
            $BodyToship['mailNickname'] = $UserObj.username ? $UserObj.username : $UserObj.mailNickname
        }
        if ($UserPrincipalName -and $UserObj.username) {
            $BodyToship['userPrincipalName'] = $UserPrincipalName
        }
        if ($UserObj.usageLocation) {
            $BodyToship['usageLocation'] = $UserObj.usageLocation.value ? $UserObj.usageLocation.value : $UserObj.usageLocation
        }
        if ($null -ne $UserObj.jobTitle) { $BodyToship['jobTitle'] = $UserObj.jobTitle }
        if ($null -ne $UserObj.mobilePhone) { $BodyToship['mobilePhone'] = $UserObj.mobilePhone }
        if ($null -ne $UserObj.streetAddress) { $BodyToship['streetAddress'] = $UserObj.streetAddress }
        if ($null -ne $UserObj.city) { $BodyToship['city'] = $UserObj.city }
        if ($null -ne $UserObj.state) { $BodyToship['state'] = $UserObj.state }
        if ($null -ne $UserObj.postalCode) { $BodyToship['postalCode'] = $UserObj.postalCode }
        if ($null -ne $UserObj.country) { $BodyToship['country'] = $UserObj.country }
        if ($null -ne $UserObj.companyName) { $BodyToship['companyName'] = $UserObj.companyName }
        if ($null -ne $UserObj.businessPhones) {
            $filteredPhones = @($UserObj.businessPhones) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $BodyToship['businessPhones'] = @($filteredPhones)
        }
        if ($null -ne $UserObj.otherMails) {
            $normalizedOtherMails = @(
                @($UserObj.otherMails) | ForEach-Object {
                    if ($null -ne $_) { [string]$_ -split ',' }
                } | ForEach-Object { $_.Trim() } | Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_)
                }
            )
            if ($normalizedOtherMails.Count -gt 0) {
                $BodyToship['otherMails'] = $normalizedOtherMails
            }
        }
        if ($UserObj.MustChangePass) {
            $BodyToship['passwordProfile'] = @{
                'forceChangePasswordNextSignIn' = [bool]$UserObj.MustChangePass
            }
        }
        # Explicit clears: the frontend lists the profile fields the user actively emptied.
        # We re-add them as null (scalars) / empty array (collections) so Graph clears them, while
        # untouched empty fields stay omitted. Whitelisted to safe attributes
        # Manage365: $BodyToship is a hashtable here (fork), so assign keys directly instead of Add-Member.
        $ClearableFields = @(
            'givenName', 'surname', 'department', 'jobTitle', 'mobilePhone',
            'streetAddress', 'city', 'state', 'postalCode', 'country', 'companyName',
            'businessPhones', 'otherMails'
        )
        $ClearList = @($UserObj.clearProperties | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        foreach ($Prop in $ClearList) {
            if ($Prop -notin $ClearableFields) { continue }
            if ($Prop -in 'businessPhones', 'otherMails') {
                $BodyToShip[$Prop] = @()
            } else {
                $BodyToShip[$Prop] = $null
            }
        }
        if ($UserObj.defaultAttributes) {
            $UserObj.defaultAttributes | Get-Member -MemberType NoteProperty | ForEach-Object {
                if (-not [string]::IsNullOrWhiteSpace($UserObj.defaultAttributes.$($_.Name).value)) {
                    Write-Host "Editing user and adding $($_.Name) with value $($UserObj.defaultAttributes.$($_.Name).value)"
                    $BodyToShip[$_.Name] = $UserObj.defaultAttributes.$($_.Name).value
                }
            }
        }
        if ($UserObj.customData) {
            $UserObj.customData | Get-Member -MemberType NoteProperty | ForEach-Object {
                if (-not [string]::IsNullOrWhiteSpace($UserObj.customData.$($_.Name))) {
                    Write-Host "Editing user and adding custom data $($_.Name) with value $($UserObj.customData.$($_.Name))"
                    $BodyToShip[$_.Name] = $UserObj.customData.$($_.Name)
                }
            }
        }

        # Only make the API call if there are properties to update
        if ($BodyToShip.Count -gt 0) {
            $bodyToShipJson = ConvertTo-Json -Depth 10 -InputObject $BodyToship -Compress
            Write-Host "Updating user with body: $bodyToShipJson"
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $UserObj.tenantFilter -type PATCH -body $bodyToShipJson -verbose
            $Results.Add( 'Success. The user has been edited.' )
            $UserDisplay = if ($UserObj.DisplayName) { $UserObj.DisplayName } else { $UserObj.userPrincipalName }
            Write-LogMessage -API $APIName -tenant ($UserObj.tenantFilter) -headers $Headers -message "Edited user $UserDisplay with id $($UserObj.id)" -Sev Info
        } else {
            $Results.Add( 'No user properties to update.' )
        }
        if ($UserObj.password) {
            $passwordProfile = [pscustomobject]@{'passwordProfile' = @{ 'password' = $UserObj.password; 'forceChangePasswordNextSignIn' = [boolean]$UserObj.MustChangePass } } | ConvertTo-Json
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $UserObj.tenantFilter -type PATCH -body $PasswordProfile -Verbose
            $Results.Add("Success. The password has been set to $($UserObj.password)")
            Write-LogMessage -API $APIName -tenant ($UserObj.tenantFilter) -headers $Headers -message "Reset $($UserObj.DisplayName)'s Password" -Sev Info
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $NormalizedError = $ErrorMessage.NormalizedError
        $ConflictInfo = $null

        if ($NormalizedError -match 'Another object with the same value for property') {
            try {
                $ConflictSearches = @()
                if ($UserPrincipalName) {
                    $ConflictSearches += "userPrincipalName eq '$UserPrincipalName'"
                    $ConflictSearches += "mail eq '$UserPrincipalName'"
                    $ConflictSearches += "proxyAddresses/any(x:x eq 'smtp:$UserPrincipalName')"
                }

                foreach ($Filter in $ConflictSearches) {
                    try {
                        $ConflictUsers = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=$Filter&`$select=id,displayName,userPrincipalName,mail,accountEnabled" -tenantid $UserObj.tenantFilter -ComplexFilter
                        foreach ($ConflictUser in $ConflictUsers) {
                            if ($ConflictUser.id -ne $UserObj.id) {
                                $ConflictInfo = @{
                                    type              = 'User'
                                    displayName       = $ConflictUser.displayName
                                    userPrincipalName = $ConflictUser.userPrincipalName
                                    mail              = $ConflictUser.mail
                                    id                = $ConflictUser.id
                                    accountEnabled    = $ConflictUser.accountEnabled
                                }
                                break
                            }
                        }
                    } catch {}
                    if ($ConflictInfo) { break }
                }

                if (-not $ConflictInfo) {
                    foreach ($Filter in $ConflictSearches) {
                        try {
                            $ConflictGroups = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=$Filter&`$select=id,displayName,mail,groupTypes,mailEnabled,securityEnabled" -tenantid $UserObj.tenantFilter -ComplexFilter
                            foreach ($ConflictGroup in $ConflictGroups) {
                                $GroupType = if ($ConflictGroup.groupTypes -contains 'Unified') { 'Microsoft 365 Group' }
                                elseif ($ConflictGroup.mailEnabled -and $ConflictGroup.securityEnabled) { 'Mail-Enabled Security Group' }
                                elseif ($ConflictGroup.mailEnabled) { 'Distribution List' }
                                else { 'Security Group' }
                                $ConflictInfo = @{
                                    type        = $GroupType
                                    displayName = $ConflictGroup.displayName
                                    mail        = $ConflictGroup.mail
                                    id          = $ConflictGroup.id
                                }
                                break
                            }
                        } catch {}
                        if ($ConflictInfo) { break }
                    }
                }
            } catch {
                Write-Verbose "Failed to look up conflicting object: $($_.Exception.Message)"
            }
        }

        Write-LogMessage -API $APIName -tenant ($UserObj.tenantFilter) -headers $Headers -message "User edit API failed. $NormalizedError" -Sev Error -LogData $ErrorMessage

        if ($ConflictInfo) {
            $ConflictDetails = "Conflicting $($ConflictInfo.type): '$($ConflictInfo.displayName)'"
            if ($ConflictInfo.userPrincipalName) { $ConflictDetails += " (UPN: $($ConflictInfo.userPrincipalName))" }
            if ($ConflictInfo.mail) { $ConflictDetails += " (Mail: $($ConflictInfo.mail))" }
            $ConflictDetails += " [ID: $($ConflictInfo.id)]"
            if ($null -ne $ConflictInfo.accountEnabled) {
                $ConflictDetails += if ($ConflictInfo.accountEnabled) { ' - Account is enabled' } else { ' - Account is disabled' }
            }
            $Results.Add("Failed to edit user. $NormalizedError Conflict: $ConflictDetails")
        } else {
            $Results.Add("Failed to edit user. $NormalizedError")
        }
    }


    #Reassign the licenses
    try {

        if ($licenses -or $UserObj.removeLicenses) {
            $CurrentLicenses = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $UserObj.tenantFilter
            if (($CurrentLicenses.assignedLicenses.skuId -join ',') -eq ($licenses -join ',') -and $UserObj.removeLicenses -eq $false) {
                Write-Host "$($CurrentLicenses.assignedLicenses.skuId -join ',') $(($licenses -join ','))"
                $Results.Add( 'Success. User license is already correct.' )
            } else {
                if ($UserObj.removeLicenses) {
                    $licResults = Set-CIPPUserLicense -UserPrincipalName $UserPrincipalName -UserId $UserObj.id -TenantFilter $UserObj.tenantFilter -RemoveLicenses $CurrentLicenses.assignedLicenses.skuId -Headers $Headers -APIName $APIName
                    $Results.Add($licResults)
                } else {
                    $RemoveLicenses = $CurrentLicenses.assignedLicenses.skuId | Where-Object { $_ -notin $licenses }
                    $licResults = Set-CIPPUserLicense -UserPrincipalName $UserPrincipalName -UserId $UserObj.id -TenantFilter $UserObj.tenantFilter -RemoveLicenses $RemoveLicenses -AddLicenses $licenses -Headers $Headers -APIName $APIName
                    $Results.Add($licResults)
                }
            }
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant ($UserObj.tenantFilter) -headers $Headers -message "License assign API failed. $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Results.Add( "We've failed to assign the license. $($ErrorMessage.NormalizedError)")
        Write-Warning "License assign API failed. $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
    }

    #Add Aliases, removal currently not supported.
    try {
        if ($Aliases) {
            Write-Host ($Aliases | ConvertTo-Json)
            foreach ($Alias in $Aliases) {
                $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $UserObj.tenantFilter -type 'patch' -body "{`"mail`": `"$Alias`"}" -Verbose
            }
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $UserObj.tenantFilter -type 'patch' -body "{`"mail`": `"$UserPrincipalName`"}" -Verbose
            Write-LogMessage -API $APIName -tenant ($UserObj.tenantFilter) -headers $Headers -message "Added Aliases to $($UserObj.DisplayName)" -Sev Info
            $Results.Add( 'Success. Added aliases to user.')
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to add aliases to user $($UserObj.DisplayName). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -tenant ($UserObj.tenantFilter) -headers $Headers -message $Message -Sev Error -LogData $ErrorMessage
        $Results.Add($Message)
    }

    if ($UserObj.CopyFrom.value) {
        $CopyFrom = Set-CIPPCopyGroupMembers -Headers $Headers -CopyFromId $UserObj.CopyFrom.value -UserID $UserPrincipalName -TenantFilter $UserObj.tenantFilter
        $Results.AddRange(@($CopyFrom))
    }

    if ($AddToGroups) {
        $AddToGroups | ForEach-Object {

            $GroupType = $_.addedFields.groupType
            $GroupID = $_.value
            $GroupName = $_.label
            Write-Host "About to add $($UserObj.userPrincipalName) to $GroupName. Group ID is: $GroupID and type is: $GroupType"

            try {
                if (& $UseExchangeForGroup $_.addedFields) {
                    Write-Host 'Adding to group via Add-DistributionGroupMember'
                    $Params = @{ Identity = $GroupID; Member = $UserObj.id; BypassSecurityGroupManagerCheck = $true }
                    $null = New-ExoRequest -tenantid $UserObj.tenantFilter -cmdlet 'Add-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true
                } else {
                    Write-Host 'Adding to group via Graph'
                    $UserBody = [PSCustomObject]@{
                        '@odata.id' = "https://graph.microsoft.com/beta/directoryObjects/$($UserObj.id)"
                    }
                    $UserBodyJSON = ConvertTo-Json -Compress -Depth 10 -InputObject $UserBody
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$GroupID/members/`$ref" -tenantid $UserObj.tenantFilter -type POST -body $UserBodyJSON -Verbose
                }
                Write-LogMessage -headers $Headers -API $APIName -tenant $UserObj.tenantFilter -message "Added $($UserObj.DisplayName) to $GroupName group" -Sev Info
                $Results.Add("Success. $($UserObj.DisplayName) has been added to $GroupName")
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Message = "Failed to add member $($UserObj.DisplayName) to $GroupName. Error: $($ErrorMessage.NormalizedError)"
                Write-LogMessage -headers $Headers -API $APIName -tenant $UserObj.tenantFilter -message $Message -Sev Error -LogData $ErrorMessage
                $Results.Add($Message)
            }
        }
    }

    if ($RemoveFromGroups) {
        $RemoveFromGroups | ForEach-Object {

            $GroupType = $_.addedFields.groupType
            $GroupID = $_.value
            $GroupName = $_.label
            Write-Host "About to remove $($UserObj.userPrincipalName) from $GroupName. Group ID is: $GroupID and type is: $GroupType"

            try {
                if (& $UseExchangeForGroup $_.addedFields) {
                    Write-Host 'Removing From group via Remove-DistributionGroupMember'
                    $Params = @{ Identity = $GroupID; Member = $UserObj.id; BypassSecurityGroupManagerCheck = $true }
                    $null = New-ExoRequest -tenantid $UserObj.tenantFilter -cmdlet 'Remove-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true
                } else {
                    Write-Host 'Removing From group via Graph'
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$GroupID/members/$($UserObj.id)/`$ref" -tenantid $UserObj.tenantFilter -type DELETE
                }
                Write-LogMessage -headers $Headers -API $APIName -tenant $UserObj.tenantFilter -message "Removed $($UserObj.DisplayName) from $GroupName group" -Sev Info
                $Results.Add("Success. $($UserObj.DisplayName) has been removed from $GroupName")
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Message = "Failed to remove member $($UserObj.DisplayName) from $GroupName. Error: $($ErrorMessage.NormalizedError)"
                Write-LogMessage -headers $Headers -API $APIName -tenant $UserObj.tenantFilter -message $Message -Sev Error -LogData $ErrorMessage
                $Results.Add($Message)
            }
        }
    }

    if ($UserObj.setManager.value) {
        $ManagerResults = Set-CIPPManager -Users $UserPrincipalName -Manager $UserObj.setManager.value -TenantFilter $UserObj.tenantFilter -Headers $Headers
        $Results.Add($ManagerResults.Result)
    }

    if ($UserObj.setSponsor.value) {
        $SponsorResults = Set-CIPPSponsor -Users $UserPrincipalName -Sponsor $UserObj.setSponsor.value -TenantFilter $UserObj.tenantFilter -Headers $Headers
        $Results.Add($SponsorResults.Result)
    }

    return @{
        Results           = $Results
        UserPrincipalName = $UserPrincipalName
    }
}
