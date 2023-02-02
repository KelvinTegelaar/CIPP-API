using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$tenantFilter = $Request.Query.TenantFilter
$User = $Request.query.user
$USERToGet = $Request.query.usertoGet
$URL = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getOneDriveUsageAccountDetail(period='D7')?`$format=application/json" -tenantid $tenantFilter | Where-Object -Property 'OwnerPrincipalName' -EQ $User).siteUrl
$OnMicrosoft = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains?$top=999' -tenantid $tenantFilter | Where-Object -Property isInitial -EQ $true).id.split('.') | Select-Object -First 1
$AdminUrl = "https://$($onmicrosoft)-admin.sharepoint.com"
Write-Host ($OnMicrosoft)
$XML = @"
<Request xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009" AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName=".NET Library">
  <Actions>
    <ObjectPath Id="249" ObjectPathId="248"/>
  </Actions>
  <ObjectPaths>
    <Method Id="248" ParentId="242" Name="SetSiteAdmin">
      <Parameters>
        <Parameter Type="String">$URL</Parameter>
        <Parameter Type="String">$USERToGet</Parameter>
        <Parameter Type="Boolean">true</Parameter>
      </Parameters>
    </Method>
    <Constructor Id="242" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}"/>
  </ObjectPaths>
</Request>
"@
New-GraphPostRequest -scope "$AdminURL/.default" -tenantid $tenantFilter -Uri "$AdminURL/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml'

Write-LogMessage  -API "Standards" -tenant $tenantFilter -message "Disabled Password Expiration" -sev Info
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })
