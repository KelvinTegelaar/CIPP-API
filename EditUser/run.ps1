using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$userobj = $Request.body
$Results = [System.Collections.ArrayList]@()
$licenses = ($userobj | Select-Object "License_*").psobject.properties.value
$Aliases = if ($userobj.AddedAliases) { ($userobj.AddedAliases).Split([Environment]::NewLine) }

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
    Write-LogMessage -API $APINAME -tenant ($UserObj.tenantid) -user $request.headers.'x-ms-client-principal' -message "Edited user $($userobj.displayname) with id $($userobj.Userid)" -Sev "Info"
    if ($userobj.password) {
        $passwordProfile = [pscustomobject]@{"passwordProfile" = @{ "password" = $userobj.password; "forceChangePasswordNextSignIn" = [boolean]$UserObj.mustchangepass } } | ConvertTo-Json
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userobj.Userid)" -tenantid $Userobj.tenantid -type PATCH -body $PasswordProfile  -verbose
        $results.add("Success. The password has been set to $($userobj.password)")
        Write-LogMessage -API $APINAME -tenant ($UserObj.tenantid) -user $request.headers.'x-ms-client-principal' -message "Reset $($userobj.displayname)'s Password" -Sev "Info"
    }
}
catch {
    Write-LogMessage -API $APINAME -tenant ($UserObj.tenantid) -user $request.headers.'x-ms-client-principal' -message "User edit API failed. $($_.Exception.Message)" -Sev "Error"
    $results.add( "Failed to edit user. $($_.Exception.Message)")
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
        Write-LogMessage -API $APINAME -tenant ($UserObj.tenantid) -user $request.headers.'x-ms-client-principal'   -message "Added Aliases to $($userobj.displayname)" -Sev "Info"
        $results.add( "Success. added aliasses to user.")
    }

}
catch {
    Write-LogMessage -API $APINAME -tenant ($UserObj.tenantid) -user $request.headers.'x-ms-client-principal'   -message "Alias API failed. $($_.Exception.Message)" -Sev "Error"
    $results.add( "Successfully edited user. The password is $password. We've failed to create the Aliases: $($_.Exception.Message)")
}

if ($Request.body.CopyFrom -ne "") {
    $CopyFrom = Set-CIPPCopyGroupMembers -ExecutingUser $request.headers.'x-ms-client-principal' -tenantid $Userobj.tenantid -CopyFromId $Request.body.CopyFrom -UserID $user -TenantFilter  $Userobj.tenantid
    $results.AddRange($CopyFrom)
}
$body = @{"Results" = @($results) }
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
