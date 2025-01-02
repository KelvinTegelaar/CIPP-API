using namespace System.Net

Function Invoke-EditUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $UserObj = $Request.body
    if ($UserObj.id -eq '') {
        $body = @{'Results' = @('Failed to edit user. No user ID provided') }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = $Body
            })
        return
    }
    $Results = [System.Collections.Generic.List[string]]::new()
    $licenses = ($UserObj.licenses).value
    $Aliases = if ($UserObj.AddedAliases) { ($UserObj.AddedAliases) -split '\s' }
    $AddToGroups = $Request.body.AddToGroups
    $RemoveFromGroups = $Request.body.RemoveFromGroups

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    #Edit the user
    try {
        Write-Host "$([boolean]$UserObj.mustchangepass)"
        $UserprincipalName = "$($UserObj.Username ? $userobj.username :$userobj.mailNickname)@$($UserObj.Domain ? $UserObj.Domain : $UserObj.primDomain.value)"
        $BodyToship = [pscustomobject] @{
            'givenName'         = $UserObj.givenname
            'surname'           = $UserObj.surname
            'accountEnabled'    = $true
            'displayName'       = $UserObj.displayName
            'department'        = $UserObj.Department
            'mailNickname'      = $UserObj.Username ? $userobj.username :$userobj.mailNickname
            'userPrincipalName' = $UserprincipalName
            'usageLocation'     = $UserObj.usageLocation.value ? $UserObj.usageLocation.value : $UserObj.usageLocation
            'city'              = $UserObj.City
            'country'           = $UserObj.Country
            'jobtitle'          = $UserObj.Jobtitle
            'mobilePhone'       = $UserObj.MobilePhone
            'streetAddress'     = $UserObj.streetAddress
            'postalCode'        = $UserObj.PostalCode
            'companyName'       = $UserObj.CompanyName
            'passwordProfile'   = @{
                'forceChangePasswordNextSignIn' = [bool]$UserObj.MustChangePass
            }
        } | ForEach-Object {
            $NonEmptyProperties = $_.psobject.Properties | Select-Object -ExpandProperty Name
            $_ | Select-Object -Property $NonEmptyProperties
        }
        if ($UserObj.addedAttributes) {
            Write-Host 'Found added attribute'
            Write-Host "Added attributes: $($UserObj.addedAttributes | ConvertTo-Json)"
            $UserObj.addedAttributes.getenumerator() | ForEach-Object {
                $results.add("Edited property $($_.Key) with value $($_.Value)")
                $bodytoShip | Add-Member -NotePropertyName $_.Key -NotePropertyValue $_.Value -Force
            }
        }
        $bodyToShip = ConvertTo-Json -Depth 10 -InputObject $BodyToship -Compress
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $userObj.tenantFilter -type PATCH -body $BodyToship -verbose
        $results.add( 'Success. The user has been edited.' )
        Write-LogMessage -API $APINAME -tenant ($userObj.tenantFilter) -user $request.headers.'x-ms-client-principal' -message "Edited user $($UserObj.DisplayName) with id $($UserObj.id)" -Sev 'Info'
        if ($UserObj.password) {
            $passwordProfile = [pscustomobject]@{'passwordProfile' = @{ 'password' = $UserObj.password; 'forceChangePasswordNextSignIn' = [boolean]$UserObj.mustchangepass } } | ConvertTo-Json
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $userObj.tenantFilter -type PATCH -body $PasswordProfile -verbose
            $results.add("Success. The password has been set to $($UserObj.password)")
            Write-LogMessage -API $APINAME -tenant ($userObj.tenantFilter) -user $request.headers.'x-ms-client-principal' -message "Reset $($UserObj.DisplayName)'s Password" -Sev 'Info'
        }
    } catch {
        Write-LogMessage -API $APINAME -tenant ($userObj.tenantFilter) -user $request.headers.'x-ms-client-principal' -message "User edit API failed. $($_.Exception.Message)" -Sev 'Error'
        $results.add( "Failed to edit user. $($_.Exception.Message)")
    }


    #Reassign the licenses
    try {

        if ($licenses -or $UserObj.removeLicenses) {
            $CurrentLicenses = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $userObj.tenantFilter
            #if the list of skuIds in $CurrentLicenses.assignedLicenses is EXACTLY the same as $licenses, we don't need to do anything, but the order in both can be different.
            if (($CurrentLicenses.assignedLicenses.skuId -join ',') -eq ($licenses -join ',') -and $UserObj.removeLicenses -eq $false) {
                Write-Host "$($CurrentLicenses.assignedLicenses.skuId -join ',') $(($licenses -join ','))"
                $results.add( 'Success. User license is already correct.' )
            } else {
                if ($UserObj.removeLicenses) {
                    $licResults = Set-CIPPUserLicense -userid $UserObj.id -TenantFilter $UserObj.tenantFilter -RemoveLicenses $CurrentLicenses.assignedLicenses.skuId
                    $results.add($licResults)
                } else {
                    #Remove all objects from $CurrentLicenses.assignedLicenses.skuId that are in $licenses
                    $RemoveLicenses = $CurrentLicenses.assignedLicenses.skuId | Where-Object { $_ -notin $licenses }
                    $licResults = Set-CIPPUserLicense -userid $UserObj.id -TenantFilter $UserObj.tenantFilter -RemoveLicenses $RemoveLicenses -AddLicenses $licenses
                    $results.add($licResults)
                }

            }
        }

    } catch {
        Write-LogMessage -API $APINAME -tenant ($userObj.tenantFilter) -user $request.headers.'x-ms-client-principal' -message "License assign API failed. $($_.Exception.Message)" -Sev 'Error'
        $results.add( "We've failed to assign the license. $($_.Exception.Message)")
    }

    #Add Aliases, removal currently not supported.
    try {
        if ($Aliases) {
            Write-Host ($Aliases | ConvertTo-Json)
            foreach ($Alias in $Aliases) {
                New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $userObj.tenantFilter -type 'patch' -body "{`"mail`": `"$Alias`"}" -verbose
            }
            New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $userObj.tenantFilter -type 'patch' -body "{`"mail`": `"$UserprincipalName`"}" -verbose
            Write-LogMessage -API $APINAME -tenant ($userObj.tenantFilter) -user $request.headers.'x-ms-client-principal' -message "Added Aliases to $($UserObj.DisplayName)" -Sev 'Info'
            $results.add( 'Success. added aliases to user.')
        }

    } catch {
        Write-LogMessage -API $APINAME -tenant ($userObj.tenantFilter) -user $request.headers.'x-ms-client-principal' -message "Alias API failed. $($_.Exception.Message)" -Sev 'Error'
        $results.add( "Successfully edited user. The password is $password. We've failed to create the Aliases: $($_.Exception.Message)")
    }

    if ($Request.body.CopyFrom.value) {
        $CopyFrom = Set-CIPPCopyGroupMembers -ExecutingUser $request.headers.'x-ms-client-principal' -CopyFromId $Request.body.CopyFrom.value -UserID $UserprincipalName -TenantFilter $userObj.tenantFilter
        $results.AddRange($CopyFrom)
    }

    if ($AddToGroups) {
        $AddToGroups | ForEach-Object {

            $GroupType = $_.value.groupType -join ','
            $GroupID = $_.value.groupid
            $GroupName = $_.value.groupName
            Write-Host "About to add $($UserObj.userPrincipalName) to $GroupName. Group ID is: $GroupID and type is: $GroupType"

            try {

                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {

                    Write-Host 'Adding to group via Add-DistributionGroupMember '
                    $Params = @{ Identity = $GroupID; Member = $UserObj.id; BypassSecurityGroupManagerCheck = $true }
                    New-ExoRequest -tenantid $userObj.tenantFilter -cmdlet 'Add-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true

                } else {

                    Write-Host 'Adding to group via Graph'
                    $UserBody = [PSCustomObject]@{
                        '@odata.id' = "https://graph.microsoft.com/beta/directoryObjects/$($UserObj.id)"
                    }
                    $UserBodyJSON = ConvertTo-Json -Compress -Depth 10 -InputObject $UserBody
                    New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$GroupID/members/`$ref" -tenantid $userObj.tenantFilter -type POST -body $UserBodyJSON -Verbose

                }

                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $userObj.tenantFilter -message "Added $($UserObj.DisplayName) to $GroupName group" -Sev 'Info'
                $null = $results.add("Success. $($UserObj.DisplayName) has been added to $GroupName")
            } catch {
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $userObj.tenantFilter -message "Failed to add member $($UserObj.DisplayName) to $GroupName. Error:$($_.Exception.Message)" -Sev 'Error'
                $null = $results.add("Failed to add member $($UserObj.DisplayName) to $GroupName : $($_.Exception.Message)")
            }

        }
    }
    if ($Request.body.setManager.value) {
        $ManagerBody = [PSCustomObject]@{'@odata.id' = "https://graph.microsoft.com/beta/users/$($Request.body.setManager.value)" }
        $ManagerBodyJSON = ConvertTo-Json -Compress -Depth 10 -InputObject $ManagerBody
        New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)/manager/`$ref" -tenantid $userObj.tenantFilter -type PUT -body $ManagerBodyJSON -Verbose
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $userObj.tenantFilter -message "Set $($UserObj.DisplayName)'s manager to $($Request.body.setManager.label)" -Sev 'Info'
        $results.add("Success. Set $($UserObj.DisplayName)'s manager to $($Request.body.setManager.label)")
    }

    if ($RemoveFromGroups) {
        $RemoveFromGroups | ForEach-Object {

            $GroupType = $_.value.groupType -join ','
            $GroupID = $_.value.groupid
            $GroupName = $_.value.groupName
            Write-Host "About to remove $($UserObj.userPrincipalName) from $GroupName. Group ID is: $GroupID and type is: $GroupType"

            try {

                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {

                    Write-Host 'Removing From group via Remove-DistributionGroupMember '
                    $Params = @{ Identity = $GroupID; Member = $UserObj.id; BypassSecurityGroupManagerCheck = $true }
                    New-ExoRequest -tenantid $userObj.tenantFilter -cmdlet 'Remove-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true

                } else {

                    Write-Host 'Removing From group via Graph'
                    New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$GroupID/members/$($UserObj.id)/`$ref" -tenantid $userObj.tenantFilter -type DELETE

                }

                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $userObj.tenantFilter -message "Removed $($UserObj.DisplayName) from $GroupName group" -Sev 'Info'
                $null = $results.add("Success. $($UserObj.DisplayName) has been removed from $GroupName")
            } catch {
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $userObj.tenantFilter -message "Failed to remove member $($UserObj.DisplayName) from $GroupName. Error:$($_.Exception.Message)" -Sev 'Error'
                $null = $results.add("Failed to remove member $($UserObj.DisplayName) from $GroupName : $($_.Exception.Message)")
            }

        }
    }

    $body = @{'Results' = @($results) }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
