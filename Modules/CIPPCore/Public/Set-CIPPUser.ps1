function Set-CIPPUser {
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

    # Graph cannot change membership on a classic distribution list or a mail-enabled security
    # group; those have to go through Add-/Remove-DistributionGroupMember. $ResolvedType is what
    # Graph says the group actually is and always wins. The fields on the autocomplete option are
    # only a fallback for groups the lookup could not answer for - they are whatever the form held
    # when the option was built, so they are missing on older saved selections and stale on any
    # group converted since.
    # Note the vocabulary of calculatedGroupType: 'security' means a MAIL-ENABLED security group
    # (Exchange), while a plain security group is 'generic' (Graph).
    $UseExchangeForGroup = {
        param($AddedFields, $ResolvedType)
        if ($ResolvedType) {
            return $ResolvedType -in @('Distribution List', 'Mail-Enabled Security')
        }
        $Calculated = $AddedFields.calculatedGroupType
        if ($Calculated) {
            return $Calculated -in @('distributionList', 'security')
        }
        return $AddedFields.groupType -in @('Distribution List', 'Mail-Enabled Security', 'distributionList')
    }


    #Edit the user
    try {
        $UserPrincipalName = "$($UserObj.username)@$($UserObj.Domain ? $UserObj.Domain : $UserObj.primDomain.value)"
        $normalizedOtherMails = @(
            @($UserObj.otherMails) | ForEach-Object {
                if ($null -ne $_) {
                    [string]$_ -split ','
                }
            } | ForEach-Object {
                $_.Trim()
            } | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            }
        )
        $BodyToship = [pscustomobject] @{
            'givenName'         = $UserObj.givenName
            'surname'           = $UserObj.surname
            'displayName'       = $UserObj.displayName
            'department'        = $UserObj.department
            'mailNickname'      = $UserObj.username ? $UserObj.username : $UserObj.mailNickname
            'userPrincipalName' = $UserPrincipalName
            'usageLocation'     = $UserObj.usageLocation.value ? $UserObj.usageLocation.value : $UserObj.usageLocation
            'jobTitle'          = $UserObj.jobTitle
            'mobilePhone'       = $UserObj.mobilePhone
            'streetAddress'     = $UserObj.streetAddress
            'city'              = $UserObj.city
            'state'             = $UserObj.state
            'postalCode'        = $UserObj.postalCode
            'country'           = $UserObj.country
            'companyName'       = $UserObj.companyName
            'businessPhones'    = $UserObj.businessPhones ? @($UserObj.businessPhones) : @()
            'otherMails'        = $normalizedOtherMails
            'passwordProfile'   = @{
                'forceChangePasswordNextSignIn' = [bool]$UserObj.MustChangePass
            }
        } | ForEach-Object {
            $NonEmptyProperties = $_.PSObject.Properties |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_.Value) } |
                Select-Object -ExpandProperty Name
                $_ | Select-Object -Property $NonEmptyProperties
            }
        # Explicit clears: the frontend lists the profile fields the user actively emptied.
        # We re-add them as null (scalars) / empty array (collections) so Graph clears them, while
        # untouched empty fields stay omitted. Whitelisted to safe attributes
        $ClearableFields = @(
            'givenName', 'surname', 'department', 'jobTitle', 'mobilePhone',
            'streetAddress', 'city', 'state', 'postalCode', 'country', 'companyName',
            'businessPhones', 'otherMails'
        )
        $ClearList = @($UserObj.clearProperties | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        foreach ($Prop in $ClearList) {
            if ($Prop -notin $ClearableFields) { continue }
            # Pass @() literally; routing it through a variable unrolls it back to $null.
            if ($Prop -in 'businessPhones', 'otherMails') {
                $BodyToShip | Add-Member -NotePropertyName $Prop -NotePropertyValue @() -Force
            } else {
                $BodyToShip | Add-Member -NotePropertyName $Prop -NotePropertyValue $null -Force
            }
        }
        if ($UserObj.defaultAttributes) {
            $UserObj.defaultAttributes | Get-Member -MemberType NoteProperty | ForEach-Object {
                if (-not [string]::IsNullOrWhiteSpace($UserObj.defaultAttributes.$($_.Name).value)) {
                    Write-Host "Editing user and adding $($_.Name) with value $($UserObj.defaultAttributes.$($_.Name).value)"
                    $BodyToShip | Add-Member -NotePropertyName $_.Name -NotePropertyValue $UserObj.defaultAttributes.$($_.Name).value -Force
                }
            }
        }
        if ($UserObj.customData) {
            $UserObj.customData | Get-Member -MemberType NoteProperty | ForEach-Object {
                if (-not [string]::IsNullOrWhiteSpace($UserObj.customData.$($_.Name))) {
                    Write-Host "Editing user and adding custom data $($_.Name) with value $($UserObj.customData.$($_.Name))"
                    $BodyToShip | Add-Member -NotePropertyName $_.Name -NotePropertyValue $UserObj.customData.$($_.Name) -Force
                }
            }
        }
        $bodyToShip = ConvertTo-Json -Depth 10 -InputObject $BodyToship -Compress
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $UserObj.tenantFilter -type PATCH -body $BodyToship -verbose
        $Results.Add( 'Success. The user has been edited.' )
        Write-LogMessage -API $APIName -tenant ($UserObj.tenantFilter) -headers $Headers -message "Edited user $($UserObj.DisplayName) with id $($UserObj.id)" -Sev Info
        if ($UserObj.password) {
            $passwordProfile = [pscustomobject]@{'passwordProfile' = @{ 'password' = $UserObj.password; 'forceChangePasswordNextSignIn' = [boolean]$UserObj.MustChangePass } } | ConvertTo-Json
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $UserObj.tenantFilter -type PATCH -body $PasswordProfile -Verbose
            $Results.Add("Success. The password has been set to $($UserObj.password)")
            Write-LogMessage -API $APIName -tenant ($UserObj.tenantFilter) -headers $Headers -message "Reset $($UserObj.DisplayName)'s Password" -Sev Info
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant ($UserObj.tenantFilter) -headers $Headers -message "User edit API failed. $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Results.Add( "Failed to edit user. $($ErrorMessage.NormalizedError)")
    }


    #Reassign the licenses
    try {

        if ($licenses -or $UserObj.removeLicenses) {
            if ($UserObj.sherwebLicense.value) {
                $null = Set-SherwebSubscription -Headers $Headers -TenantFilter $UserObj.tenantFilter -SKU $UserObj.sherwebLicense.value -Add 1
                $Results.Add('Added Sherweb License, scheduling assignment')
                $taskObject = [PSCustomObject]@{
                    TenantFilter  = $UserObj.tenantFilter
                    Name          = "Assign License: $UserPrincipalName"
                    Command       = @{
                        value = 'Set-CIPPUserLicense'
                    }
                    Parameters    = [pscustomobject]@{
                        UserId            = $UserObj.id
                        APIName           = 'Sherweb License Assignment'
                        AddLicenses       = $licenses
                        UserPrincipalName = $UserPrincipalName
                    }
                    ScheduledTime = 0 #right now, which is in the next 15 minutes and should cover most cases.
                    PostExecution = @{
                        Webhook = [bool]$UserObj.PostExecution.webhook
                        Email   = [bool]$UserObj.PostExecution.email
                        PSA     = [bool]$UserObj.PostExecution.psa
                    }
                }
                Add-CIPPScheduledTask -Task $taskObject -hidden $false -Headers $Headers
            } else {
                $CurrentLicenses = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $UserObj.tenantFilter
                #if the list of skuIds in $CurrentLicenses.assignedLicenses is EXACTLY the same as $licenses, we don't need to do anything, but the order in both can be different.
                if (($CurrentLicenses.assignedLicenses.skuId -join ',') -eq ($licenses -join ',') -and $UserObj.removeLicenses -eq $false) {
                    Write-Host "$($CurrentLicenses.assignedLicenses.skuId -join ',') $(($licenses -join ','))"
                    $Results.Add( 'Success. User license is already correct.' )
                } else {
                    if ($UserObj.removeLicenses) {
                        $licResults = Set-CIPPUserLicense -UserPrincipalName $UserPrincipalName -UserId $UserObj.id -TenantFilter $UserObj.tenantFilter -RemoveLicenses $CurrentLicenses.assignedLicenses.skuId -Headers $Headers -APIName $APIName
                        $Results.Add($licResults)
                    } else {
                        #Remove all objects from $CurrentLicenses.assignedLicenses.skuId that are in $licenses
                        $RemoveLicenses = $CurrentLicenses.assignedLicenses.skuId | Where-Object { $_ -notin $licenses }
                        $licResults = Set-CIPPUserLicense -UserPrincipalName $UserPrincipalName -UserId $UserObj.id -TenantFilter $UserObj.tenantFilter -RemoveLicenses $RemoveLicenses -AddLicenses $licenses -Headers $Headers -APIName $APIName
                        $Results.Add($licResults)
                    }

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
        # Set-CIPPCopyGroupMembers hands back a single object carrying a Success list and an Error
        # list. Adding that object straight to a string list renders the whole copy as
        # "@{Success=System.Object[]; Error=System.Object[]}", which hides every per-group outcome -
        # the failures included. Flatten it the way New-CIPPUserTask already does.
        foreach ($CopyResult in @($CopyFrom)) {
            @($CopyResult.Success) | Where-Object { $_ } | ForEach-Object { $Results.Add($_) }
            @($CopyResult.Error) | Where-Object { $_ } | ForEach-Object { $Results.Add($_) }
            # Groups deliberately left out (dynamic, AD-synced, public, already assigned) are
            # reported too: silently dropping them reads as the copy having missed something.
            @($CopyResult.Skipped) | Where-Object { $_ } | ForEach-Object { $Results.Add($_) }
        }
    }

    # Ask Graph what every group in this request actually is, in one call, so the Exchange-vs-Graph
    # decision below does not depend on what the form happened to post. A failure here is not fatal:
    # the loops fall back to the option's own fields.
    $ResolvedGroupTypes = @{}
    $GroupsToResolve = @(@($AddToGroups) + @($RemoveFromGroups) | Where-Object { $_.value } |
            Select-Object -ExpandProperty value -Unique)
    if ($GroupsToResolve.Count -gt 0) {
        try {
            $GroupLookups = New-GraphBulkRequest -tenantid $UserObj.tenantFilter -Requests @(
                foreach ($ResolveId in $GroupsToResolve) {
                    @{
                        id     = $ResolveId
                        method = 'GET'
                        url    = "groups/$($ResolveId)?`$select=id,groupTypes,mailEnabled,securityEnabled"
                    }
                }
            )
            foreach ($Lookup in $GroupLookups) {
                $LookupGroup = $Lookup.body
                if ($null -eq $LookupGroup.mailEnabled -and $null -eq $LookupGroup.securityEnabled) { continue }
                $ResolvedGroupTypes[$Lookup.id] = if ($LookupGroup.groupTypes -contains 'Unified') { 'Microsoft 365' }
                elseif ($LookupGroup.mailEnabled -and $LookupGroup.securityEnabled) { 'Mail-Enabled Security' }
                elseif ($LookupGroup.mailEnabled) { 'Distribution List' }
                else { 'Security' }
            }
        } catch {
            Write-LogMessage -headers $Headers -API $APIName -tenant $UserObj.tenantFilter -Sev 'Warn' -message "Could not look up group types, falling back to the types supplied by the request: $($_.Exception.Message)"
        }
    }

    if ($AddToGroups) {
        $AddToGroups | ForEach-Object {

            $GroupID = $_.value
            $GroupType = $ResolvedGroupTypes[$GroupID] ?? $_.addedFields.groupType
            $GroupName = $_.label
            Write-Host "About to add $($UserObj.userPrincipalName) to $GroupName. Group ID is: $GroupID and type is: $GroupType"

            try {
                if (& $UseExchangeForGroup $_.addedFields $ResolvedGroupTypes[$GroupID]) {
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

            $GroupID = $_.value
            $GroupType = $ResolvedGroupTypes[$GroupID] ?? $_.addedFields.groupType
            $GroupName = $_.label
            Write-Host "About to remove $($UserObj.userPrincipalName) from $GroupName. Group ID is: $GroupID and type is: $GroupType"

            try {
                if (& $UseExchangeForGroup $_.addedFields $ResolvedGroupTypes[$GroupID]) {
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
