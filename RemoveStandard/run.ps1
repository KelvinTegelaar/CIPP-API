using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$user = $request.headers.'x-ms-client-principal'
$ID = $request.query.id
try {
    remove-item "$($ID).Standards.json" -force
    Log-Request -user $user -message "Removed standards for $ID." -Sev "Info"
    $body = [pscustomobject]@{"Results" = "Successfully removed standards deployment" }


}
catch {
    Log-Request -user $user -message "Failed to remove standard for $ID. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed to remove standard)" }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })

