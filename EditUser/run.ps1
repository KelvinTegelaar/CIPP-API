using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$userobj = $Request.body
$user = $request.headers.'x-ms-client-principal'

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
#Edit the user
try {
    $Email = "$($UserObj.username)@$($UserObj.domain)"
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
        "userPrincipalName" = $Email
        "usageLocation"     = $UserObj.usageLocation
        "mobilePhone"       = $userobj.mobilePhone
        "streetAddress"     = $userobj.streetAddress
        "businessPhones"    = @($userobj.businessPhone)
        "passwordProfile"   = @{
            "forceChangePasswordNextSignIn" = [bool]$UserObj.mustchangepass
        }
    } | ForEach-Object {
        $NonEmptyProperties = $_.psobject.Properties | Where-Object { $_.Value } | Select-Object -ExpandProperty Name
        $_ | Select-Object -Property $NonEmptyProperties | ConvertTo-Json
    }
    $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userobj.Userid)" -tenantid $Userobj.tenantid -type PATCH -body $BodyToship  -verbose
    $body = [pscustomobject]@{"Results" = "Success. The user has been edited." }
    if ($userobj.password) {
        $passwordProfile = [pscustomobject] @{"passwordProfile" = @{ "password" = $userobj.password } } | ConvertTo-Json
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userobj.Userid)" -tenantid $Userobj.tenantid -type PATCH -body $PasswordProfile  -verbose
        $body = [pscustomobject]@{"Results" = "Success. The password has been set to $($userobj.password)" }
    }
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal'   -message "User edit API failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed to create user. $($_.Exception.Message)" }
    Log-Request -user $request.headers.'x-ms-client-principal'   -message "Edited user $($userobj.displayname) with id $($userobj.Userid)  for $($UserObj.tenantid)" -Sev "Info"
}


#Reassign the licenses
try {
    if ($licenses -or $userobj.RemoveAllLicenses) {
        $CurrentLicenses = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userobj.Userid)" -tenantid $Userobj.tenantid
        $RemovalList = ($CurrentLicenses.assignedLicenses | Where-Object -Property skuid -NotIn $licenses).skuid
        $LicensesToRemove = if ($RemovalList) { ConvertTo-Json @( $RemovalList ) } else { "[]" }
   
        $liclist = foreach ($license in $Licenses) { '{"disabledPlans": [],"skuId": "' + $license + '" },' }
        $LicenseBody = '{"addLicenses": [' + $LicList + '], "removeLicenses": ' + $LicensesToRemove + '}'
        
        Write-Host $LicenseBody
        $LicRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userobj.Userid)/assignlicense" -tenantid $Userobj.tenantid -type POST -body $LicenseBody -verbose

        Log-Request -user $request.headers.'x-ms-client-principal'   -message "Assigned user $($userobj.displayname) license $($licences)" -Sev "Info"
        $body = [pscustomobject]@{"Results" = "Success. User has been edited." }
    }

}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal'   -message "License assign API failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Succesfully edit user. The password is $password. We've failed to assign the license. $($_.Exception.Message)" }
}

#Add aliasses, removal currently not supported.
try {
    if ($aliasses) {
        foreach ($Alias in $aliasses) {
            New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userobj.Userid)" -tenantid $Userobj.tenantid -type "patch" -body "{`"mail`": `"$Alias`"}" -verbose
        }
        New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userobj.Userid)" -tenantid $Userobj.tenantid -type "patch" -body "{`"mail`": `"$UserprincipalName`"}" -verbose
        Log-Request -user $request.headers.'x-ms-client-principal'   -message "Added aliasses to $($userobj.displayname) license $($licences)" -Sev "Info"
        $body = [pscustomobject]@{"Results" = "Success. User has been edited" }
    }

}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal'   -message "Alias API failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Succesfully edited user. The password is $password. We've failed to create the aliasses: $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
