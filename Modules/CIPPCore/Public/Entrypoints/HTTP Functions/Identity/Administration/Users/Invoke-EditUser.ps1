using namespace System.Net

function Invoke-EditUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $UserObj = $Request.Body
    if ([string]::IsNullOrWhiteSpace($UserObj.id)) {
        $body = @{'Results' = @('Failed to edit user. No user ID provided') }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = $Body
            })
        return
    }
    $Results = [System.Collections.Generic.List[object]]::new()
    $licenses = ($UserObj.licenses).value
    $Aliases = if ($UserObj.AddedAliases) { ($UserObj.AddedAliases) -split '\s' }
    $AddToGroups = $Request.Body.AddToGroups
    $RemoveFromGroups = $Request.Body.RemoveFromGroups


    #Edit the user
    try {
        Write-Host "$([boolean]$UserObj.MustChangePass)"
        $UserPrincipalName = "$($UserObj.username)@$($UserObj.Domain ? $UserObj.Domain : $UserObj.primDomain.value)"
        $BodyToship = [pscustomobject] @{
            'givenName'         = $UserObj.givenName
            'surname'           = $UserObj.surname
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
            'businessPhones'    = $UserObj.businessPhones ? @($UserObj.businessPhones) : @()
            'otherMails'        = $UserObj.otherMails ? @($UserObj.otherMails) : @()
            'passwordProfile'   = @{
                'forceChangePasswordNextSignIn' = [bool]$UserObj.MustChangePass
            }
        } | ForEach-Object {
            $NonEmptyProperties = $_.PSObject.Properties | Select-Object -ExpandProperty Name
            $_ | Select-Object -Property $NonEmptyProperties
        }
        if ($UserObj.defaultAttributes) {
            $UserObj.defaultAttributes | Get-Member -MemberType NoteProperty | ForEach-Object {
                Write-Host "Editing user and adding $($_.Name) with value $($UserObj.defaultAttributes.$($_.Name).value)"
                if (-not [string]::IsNullOrWhiteSpace($UserObj.defaultAttributes.$($_.Name).value)) {
                    Write-Host 'adding body to ship'
                    $BodyToShip | Add-Member -NotePropertyName $_.Name -NotePropertyValue $UserObj.defaultAttributes.$($_.Name).value -Force
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
                        userId      = $UserObj.id
                        APIName     = 'Sherweb License Assignment'
                        AddLicenses = $licenses
                    }
                    ScheduledTime = 0 #right now, which is in the next 15 minutes and should cover most cases.
                    PostExecution = @{
                        Webhook = [bool]$Request.Body.PostExecution.webhook
                        Email   = [bool]$Request.Body.PostExecution.email
                        PSA     = [bool]$Request.Body.PostExecution.psa
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
                        $licResults = Set-CIPPUserLicense -UserId $UserObj.id -TenantFilter $UserObj.tenantFilter -RemoveLicenses $CurrentLicenses.assignedLicenses.skuId -Headers $Headers
                        $Results.Add($licResults)
                    } else {
                        #Remove all objects from $CurrentLicenses.assignedLicenses.skuId that are in $licenses
                        $RemoveLicenses = $CurrentLicenses.assignedLicenses.skuId | Where-Object { $_ -notin $licenses }
                        $licResults = Set-CIPPUserLicense -UserId $UserObj.id -TenantFilter $UserObj.tenantFilter -RemoveLicenses $RemoveLicenses -AddLicenses $licenses -Headers $headers
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
            $null = $Results.Add( 'Success. Added aliases to user.')
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to add aliases to user $($UserObj.DisplayName). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -tenant ($UserObj.tenantFilter) -headers $Headers -message $Message -Sev Error -LogData $ErrorMessage
        $null = $Results.Add($Message)
    }

    if ($Request.Body.CopyFrom.value) {
        $CopyFrom = Set-CIPPCopyGroupMembers -Headers $Headers -CopyFromId $Request.Body.CopyFrom.value -UserID $UserPrincipalName -TenantFilter $UserObj.tenantFilter
        $null = $Results.AddRange(@($CopyFrom))
    }

    if ($AddToGroups) {
        $AddToGroups | ForEach-Object {

            $GroupType = $_.addedFields.calculatedGroupType
            $GroupID = $_.value
            $GroupName = $_.label
            Write-Host "About to add $($UserObj.userPrincipalName) to $GroupName. Group ID is: $GroupID and type is: $GroupType"

            try {
                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
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
                $null = $Results.Add("Success. $($UserObj.DisplayName) has been added to $GroupName")
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Message = "Failed to add member $($UserObj.DisplayName) to $GroupName. Error: $($ErrorMessage.NormalizedError)"
                Write-LogMessage -headers $Headers -API $APIName -tenant $UserObj.tenantFilter -message $Message -Sev Error -LogData $ErrorMessage
                $null = $Results.Add($Message)
            }
        }
    }

    if ($RemoveFromGroups) {
        $RemoveFromGroups | ForEach-Object {

            $GroupType = $_.addedFields.calculatedGroupType
            $GroupID = $_.value
            $GroupName = $_.label
            Write-Host "About to remove $($UserObj.userPrincipalName) from $GroupName. Group ID is: $GroupID and type is: $GroupType"

            try {
                if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
                    Write-Host 'Removing From group via Remove-DistributionGroupMember'
                    $Params = @{ Identity = $GroupID; Member = $UserObj.id; BypassSecurityGroupManagerCheck = $true }
                    $null = New-ExoRequest -tenantid $UserObj.tenantFilter -cmdlet 'Remove-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true
                } else {
                    Write-Host 'Removing From group via Graph'
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$GroupID/members/$($UserObj.id)/`$ref" -tenantid $UserObj.tenantFilter -type DELETE
                }
                Write-LogMessage -headers $Headers -API $APIName -tenant $UserObj.tenantFilter -message "Removed $($UserObj.DisplayName) from $GroupName group" -Sev Info
                $null = $Results.Add("Success. $($UserObj.DisplayName) has been removed from $GroupName")
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Message = "Failed to remove member $($UserObj.DisplayName) from $GroupName. Error: $($ErrorMessage.NormalizedError)"
                Write-LogMessage -headers $Headers -API $APIName -tenant $UserObj.tenantFilter -message $Message -Sev Error -LogData $ErrorMessage
                $null = $Results.Add($Message)
            }
        }
    }

    if ($Request.body.setManager.value) {
        $ManagerBody = [PSCustomObject]@{'@odata.id' = "https://graph.microsoft.com/beta/users/$($Request.body.setManager.value)" }
        $ManagerBodyJSON = ConvertTo-Json -Compress -Depth 10 -InputObject $ManagerBody
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)/manager/`$ref" -tenantid $UserObj.tenantFilter -type PUT -body $ManagerBodyJSON -Verbose
        Write-LogMessage -headers $Headers -API $APIName -tenant $UserObj.tenantFilter -message "Set $($UserObj.DisplayName)'s manager to $($Request.body.setManager.label)" -Sev Info
        $null = $Results.Add("Success. Set $($UserObj.DisplayName)'s manager to $($Request.body.setManager.label)")
    }

    if ($Request.body.setSponsor.value) {
        $SponsorBody = [PSCustomObject]@{'@odata.id' = "https://graph.microsoft.com/beta/users/$($Request.body.setSponsor.value)" }
        $SponsorBodyJSON = ConvertTo-Json -Compress -Depth 10 -InputObject $SponsorBody
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)/sponsors/`$ref" -tenantid $UserObj.tenantFilter -type POST -body $SponsorBodyJSON -Verbose
        Write-LogMessage -headers $Headers -API $APIName -tenant $UserObj.tenantFilter -message "Set $($UserObj.DisplayName)'s sponsor to $($Request.body.setSponsor.label)" -Sev Info
        $null = $Results.Add("Success. Set $($UserObj.DisplayName)'s sponsor to $($Request.body.setSponsor.label)")
    }

    $body = @{'Results' = @($results) }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
