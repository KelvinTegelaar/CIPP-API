using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
$body = '{"userPreferredMethodForSecondaryAuthentication": "push"}'
$graphRequest = New-GraphPOSTRequest -body $body -type PATCH -uri 'https://graph.microsoft.com/beta/users/b4156a0c-91c5-4195-bb1b-41b96d0806a7/authentication/signInPreferences' -tenantid $TenantFilter

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($graphRequest)
        }) -clobber