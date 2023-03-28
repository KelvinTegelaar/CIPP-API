using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$Results = [System.Collections.ArrayList]@()
$userobj = $Request.body
# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
write-host [boolean]$userobj.SendInvite
try {
    $BodyToship = [pscustomobject] @{
        "InvitedUserDisplayName"                = $userobj.Displayname
        "InvitedUserEmailAddress"               = $($userobj.mail)
        "inviteRedirectUrl"                     = $($userobj.RedirectURL)
        "sendInvitationMessage"                 = [boolean]$userobj.SendInvite
    } 
    $bodyToShip = ConvertTo-Json -Depth 10 -InputObject $BodyToship -Compress
    $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/invitations" -tenantid $Userobj.tenantid -type POST -body $BodyToship -verbose
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "Invited Guest $($userobj.displayname) with id $($GraphRequest.id) " -Sev "Info"
    $results.add("Invited Guest.")
}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid)  -message "Guest Invite API failed. $($_.Exception.Message)" -Sev "Error"
    $body = $results.add("Failed to Invite Guest. $($_.Exception.Message)" )
}

$body = @{"Results" = @($results) }
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
