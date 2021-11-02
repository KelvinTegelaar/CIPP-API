using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$Results = [System.Collections.ArrayList]@()


$userobj = $Request.body

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
 
$AddMembers = ($userobj.Addmember).Split([Environment]::NewLine)
try {
    if ($AddMembers) {
        $MemberIDs = $AddMembers | ForEach-Object { "https://graph.microsoft.com/v1.0/directoryObjects/" + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $Userobj.tenantid).id }
        $addmemberbody = "{ `"members@odata.bind`": $(ConvertTo-Json @($MemberIDs)) }"
        New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)" -tenantid $Userobj.tenantid -type patch -body $addmemberbody -verbose
        Log-Request -API $APINAME -tenant $Userobj.tenantid -user $request.headers.'x-ms-client-principal'  -message "Added member to $($userobj.displayname) group" -Sev "Info"
        $body = $results.add("Success. $AddMembers have been added")
    }

}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal'   -message "Add member API failed. $($_.Exception.Message)" -Sev "Error"
    $body = $results.add("Failed to add $AddMembers to $($userobj.Groupid) $($_.Exception.Message)")
}

$RemoveMembers = ($userobj.Removemember).Split([Environment]::NewLine)
try {
    if ($RemoveMembers) {
        $RemoveMembers | ForEach-Object { 
            $MemberInfo = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $Userobj.tenantid)
            New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)/members/$($MemberInfo.id)/`$ref" -tenantid $Userobj.tenantid -type DELETE 
            Log-Request -API $APINAME -tenant $Userobj.tenantid -user $request.headers.'x-ms-client-principal'  -message "Removed $($MemberInfo.UserPrincipalname) from $($userobj.displayname) group" -Sev "Info"
            $body = $results.add("Success. Member $_ has been removed from $($userobj.Groupid)")
        }  
    }
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $Userobj.tenantid -message "Add member API failed. $($_.Exception.Message)" -Sev "Error"
    $body = $results.add("Could not remove $RemoveMembers from $($userobj.Groupid). $($_.Exception.Message)")
}

$AddOwners = ($userobj.Addowner).Split([Environment]::NewLine)
try {
    if ($AddOwners) {
        $AddOwners | ForEach-Object { 
            $ID = "https://graph.microsoft.com/beta/users/" + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $Userobj.tenantid).id
            Write-Host $ID
            $AddOwner = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)/owners/`$ref" -tenantid $Userobj.tenantid -type POST -body ('{"@odata.id": "' + $ID + '"}')
            Log-Request -API $APINAME -tenant $Userobj.tenantid -user $request.headers.'x-ms-client-principal'  -message "Added owner $_ to $($userobj.displayname) group" -Sev "Info"
            $body = $results.add("Success. $_ has been added")
    
        }

    }

}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal'   -message "Add member API failed. $($_.Exception.Message)" -Sev "Error"
    $body = $results.add("Failed to add $AddMembers to $($userobj.Groupid) $($_.Exception.Message)")
}

$RemoveOwners = ($userobj.RemoveOwner).Split([Environment]::NewLine)
try {
    if ($RemoveOwners) {
        $RemoveOwners | ForEach-Object { 
            $MemberInfo = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $Userobj.tenantid)
            New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)/owners/$($MemberInfo.id)/`$ref" -tenantid $Userobj.tenantid -type DELETE 
            Log-Request -API $APINAME -tenant $Userobj.tenantid -user $request.headers.'x-ms-client-principal'  -message "Removed $($MemberInfo.UserPrincipalname) from $($userobj.displayname) group" -Sev "Info"
            $body = $results.add("Success. Member $_ has been removed from $($userobj.Groupid)")
        }  
    }
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $Userobj.tenantid -message "Add member API failed. $($_.Exception.Message)" -Sev "Error"
    $body = $results.add("Could not remove $RemoveMembers from $($userobj.Groupid). $($_.Exception.Message)")
}


$body = @{"Results" = ($results -join "<br>") }
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
