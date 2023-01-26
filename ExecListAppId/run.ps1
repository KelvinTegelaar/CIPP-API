using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$ResponseURL = "$(($Request.headers.'x-ms-original-url').replace('/api/ExecListAppId','/api/ExecSamSetup'))"

$Results = @{
      applicationId      = $ENV:ApplicationID 
      tenantId           = $ENV:TenantID
      refreshUrl         = "https://login.microsoftonline.com/$ENV:TenantID/oauth2/v2.0/authorize?client_id=$ENV:ApplicationID&response_type=code&redirect_uri=$ResponseURL&response_mode=query&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default+offline_access+profile+openid&state=1&prompt=select_account"
      exchangeRefreshUrl = "https://login.microsoftonline.com/$ENV:TenantId/oauth2/v2.0/authorize?client_id=a0c73c16-a7e3-4564-9a95-2bdf47383716&response_type=code&redirect_uri=https://login.microsoftonline.com/common/oauth2/nativeclient&response_mode=form_post&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default+offline_access+profile+openid&state=1&prompt=select_account"
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
      })