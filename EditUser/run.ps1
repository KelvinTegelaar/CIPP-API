using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$userobj = $Request.body
$Results = [System.Collections.ArrayList]@()
$licenses = ($userobj | Select-Object "License_*").psobject.properties.value
$Aliases = ($userobj.AddedAliases).Split([Environment]::NewLine)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
#Edit the user
try {
    Write-Host "$([boolean]$UserObj.mustchangepass)"
    $Email = "$($UserObj.username)@$($UserObj.domain)"
    $UserprincipalName = "$($UserObj.username)@$($UserObj.domain)"
    $BodyToship = [pscustomobject] @{
        "givenName"         = $userobj.firstname
        "surname"           = $userobj.lastname
        "city"              = $userobj.city
        "country"           = $userobj.country
        "department"        = $userobj.department
        "displayName"       = $UserObj.Displayname
        "postalCode"        = $userobj.postalCode
        "companyName"       = $userobj.companyName
        "mailNickname"      = $UserObj.username
        "jobTitle"          = $UserObj.JobTitle
        "userPrincipalName" = $Email
        "usageLocation"     = $UserObj.usageLocation
        "mobilePhone"       = $userobj.mobilePhone
        "streetAddress"     = $userobj.streetAddress
        "businessPhones"    = @($userobj.businessPhone)
        "passwordProfile"   = @{
            "forceChangePasswordNextSignIn" = [boolean]$UserObj.mustchangepass
        }
    } | ForEach-Object {
        $NonEmptyProperties = $_.psobject.Properties | Select-Object -ExpandProperty Name
        $_ | Select-Object -Property $NonEmptyProperties | ConvertTo-Json
    }
    $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userobj.Userid)" -tenantid $Userobj.tenantid -type PATCH -body $BodyToship  -verbose
    $results.add( "Success. The user has been edited." )
    if ($userobj.password) {
        $passwordProfile = [pscustomobject] @{"passwordProfile" = @{ "password" = $userobj.password } } | ConvertTo-Json
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userobj.Userid)" -tenantid $Userobj.tenantid -type PATCH -body $PasswordProfile  -verbose
        $results.add("Success. The password has been set to $($userobj.password)")
    }
}
catch {
    Write-LogMessage -API $APINAME -tenant ($UserObj.tenantid) -user $request.headers.'x-ms-client-principal' -message "User edit API failed. $($_.Exception.Message)" -Sev "Error"
    $results.add( "Failed to edit user. $($_.Exception.Message)")
    Write-LogMessage -API $APINAME -tenant ($UserObj.tenantid) -user $request.headers.'x-ms-client-principal' -message "Edited user $($userobj.displayname) with id $($userobj.Userid)" -Sev "Info"
}


#Reassign the licenses
try {

    if ($licenses -or $userobj.RemoveAllLicenses) {
        $licenses = (($userobj | Select-Object "License_*").psobject.properties | Where-Object { $_.value -EQ $true }).name -replace "License_", ""
        $CurrentLicenses = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userobj.Userid)" -tenantid $Userobj.tenantid
        $RemovalList = ($CurrentLicenses.assignedLicenses | Where-Object -Property skuid -NotIn $licenses).skuid
        $LicensesToRemove = if ($RemovalList) { ConvertTo-Json @( $RemovalList ) } else { "[]" }
   
        $liclist = foreach ($license in $Licenses) { '{"disabledPlans": [],"skuId": "' + $license + '" },' }
        $LicenseBody = '{"addLicenses": [' + $LicList + '], "removeLicenses": ' + $LicensesToRemove + '}'
        if ($userobj.RemoveAllLicenses) { $LicenseBody = '{"addLicenses": [], "removeLicenses": ' + $LicensesToRemove + '}' }
        Write-Host $LicenseBody
        $LicRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userobj.Userid)/assignlicense" -tenantid $Userobj.tenantid -type POST -body $LicenseBody -verbose

        Write-LogMessage -API $APINAME -tenant ($UserObj.tenantid) -user $request.headers.'x-ms-client-principal' -message "Changed user $($userobj.displayname) license. Sent info: $licensebody" -Sev "Info"
        $results.add( "Success. User license has been edited." )
    }

}
catch {
    Write-LogMessage -API $APINAME -tenant ($UserObj.tenantid) -user $request.headers.'x-ms-client-principal' -message "License assign API failed. $($_.Exception.Message)" -Sev "Error"
    $results.add( "We've failed to assign the license. $($_.Exception.Message)")
}

#Add Aliases, removal currently not supported.
try {
    if ($Aliases) {
        foreach ($Alias in $Aliases) {
            New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userobj.Userid)" -tenantid $Userobj.tenantid -type "patch" -body "{`"mail`": `"$Alias`"}" -verbose
        }
        New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userobj.Userid)" -tenantid $Userobj.tenantid -type "patch" -body "{`"mail`": `"$UserprincipalName`"}" -verbose
        Write-LogMessage -API $APINAME -tenant ($UserObj.tenantid) -user $request.headers.'x-ms-client-principal'   -message "Added Aliases to $($userobj.displayname) license $($licences)" -Sev "Info"
        $results.add( "Success. added aliasses to user.")
    }

}
catch {
    Write-LogMessage -API $APINAME -tenant ($UserObj.tenantid) -user $request.headers.'x-ms-client-principal'   -message "Alias API failed. $($_.Exception.Message)" -Sev "Error"
    $results.add( "Successfully edited user. The password is $password. We've failed to create the Aliases: $($_.Exception.Message)")
}

if ($Request.body.CopyFrom -ne "") {
    $MemberIDs = "https://graph.microsoft.com/v1.0/directoryObjects/" + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userobj.Userid)" -tenantid $Userobj.tenantid).id 
    $addmemberbody = "{ `"members@odata.bind`": $(ConvertTo-Json @($MemberIDs)) }"
        (New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($Request.body.CopyFrom)/GetMemberGroups" -tenantid $Userobj.tenantid -type POST -body  '{"securityEnabledOnly": false}').value | ForEach-Object {
        try {
            $groupname = (New-GraphGetRequest -tenantid $Userobj.tenantid -asApp $true -uri "https://graph.microsoft.com/beta/groups/$($_)").displayName
            Write-Host "name: $groupname"
            $GroupResult = New-GraphPostRequest -AsApp $true -uri "https://graph.microsoft.com/beta/groups/$($_)" -tenantid $Userobj.tenantid -type patch -body $addmemberbody -ErrorAction Stop
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Added $($UserprincipalName) to group $groupresult.displayName)" -Sev "Info"  -tenant $TenantFilter
            $body = $results.add("Added group: $($groupname)")
        }
        catch {
            $body = $results.add("We've failed to add the group $($groupname): $($_.Exception.Message)")
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid) -message "Failed to add group. $($_.Exception.Message)" -Sev "Error"
        }
    }

}
$body = @{"Results" = @($results) }
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
