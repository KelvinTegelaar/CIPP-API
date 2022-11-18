using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$contactobj = $Request.body
$user = $request.headers.'x-ms-client-principal'

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
try {

    $BodyToship = [pscustomobject] @{
        "displayName"          = $contactobj.Displayname
        "name"                 = $contactobj.displayName
        "ExternalEmailAddress" = $contactobj.Email
        FirstName              = $contactObj.firstname
        lastname               = $contactobj.lastname

    }
    $NewContact = New-ExoRequest -tenantid $Request.body.tenantid -cmdlet "New-MailContact" -cmdparams $BodyToship
    Write-Host ( $NewContact | ConvertTo-Json)
    New-ExoRequest -tenantid $Request.body.tenantid -cmdlet "Set-MailContact" -cmdparams @{identity = $NewContact.id; HiddenFromAddressListsEnabled = [boolean]$contactobj.hidefromGAL }
    $body = [pscustomobject]@{"Results" = "Successfully created shared mailbox." }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($contactobj.tenantid) -message "Created contact $($contactobj.displayname) with id $($GraphRequest.id) for " -Sev "Info"

}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($contactobj.tenantid) -message "contact creation API failed. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed to create contact. $($_.Exception.Message)" }

}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
