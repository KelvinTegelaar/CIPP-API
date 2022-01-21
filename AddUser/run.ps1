using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$Results = [System.Collections.ArrayList]@()
$userobj = $Request.body
# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
try {
    $license = $userobj.license
    $Aliases = ($userobj.AddedAliases).Split([Environment]::NewLine)
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
    $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users" -tenantid $Userobj.tenantid -type POST -body $BodyToship  -verbose
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "Created user $($userobj.displayname) with id $($GraphRequest.id) " -Sev "Info"
    $results.add("Created user.")
    $results.add("Username: $($UserprincipalName)")
    $results.add("Password: $password")
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "User creation API failed. $($_.Exception.Message)" -Sev "Error"
    $body = $results.add("Failed to create user. $($_.Exception.Message)" )
}

try {
    if ($license) {
        Write-Host ($userobj | ConvertTo-Json)
        $licenses = (($userobj | Select-Object "License_*").psobject.properties | Where-Object { $_.value -EQ $true }).name -replace "License_", ""
        Write-Host "Lics are: $licences"
        $LicenseBody = if ($licenses.count -ge 2) {
            $liclist = foreach ($license in $Licenses) { '{"disabledPlans": [],"skuId": "' + $license + '" },' }
            '{"addLicenses": [' + $LicList + '], "removeLicenses": [ ] }'
        }
        else {
            '{"addLicenses": [ {"disabledPlans": [],"skuId": "' + $licenses + '" }],"removeLicenses": [ ]}'
        }
        Write-Host $LicenseBody
        $LicRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($GraphRequest.id)/assignlicense" -tenantid $Userobj.tenantid -type POST -body $LicenseBody -verbose
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "Assigned user $($userobj.displayname) license $($licences)" -Sev "Info"
        $body = $results.add("Assigned licenses.")
    }

}

catch {
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "License assign API failed. $($_.Exception.Message)" -Sev "Error"
    $body = $results.add("We've failed to assign the license. $($_.Exception.Message)")
}

try {
    if ($Aliases) {
        foreach ($Alias in $Aliases) {
            Write-Host $Alias
            New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($GraphRequest.id)" -tenantid $Userobj.tenantid -type "patch" -body "{`"mail`": `"$Alias`"}" -verbose
        }
        New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($GraphRequest.id)" -tenantid $Userobj.tenantid -type "patch" -body "{`"mail`": `"$UserprincipalName`"}" -verbose
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "Added alias $($Alias) to $($userobj.displayname)" -Sev "Info"
        $body = $results.add("Added Aliases: $($Aliases -join ',')")
    }
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid) -message "Alias API failed. $($_.Exception.Message)" -Sev "Error"
    $body = $results.add("We've failed to create the Aliases: $($_.Exception.Message)")
}
if ($Request.body.CopyFrom -ne "") {
    $MemberIDs = "https://graph.microsoft.com/v1.0/directoryObjects/" + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($GraphRequest.id)" -tenantid $Userobj.tenantid).id 
    $addmemberbody = "{ `"members@odata.bind`": $(ConvertTo-Json @($MemberIDs)) }"
        (New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($Request.body.CopyFrom)/GetMemberGroups" -tenantid $Userobj.tenantid -type POST -body  '{"securityEnabledOnly": false}').value | ForEach-Object {
        try {
            $groupname = (New-GraphGetRequest -tenantid $Userobj.tenantid -asApp $true -uri "https://graph.microsoft.com/beta/groups/$($_)").displayName
            Write-Host "name: $groupname"
            $GroupResult = New-GraphPostRequest -AsApp $true -uri "https://graph.microsoft.com/beta/groups/$($_)" -tenantid $Userobj.tenantid -type patch -body $addmemberbody -Verbose
            Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Added $($UserprincipalName) to group $groupresult.displayName)" -Sev "Info"  -tenant $TenantFilter
            $body = $results.add("Added group: $($groupname)")
        }
        catch {
            $body = $results.add("We've failed to add the group $($groupname): $($_.Exception.Message)")
            Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid) -message "Alias API failed. $($_.Exception.Message)" -Sev "Error"
        }
    }

}
$body = @{"Results" = @($results) }
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
