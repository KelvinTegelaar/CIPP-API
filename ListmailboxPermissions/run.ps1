using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter

Write-Host "Tenant Filter: $TenantFilter"
try {
    $PermsRequest = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenantfilter)/Mailbox('$($Request.Query.UserID)')/MailboxPermission" -Tenantid $tenantfilter -scope ExchangeOnline 
    $GraphRequest = foreach ($Perm in $PermsRequest) {
        if ($Perm.User -ne 'NT AUTHORITY\SELF') {
            [pscustomobject]@{
                User         = $Perm.User
                AccessRights = $Perm.PermissionList.AccessRights -join ', '
            }
        }
    }
    $StatusCode = [HttpStatusCode]::OK
}
catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
    $StatusCode = [HttpStatusCode]::Forbidden
    $GraphRequest = $ErrorMessage
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    })


