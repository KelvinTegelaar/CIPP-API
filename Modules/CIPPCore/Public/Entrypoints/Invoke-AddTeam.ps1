    using namespace System.Net

    Function Invoke-AddTeam {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

        $APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$userobj = $Request.body

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
 
$Owners = ($userobj.owner).Split([Environment]::NewLine) | Where-Object { $_ -ne $null -or $_ -ne "" }
try {
    
    $Owners = $Owners |  ForEach-Object {
        $OwnerID = "https://graph.microsoft.com/beta/users('" + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$_" -tenantid $Userobj.tenantid).id + "')"
        @{
            "@odata.type"     = "#microsoft.graph.aadUserConversationMember"
            "roles"           = @("owner")
            "user@odata.bind" = $OwnerID
        }
    }

    $TeamsSettings = [PSCustomObject]@{
        "template@odata.bind" = "https://graph.microsoft.com/v1.0/teamsTemplates('standard')"
        "visibility"          = $userobj.visibility
        "displayName"         = $userobj.displayname
        "description"         = $userobj.description
        "members"             = @($owners)

    } | ConvertTo-Json -Depth 10

    Write-Host $TeamsSettings
    New-GraphPostRequest -AsApp $true -uri "https://graph.microsoft.com/beta/teams" -tenantid $Userobj.tenantid -type POST -body $TeamsSettings -verbose
    Write-LogMessage -user $request.headers.'x-ms-client-principal'  -API $APINAME -tenant $($userobj.tenantid) -message "Added Team $($userobj.displayname)" -Sev "Info"
    $body = [pscustomobject]@{"Results" = "Success. Team has been added" }

}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid) -message "$($userobj.tenantid): Add Team failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed. Error message: $($_.Exception.Message)" }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })

    }
