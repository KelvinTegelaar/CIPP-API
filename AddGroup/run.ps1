using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$groupobj = $Request.body
$user = $request.headers.'x-ms-client-principal'

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
try {
    $email = "$($groupobj.username)@$($groupobj.domain)"
    $BodyToship = [pscustomobject] @{
        "displayName"      = $groupobj.Displayname
        "description"      = $groupobj.Description
        "mailNickname"     = $groupobj.username
        mailEnabled        = [bool]$false
        securityEnabled    = [bool]$true
        isAssignableToRole = [bool]($groupobj.isAssignableToRole)

    } | ConvertTo-Json
    $GraphRequest = New-GraphPostRequest -AsApp $true -uri "https://graph.microsoft.com/beta/groups" -tenantid $groupobj.tenantid -type POST -body $BodyToship   -verbose
    $body = [pscustomobject]@{"Results" = "Succesfully created group. $($_.Exception.Message)" }
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($groupobj.tenantid) -message "Created group $($groupobj.displayname) with id $($GraphRequest.id) for " -Sev "Info"

}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($groupobj.tenantid) -message "Group creation API failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed to create group. $($_.Exception.Message)" }

}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
