using namespace System.Net

Function Invoke-EditUser {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $UserObj = $Request.body
    if ($UserObj.UserID -eq '') {
        $body = @{'Results' = @('Failed to edit user. No user ID provided') }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = $Body
            })
        return
    }
    $Results = [System.Collections.Generic.List[string]]::new()
    $licenses = ($UserObj | Select-Object 'License_*').psobject.properties.value
    $Aliases = if ($UserObj.AddedAliases) { ($UserObj.AddedAliases) -split '\s' }
    $AddToGroups = $Request.body.AddToGroups
    $RemoveFromGroups = $Request.body.RemoveFromGroups

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    #Edit the user
    try {
        Write-Host "$([boolean]$UserObj.mustchangepass)"
        $Email = "$($UserObj.Username)@$($UserObj.Domain)"
        $UserprincipalName = "$($UserObj.Username)@$($UserObj.Domain)"
        $BodyToship = [pscustomobject] @{
            'givenName'         = $UserObj.firstName
            'surname'           = $UserObj.LastName
            'city'              = $UserObj.City
            'country'           = $UserObj.Country
            'department'        = $UserObj.Department
            'displayName'       = $UserObj.DisplayName
            'postalCode'        = $UserObj.PostalCode
            'companyName'       = $UserObj.CompanyName
            'jobTitle'          = $UserObj.JobTitle
            'userPrincipalName' = $Email
            'usageLocation'     = $UserObj.usagelocation
            'mobilePhone'       = $UserObj.MobilePhone
            'streetAddress'     = $UserObj.streetAddress
            'businessPhones'    = @($UserObj.BusinessPhone)
            'passwordProfile'   = @{
                'forceChangePasswordNextSignIn' = [boolean]$UserObj.mustchangepass
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
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.UserID)" -tenantid $UserObj.tenantID -type PATCH -body $BodyToship -verbose
        $results.add( 'Success. The user has been edited.' )
        Write-LogMessage -API $APINAME -tenant ($UserObj.tenantID) -user $request.headers.'x-ms-client-principal' -message "Edited user $($UserObj.DisplayName) with id $($UserObj.UserID)" -Sev 'Info'
        if ($UserObj.password) {
            $passwordProfile = [pscustomobject]@{'passwordProfile' = @{ 'password' = $UserObj.password; 'forceChangePasswordNextSignIn' = [boolean]$UserObj.mustchangepass } } | ConvertTo-Json
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.UserID)" -tenantid $UserObj.tenantID -type PATCH -body $PasswordProfile -verbose
            $results.add("Success. The password has been set to $($UserObj.password)")
            Write-LogMessage -API $APINAME -tenant ($UserObj.tenantID) -user $request.headers.'x-ms-client-principal' -message "Reset $($UserObj.DisplayName)'s Password" -Sev 'Info'
        }
    } catch {
        Write-LogMessage -API $APINAME -tenant ($UserObj.tenantID) -user $request.headers.'x-ms-client-principal' -message "User edit API failed. $($_.Exception.Message)" -Sev 'Error'
        $results.add( "Failed to edit user. $($_.Exception.Message)")
    }


    #Reassign the licenses
    try {

        if ($licenses -or $UserObj.RemoveAllLicenses) {
            $licenses = (($UserObj | Select-Object 'License_*').psobject.properties | Where-Object { $_.value -EQ $true }).name -replace 'License_', ''
            $CurrentLicenses = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.UserID)" -tenantid $UserObj.tenantID
            $RemovalList = ($CurrentLicenses.assignedLicenses | Where-Object -Property skuid -NotIn $licenses).skuid
            $LicensesToRemove = if ($RemovalList) { ConvertTo-Json @( $RemovalList ) } else { '[]' }

            $liclist = foreach ($license in $Licenses) { '{"disabledPlans": [],"skuId": "' + $license + '" },' }
            $LicenseBody = '{"addLicenses": [' + $LicList + '], "removeLicenses": ' + $LicensesToRemove + '}'
            if ($UserObj.RemoveAllLicenses) { $LicenseBody = '{"addLicenses": [], "removeLicenses": ' + $LicensesToRemove + '}' }
            Write-Host $LicenseBody
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.UserID)/assignlicense" -tenantid $UserObj.tenantID -type POST -body $LicenseBody -verbose

            Write-LogMessage -API $APINAME -tenant ($UserObj.tenantID) -user $request.headers.'x-ms-client-principal' -message "Changed user $($UserObj.DisplayName) license. Sent info: $licensebody" -Sev 'Info'
            $results.add( 'Success. User license has been edited.' )
        }

    } catch {
        Write-LogMessage -API $APINAME -tenant ($UserObj.tenantID) -user $request.headers.'x-ms-client-principal' -message "License assign API failed. $($_.Exception.Message)" -Sev 'Error'
        $results.add( "We've failed to assign the license. $($_.Exception.Message)")
    }

    #Add Aliases, removal currently not supported.
    try {
        if ($Aliases) {
            Write-Host ($Aliases | ConvertTo-Json)
            foreach ($Alias in $Aliases) {
                New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.UserID)" -tenantid $UserObj.tenantID -type 'patch' -body "{`"mail`": `"$Alias`"}" -verbose
            }
            New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.UserID)" -tenantid $UserObj.tenantID -type 'patch' -body "{`"mail`": `"$UserprincipalName`"}" -verbose
            Write-LogMessage -API $APINAME -tenant ($UserObj.tenantID) -user $request.headers.'x-ms-client-principal' -message "Added Aliases to $($UserObj.DisplayName)" -Sev 'Info'
            $results.add( 'Success. added aliases to user.')
        }

    } catch {
        Write-LogMessage -API $APINAME -tenant ($UserObj.tenantID) -user $request.headers.'x-ms-client-principal' -message "Alias API failed. $($_.Exception.Message)" -Sev 'Error'
        $results.add( "Successfully edited user. The password is $password. We've failed to create the Aliases: $($_.Exception.Message)")
    }

    if ($Request.body.CopyFrom -ne '') {
        $CopyFrom = Set-CIPPCopyGroupMembers -ExecutingUser $request.headers.'x-ms-client-principal' -CopyFromId $Request.body.CopyFrom -UserID $UserprincipalName -TenantFilter $UserObj.tenantID
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
                    $Params = @{ Identity = $GroupID; Member = $UserObj.UserID; BypassSecurityGroupManagerCheck = $true }
                    New-ExoRequest -tenantid $UserObj.tenantID -cmdlet 'Add-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true

                } else {

                    Write-Host 'Adding to group via Graph'
                    $UserBody = [PSCustomObject]@{
                        '@odata.id' = "https://graph.microsoft.com/beta/directoryObjects/$($UserObj.UserID)"
                    }
                    $UserBodyJSON = ConvertTo-Json -Compress -Depth 10 -InputObject $UserBody
                    New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$GroupID/members/`$ref" -tenantid $UserObj.tenantID -type POST -body $UserBodyJSON -Verbose

                }

                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $UserObj.tenantID -message "Added $($UserObj.DisplayName) to $GroupName group" -Sev 'Info'
                $null = $results.add("Success. $($UserObj.DisplayName) has been added to $GroupName")
            } catch {
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $UserObj.tenantID -message "Failed to add member $($UserObj.DisplayName) to $GroupName. Error:$($_.Exception.Message)" -Sev 'Error'
                $null = $results.add("Failed to add member $($UserObj.DisplayName) to $GroupName : $($_.Exception.Message)")
            }

        }
    }
    if ($Request.body.setManager) {
        $ManagerBody = [PSCustomObject]@{'@odata.id' = "https://graph.microsoft.com/beta/users/$($Request.body.setManager.value)" }
        $ManagerBodyJSON = ConvertTo-Json -Compress -Depth 10 -InputObject $ManagerBody
        New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.UserID)/manager/`$ref" -tenantid $UserObj.tenantID -type PUT -body $ManagerBodyJSON -Verbose
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $UserObj.tenantID -message "Set $($UserObj.DisplayName)'s manager to $($Request.body.setManager.label)" -Sev 'Info'
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
                    $Params = @{ Identity = $GroupID; Member = $UserObj.UserID; BypassSecurityGroupManagerCheck = $true }
                    New-ExoRequest -tenantid $UserObj.tenantID -cmdlet 'Remove-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true

                } else {

                    Write-Host 'Removing From group via Graph'
                    New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$GroupID/members/$($UserObj.UserID)/`$ref" -tenantid $UserObj.tenantID -type DELETE

                }

                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $UserObj.tenantID -message "Removed $($UserObj.DisplayName) from $GroupName group" -Sev 'Info'
                $null = $results.add("Success. $($UserObj.DisplayName) has been removed from $GroupName")
            } catch {
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $UserObj.tenantID -message "Failed to remove member $($UserObj.DisplayName) from $GroupName. Error:$($_.Exception.Message)" -Sev 'Error'
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
