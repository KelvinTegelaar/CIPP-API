using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$userobj = $Request.body
$user = $request.headers.'x-ms-client-principal'

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
try {
    $licenses = ($userobj | Select-Object "License_*").psobject.properties.value
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
    } | ConvertTo-Json
    $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users" -tenantid $Userobj.tenantid-type POST -body $BodyToship   -verbose
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "Created user $($userobj.displayname) with id $($GraphRequest.id) " -Sev "Info"
    $body = [pscustomobject]@{"Results" = "Success.  <br> Username: $($UserprincipalName) <br>Password: $password" }

}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "User creation API failed. $($_.Exception.Message)" -Sev "Error"
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
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "Assigned user $($userobj.displayname) license $($licences)" -Sev "Info"
        $body = [pscustomobject]@{"Results" = "Success.  <br> Username: $($UserprincipalName) <br>Password: $password" }

    }
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "License assign API failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Succesfully created user.  <br> Username: $($UserprincipalName) <br>Password: $password <br> We've failed to assign the license. $($_.Exception.Message)" }
}

try {
    if ($aliasses) {
        foreach ($Alias in $aliasses) {
            Write-Host $Alias
            New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($GraphRequest.id)" -tenantid $Userobj.tenantid -type "patch" -body "{`"mail`": `"$Alias`"}" -verbose
        }
        New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($GraphRequest.id)" -tenantid $Userobj.tenantid -type "patch" -body "{`"mail`": `"$UserprincipalName`"}" -verbose
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "Added alias $($Alias) to $($userobj.displayname)" -Sev "Info"
        $body = [pscustomobject]@{"Results" = "Success. User has been created. <br> Username: $($UserprincipalName) <br>Password: $password" }
    }
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid) -message "Alias API failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Succesfully created user. <br> Username: $($UserprincipalName) <br>Password: $password <br> We've failed to create the aliasses: $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
