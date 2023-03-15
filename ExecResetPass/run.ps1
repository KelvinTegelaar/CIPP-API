using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
Write-Host "$($Request.query.ID)"
# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$password = New-passwordString
$mustChange = $request.query.MustChange
if (!$mustChange) { $mustChange = 'true' }

$passwordProfile = @"
{"passwordProfile": { "forceChangePasswordNextSignIn": $mustChange, "password": "$password" }}'
"@

try {
    if ($TenantFilter -eq $null -or $TenantFilter -eq "null") {
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$($Request.query.ID)" -type PATCH -body $passwordProfile  -verbose
    }
    else {
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$($Request.query.ID)" -tenantid $TenantFilter -type PATCH -body $passwordProfile  -verbose
    }
    $Results = [pscustomobject]@{"Results" = "Reset password for $($Request.query.ID). User must change password at next logon is set to $mustChange. Temporary password is $password" }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Reset password for $($REquest.query.id)" -Sev "Info"
}
catch {
    $Results = [pscustomobject]@{"Results" = "Failed to reset password for $($Request.query.id): $($_.Exception.Message)" }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Failed to reset password for $($Request.query.id): $($_.Exception.Message)" -Sev "Error"

}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })