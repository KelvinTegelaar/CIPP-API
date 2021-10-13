using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$userobj = $Request.body
$user = $request.headers.'x-ms-client-principal'

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
 
$Owners = ($userobj.owner).Split([Environment]::NewLine) | where-object { $_ -ne $null -or $_ -ne "" }
try {
    
    $Owners = $Owners |  foreach-object {
        $OwnerID = "https://graph.microsoft.com/beta/users('" + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$_" -tenantid $Userobj.tenantid).id + "')"
        @{
            "@odata.type"     = "#microsoft.graph.aadUserConversationMember"
            "roles"           = @("owner")
            "user@odata.bind" = $OwnerID
        }
    }

    $TeamsSettings = [PSCustomObject]@{
        "template@odata.bind" = "https://graph.microsoft.com/v1.0/teamsTemplates('standard')"
        "visibility"          = "Public"
        "displayName"         = $userobj.displayname
        "description"         = $userobj.description
        "members"             = @($owners)

    } | convertto-json -Depth 10

    write-host $TeamsSettings
    New-GraphPostRequest -AsApp $true -uri "https://graph.microsoft.com/beta/teams" -tenantid $Userobj.tenantid -type POST -body $TeamsSettings -verbose
    Log-Request -user $user -message "$($userobj.tenantid): $($userobj.tenantid): Added Team $($userobj.displayname)" -Sev "Info"
    $body = [pscustomobject]@{"Results" = "Success. Team has been added" }

}
catch {
    Log-Request -user $user -message "$($userobj.tenantid): Add Team failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed. Error message: $($_.Exception.Message)" }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
