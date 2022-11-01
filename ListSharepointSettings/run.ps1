using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
Set-Location (Get-Item $PSScriptRoot).Parent.FullName

$Translator = Get-Content '.\Cache_SAMSetup\PermissionsTranslator.json' | ConvertFrom-Json
$ExpectedPermissions = Get-Content '.\Cache_SAMSetup\SAMManifest.json' | ConvertFrom-Json
$RequiredCPVPerms = $ExpectedPermissions.requiredResourceAccess | ForEach-Object {
    $Resource = $_
    $Scope = ($Translator | Where-Object { $_.id -in $Resource.ResourceAccess.id } | Where-Object { $_.value -notin 'profile', 'openid', 'offline_access' }).value -join ','
    if ($Scope) {
        [PSCustomObject]@{
            EnterpriseApplicationId = $_.ResourceAppId
            Scope                   = $Scope
        }
    }
}
$DeleteOldPermissions = New-GraphpostRequest -Type DELETE -noauthcheck $true -uri "https://api.partnercenter.microsoft.com/v1/customers/$($TenantFilter)/applicationconsents/$($env:ApplicationID)" -scope "https://api.partnercenter.microsoft.com/.default" -tenantid $env:TenantID
$AppBody = @"
{
  "ApplicationGrants": $(ConvertTo-Json -InputObject $RequiredCPVPerms -Compress -Depth 10),
  "ApplicationId": "$($env:ApplicationID)",
  "DisplayName": "CIPP-SAM"
}
"@
$CPVConsent = New-GraphpostRequest -body $AppBody -Type POST -noauthcheck $true -uri "https://api.partnercenter.microsoft.com/v1/customers/$($TenantFilter)/applicationconsents" -scope "https://api.partnercenter.microsoft.com/.default" -tenantid $env:TenantID
$StatusCode = [HttpStatusCode]::OK

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    })
