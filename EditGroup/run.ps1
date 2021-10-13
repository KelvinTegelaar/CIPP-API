using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$userobj = $Request.body
$user = $request.headers.'x-ms-client-principal'

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
 
$AddMembers = ($userobj.Addmember).Split([Environment]::NewLine)
try {
    if ($AddMembers) {
        $MemberIDs = $AddMembers | foreach-object { "https://graph.microsoft.com/v1.0/directoryObjects/" + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $Userobj.tenantid).id }
        $addmemberbody = "{ `"members@odata.bind`": $(ConvertTo-Json @($MemberIDs)) }"
        New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)" -tenantid $Userobj.tenantid -type patch -body $addmemberbody -verbose
        Log-Request -user $user -message "Added member to $($userobj.displayname) group" -Sev "Info"
        $body = [pscustomobject]@{"Results" = "Success. Member has been added" }
    }

}
catch {
    Log-Request -user $user -message "Add member API failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Succesfully added the users $AddMembers to $($userobj.Groupid) $($_.Exception.Message)" }
}

$RemoveMembers = ($userobj.Removemember).Split([Environment]::NewLine)
try {
    if ($RemoveMembers) {
        $RemoveMembers | foreach-object { 
            $MemberInfo = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $Userobj.tenantid)
            New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($userobj.groupid)/members/$($MemberInfo.id)/`$ref" -tenantid $Userobj.tenantid -type DELETE 
            Log-Request -user $user -message "Removed $($MemberInfo.UserPrincipalname) from $($userobj.displayname) group" -Sev "Info"
           
        }
        
        $body = [pscustomobject]@{"Results" = "Success. Member has been removed" }
    }

}
catch {
    Log-Request -user $user -message "Add member API failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Succesfully added the users $AddMembers to $($userobj.Groupid) $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
