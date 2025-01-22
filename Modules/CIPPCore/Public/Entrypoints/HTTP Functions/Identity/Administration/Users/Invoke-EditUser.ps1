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

    $ApiName = $TriggerMetadata.FunctionName
    $User = $Request.headers.'x-ms-client-principal'
    Write-LogMessage -user $User -API $ApiName -message 'Accessed this API' -Sev 'Debug'

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
        Write-Host "$([boolean]$UserObj.MustChangePass)"
        $UserPrincipalName = "$($UserObj.Username ? $UserObj.username :$UserObj.mailNickname)@$($UserObj.Domain ? $UserObj.Domain : $UserObj.primDomain.value)"
        $BodyToship = [pscustomobject] @{
            'givenName'         = $UserObj.givenName
            'surname'           = $UserObj.surname
            'accountEnabled'    = $true
            'displayName'       = $UserObj.displayName
            'department'        = $UserObj.Department
            'mailNickname'      = $UserObj.Username ? $UserObj.username :$UserObj.mailNickname
            'userPrincipalName' = $UserPrincipalName
            'usageLocation'     = $UserObj.usageLocation.value ? $UserObj.usageLocation.value : $UserObj.usageLocation
            'city'              = $UserObj.City
            'country'           = $UserObj.Country
            'jobTitle'          = $UserObj.jobTitle
            'mobilePhone'       = $UserObj.MobilePhone
            'streetAddress'     = $UserObj.streetAddress
            'postalCode'        = $UserObj.PostalCode
            'companyName'       = $UserObj.CompanyName
            'otherMails'        = @($UserObj.otherMails)
            'passwordProfile'   = @{
                'forceChangePasswordNextSignIn' = [bool]$UserObj.MustChangePass
            }
        } | ForEach-Object {
            $NonEmptyProperties = $_.PSObject.Properties | Select-Object -ExpandProperty Name
            $_ | Select-Object -Property $NonEmptyProperties
        }
        if ($UserObj.addedAttributes) {
            Write-Host 'Found added attribute'
            Write-Host "Added attributes: $($UserObj.addedAttributes | ConvertTo-Json)"
            $UserObj.addedAttributes.GetEnumerator() | ForEach-Object {
                $null = $results.Add("Edited property $($_.Key) with value $($_.Value)")
                $bodytoShip | Add-Member -NotePropertyName $_.Key -NotePropertyValue $_.Value -Force
            }
        }
        $bodyToShip = ConvertTo-Json -Depth 10 -InputObject $BodyToship -Compress
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $UserObj.tenantFilter -type PATCH -body $BodyToship -verbose
        $null = $results.Add( 'Success. The user has been edited.' )
        Write-LogMessage -API $ApiName -tenant ($UserObj.tenantFilter) -user $User -message "Edited user $($UserObj.DisplayName) with id $($UserObj.id)" -Sev Info
        if ($UserObj.password) {
            $passwordProfile = [pscustomobject]@{'passwordProfile' = @{ 'password' = $UserObj.password; 'forceChangePasswordNextSignIn' = [boolean]$UserObj.MustChangePass } } | ConvertTo-Json
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $UserObj.tenantFilter -type PATCH -body $PasswordProfile -verbose
            $null = $results.Add("Success. The password has been set to $($UserObj.password)")
            Write-LogMessage -API $ApiName -tenant ($UserObj.tenantFilter) -user $User -message "Reset $($UserObj.DisplayName)'s Password" -Sev Info
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $ApiName -tenant ($UserObj.tenantFilter) -user $User -message "User edit API failed. $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $null = $results.Add( "Failed to edit user. $($ErrorMessage.NormalizedError)")
    }


    #Reassign the licenses
    try {

        if ($licenses -or $UserObj.removeLicenses) {
            $CurrentLicenses = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $UserObj.tenantFilter
            #if the list of skuIds in $CurrentLicenses.assignedLicenses is EXACTLY the same as $licenses, we don't need to do anything, but the order in both can be different.
            if (($CurrentLicenses.assignedLicenses.skuId -join ',') -eq ($licenses -join ',') -and $UserObj.removeLicenses -eq $false) {
                Write-Host "$($CurrentLicenses.assignedLicenses.skuId -join ',') $(($licenses -join ','))"
                $null = $results.Add( 'Success. User license is already correct.' )
            } else {
                if ($UserObj.removeLicenses) {
                    $licResults = Set-CIPPUserLicense -UserId $UserObj.id -TenantFilter $UserObj.tenantFilter -RemoveLicenses $CurrentLicenses.assignedLicenses.skuId
                    $null = $results.Add($licResults)
                } else {
                    #Remove all objects from $CurrentLicenses.assignedLicenses.skuId that are in $licenses
                    $RemoveLicenses = $CurrentLicenses.assignedLicenses.skuId | Where-Object { $_ -notin $licenses }
                    $licResults = Set-CIPPUserLicense -UserId $UserObj.id -TenantFilter $UserObj.tenantFilter -RemoveLicenses $RemoveLicenses -AddLicenses $licenses
                    $null = $results.Add($licResults)
                }

            }
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $ApiName -tenant ($UserObj.tenantFilter) -user $User -message "License assign API failed. $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $null = $results.Add( "We've failed to assign the license. $($ErrorMessage.NormalizedError)")
    }

    #Add Aliases, removal currently not supported.
    try {
        if ($Aliases) {
            Write-Host ($Aliases | ConvertTo-Json)
            foreach ($Alias in $Aliases) {
                $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $UserObj.tenantFilter -type 'patch' -body "{`"mail`": `"$Alias`"}" -Verbose
            }
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $UserObj.tenantFilter -type 'patch' -body "{`"mail`": `"$UserPrincipalName`"}" -Verbose
            Write-LogMessage -API $ApiName -tenant ($UserObj.tenantFilter) -user $User -message "Added Aliases to $($UserObj.DisplayName)" -Sev Info
            $null = $results.Add( 'Success. added aliases to user.')
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $ApiName -tenant ($UserObj.tenantFilter) -user $User -message "Alias API failed. $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $null = $results.Add( "Successfully edited user. The password is $password. We've failed to create the Aliases: $($ErrorMessage.NormalizedError)")
    }

    if ($Request.body.CopyFrom.value) {
        $CopyFrom = Set-CIPPCopyGroupMembers -ExecutingUser $User -CopyFromId $Request.body.CopyFrom.value -UserID $UserPrincipalName -TenantFilter $UserObj.tenantFilter
        $null = $results.AddRange($CopyFrom)
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
                    $null = New-ExoRequest -tenantid $UserObj.tenantFilter -cmdlet 'Add-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true

                } else {

                    Write-Host 'Adding to group via Graph'
                    $UserBody = [PSCustomObject]@{
                        '@odata.id' = "https://graph.microsoft.com/beta/directoryObjects/$($UserObj.id)"
                    }
                    $UserBodyJSON = ConvertTo-Json -Compress -Depth 10 -InputObject $UserBody
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$GroupID/members/`$ref" -tenantid $UserObj.tenantFilter -type POST -body $UserBodyJSON -Verbose

                }

                Write-LogMessage -user $User -API $ApiName -tenant $UserObj.tenantFilter -message "Added $($UserObj.DisplayName) to $GroupName group" -Sev Info
                $null = $results.Add("Success. $($UserObj.DisplayName) has been added to $GroupName")
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -user $User -API $ApiName -tenant $UserObj.tenantFilter -message "Failed to add member $($UserObj.DisplayName) to $GroupName. Error:$($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
                $null = $results.Add("Failed to add member $($UserObj.DisplayName) to $GroupName : $($ErrorMessage.NormalizedError)")
            }

        }
    }
    if ($Request.body.setManager.value) {
        $ManagerBody = [PSCustomObject]@{'@odata.id' = "https://graph.microsoft.com/beta/users/$($Request.body.setManager.value)" }
        $ManagerBodyJSON = ConvertTo-Json -Compress -Depth 10 -InputObject $ManagerBody
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)/manager/`$ref" -tenantid $UserObj.tenantFilter -type PUT -body $ManagerBodyJSON -Verbose
        Write-LogMessage -user $User -API $ApiName -tenant $UserObj.tenantFilter -message "Set $($UserObj.DisplayName)'s manager to $($Request.body.setManager.label)" -Sev Info
        $null = $results.Add("Success. Set $($UserObj.DisplayName)'s manager to $($Request.body.setManager.label)")
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
                    $null = New-ExoRequest -tenantid $UserObj.tenantFilter -cmdlet 'Remove-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true

                } else {

                    Write-Host 'Removing From group via Graph'
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$GroupID/members/$($UserObj.id)/`$ref" -tenantid $UserObj.tenantFilter -type DELETE

                }

                Write-LogMessage -user $User -API $ApiName -tenant $UserObj.tenantFilter -message "Removed $($UserObj.DisplayName) from $GroupName group" -Sev Info
                $null = $results.Add("Success. $($UserObj.DisplayName) has been removed from $GroupName")
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -user $User -API $ApiName -tenant $UserObj.tenantFilter -message "Failed to remove member $($UserObj.DisplayName) from $GroupName. Error:$($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
                $null = $results.Add("Failed to remove member $($UserObj.DisplayName) from $GroupName : $($ErrorMessage.NormalizedError)")
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
