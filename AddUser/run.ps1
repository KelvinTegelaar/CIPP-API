using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$Results = [System.Collections.ArrayList]@()
$userobj = $Request.body
# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
try {
    $license = $userobj.license
    $Aliases = ($userobj.AddedAliases).Split([Environment]::NewLine)
    $password = if ($userobj.password) { $userobj.password } else { New-passwordString }
    $UserprincipalName = "$($UserObj.username)@$($UserObj.domain)"
    $BodyToship = [pscustomobject] @{
        "givenName"         = $userobj.firstname
        "surname"           = $userobj.lastname
        "accountEnabled"    = $true
        "displayName"       = $UserObj.Displayname
        "department"        = $userobj.department
        "mailNickname"      = $UserObj.username
        "userPrincipalName" = $UserprincipalName
        "usageLocation"     = $UserObj.usageLocation
        "city"              = $userobj.city
        "country"           = $userobj.country
        "jobtitle"          = $userObj.jobtitle
        "mobilePhone"       = $userobj.mobilePhone
        "streetAddress"     = $userobj.streetAddress
        "postalCode"        = $userobj.postalCode
        "companyName"       = $userobj.companyName
        "passwordProfile"   = @{
            "forceChangePasswordNextSignIn" = [bool]$UserObj.mustchangepass
            "password"                      = $password
        }
    } 
    if ($userobj.businessPhone) { $bodytoShip | Add-Member -NotePropertyName businessPhones -NotePropertyValue @($userobj.businessPhone) }
    $bodyToShip = ConvertTo-Json -Depth 10 -InputObject $BodyToship -Compress
    $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users" -tenantid $Userobj.tenantid -type POST -body $BodyToship  -verbose
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "Created user $($userobj.displayname) with id $($GraphRequest.id) " -Sev "Info"
    $results.add("Created user.")
    $results.add("Username: $($UserprincipalName)")
    $results.add("Password: $password")
}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "User creation API failed. $($_.Exception.Message)" -Sev "Error"
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
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "Assigned user $($userobj.displayname) license $($licences)" -Sev "Info"
        $body = $results.add("Assigned licenses.")
    }

}

catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "License assign API failed. $($_.Exception.Message)" -Sev "Error"
    $body = $results.add("We've failed to assign the license. $($_.Exception.Message)")
}

try {
    if ($Aliases) {
        foreach ($Alias in $Aliases) {
            Write-Host $Alias
            New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($GraphRequest.id)" -tenantid $Userobj.tenantid -type "patch" -body "{`"mail`": `"$Alias`"}" -verbose
        }
        New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($GraphRequest.id)" -tenantid $Userobj.tenantid -type "patch" -body "{`"mail`": `"$UserprincipalName`"}" -verbose
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "Added alias $($Alias) to $($userobj.displayname)" -Sev "Info"
        $body = $results.add("Added Aliases: $($Aliases -join ',')")
    }
}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid) -message "Alias API failed. $($_.Exception.Message)" -Sev "Error"
    $body = $results.add("We've failed to create the Aliases: $($_.Exception.Message)")
}
if ($Request.body.CopyFrom -ne "") {
    $CopyFrom = Set-CIPPCopyGroupMembers -ExecutingUser $request.headers.'x-ms-client-principal' -tenantid $Userobj.tenantid -CopyFromId $Request.body.CopyFrom -UserID $UserprincipalName -TenantFilter $Userobj.tenantid
    $results.AddRange($CopyFrom) 
}
$body = @{"Results" = @($results) }
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
