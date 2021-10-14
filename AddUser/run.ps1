using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$userobj = $Request.body
$user = $request.headers.'x-ms-client-principal'

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
try {
    $licenses = ($userobj | select-object "License_*").psobject.properties.value
    $aliasses = ($userobj.AddedAliasses).Split([Environment]::NewLine)
    $password = if ($userobj.password) { $userobj.password } else { -join ('abcdefghkmnrstuvwxyzABCDEFGHKLMNPRSTUVWXYZ23456789$%&*#'.ToCharArray() | Get-Random -Count 12) }
    $UserprincipalName = "$($UserObj.username)@$($UserObj.domain)"
    $BodyToship = [pscustomobject] @{
        "givenName"         = $userobj.firstname
        "surname"           = $userobj.lastname
        "accountEnabled"    = $true
        "displayName"       = $UserObj.Displayname
        "mailNickname"      = $UserObj.username
        "userPrincipalName" = $UserprincipalName
        "usageLocation"     = $UserObj.usageLocation
        "passwordProfile"   = @{
            "forceChangePasswordNextSignIn" = [bool]$UserObj.mustchangepass
            "password"                      = $password
        }
    } | convertto-json
    $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users" -tenantid $Userobj.tenantid-type POST -body $BodyToship   -verbose
        Log-Request -user $request.headers.'x-ms-client-principal'   -message "Created user $($userobj.displayname) with id $($GraphRequest.id) for $($UserObj.tenantid)" -Sev "Info"

}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal'   -message "User creation API failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed to create user. $($_.Exception.Message)" }
}

try {
    if ($licenses) {
        $LicenseBody = if ($licenses.count -ge 2) {
            $liclist = foreach ($license in $Licenses) { '{"disabledPlans": [],"skuId": "' + $license + '" },' }
            '{"addLicenses": [' + $LicList + '], "removeLicenses": [ ] }'
        }
        else {
            '{"addLicenses": [ {"disabledPlans": [],"skuId": "' + $licenses + '" }],"removeLicenses": [ ]}'
        }
        $LicRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($GraphRequest.id)/assignlicense" -tenantid $Userobj.tenantid -type POST -body $LicenseBody -verbose
        Log-Request -user $request.headers.'x-ms-client-principal'   -message "Assigned user $($userobj.displayname) license $($licences)" -Sev "Info"
    }
    $body = [pscustomobject]@{"Results" = "Success. User has been created. The password is $password" }
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal'   -message "License assign API failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Succesfully created user. The password is $password. We've failed to assign the license. $($_.Exception.Message)" }
}

try {
    if ($aliasses) {
        foreach ($Alias in $aliasses) {
            write-host $Alias
            New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($GraphRequest.id)" -tenantid $Userobj.tenantid -type "patch" -body "{`"mail`": `"$Alias`"}" -verbose
        }
        New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($GraphRequest.id)" -tenantid $Userobj.tenantid -type "patch" -body "{`"mail`": `"$UserprincipalName`"}" -verbose

    }
    Log-Request -user $request.headers.'x-ms-client-principal'   -message "Added aliasses to $($userobj.displayname) license $($licences)" -Sev "Info"
    $body = [pscustomobject]@{"Results" = "Success. Uses has been created. The password is $password" }
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal'   -message "Alias API failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Succesfully created user. The password is $password. We've failed to create the aliasses: $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
