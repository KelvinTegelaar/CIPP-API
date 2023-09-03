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
try {
    $DeleteOldPermissions = New-GraphpostRequest -Type DELETE -noauthcheck $true -uri "https://api.partnercenter.microsoft.com/v1/customers/$($TenantFilter)/applicationconsents/$($env:ApplicationID)" -scope "https://api.partnercenter.microsoft.com/.default" -tenantid $env:TenantID

}
catch {
    "no old permissions to delete, moving on"
}

$GraphRequest = $ExpectedPermissions.requiredResourceAccess | ForEach-Object { 
    try {
        $Resource = $_
        $Permissionsname = switch ($Resource.ResourceAppId) {
            '00000002-0000-0ff1-ce00-000000000000' { 'Office 365 Exchange Online' }
            '00000003-0000-0000-c000-000000000000' { "Graph API" }
            'fc780465-2017-40d4-a0c5-307022471b92' { 'WindowsDefenderATP' }
            '00000003-0000-0ff1-ce00-000000000000' { 'Sharepoint' }
            '48ac35b8-9aa8-4d74-927d-1f4a14a0b239' { 'Skype and Teams Tenant Admin API' }
            'c5393580-f805-4401-95e8-94b7a6ef2fc2' { 'Office 365 Management API' }

        }
        $Scope = ($Translator | Where-Object { $_.id -in $Resource.ResourceAccess.id } | Where-Object { $_.value -notin 'profile', 'openid', 'offline_access' }).value -join ', '
        if ($Scope) {
            $RequiredCPVPerms = [PSCustomObject]@{
                EnterpriseApplicationId = $_.ResourceAppId
                Scope                   = "$Scope"
            }
            $AppBody = @"
{
  "ApplicationGrants":[ $(ConvertTo-Json -InputObject $RequiredCPVPerms -Compress -Depth 10)],
  "ApplicationId": "$($env:ApplicationID)"}
"@
            $CPVConsent = New-GraphpostRequest -body $AppBody -Type POST -noauthcheck $true -uri "https://api.partnercenter.microsoft.com/v1/customers/$($TenantFilter)/applicationconsents" -scope "https://api.partnercenter.microsoft.com/.default" -tenantid $env:TenantID
            "Succesfully set CPV permissions for $Permissionsname"

        } 
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Could not set CPV permissions for $PermissionsName. Does the Tenant have a license for this API. error: $($_.Exception.message)" -Sev "Error"
        "Could not set CPV permissions for $PermissionsName. Does the Tenant have a license for this API? Error: $($_.Exception.message)"
    }
}

try {
    $ourSVCPrincipal = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals(appId='$($ENV:applicationid)')" -tenantid $Tenantfilter
    $CurrentRoles = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals/$($ourSVCPrincipal.id)/appRoleAssignments" -tenantid $tenantfilter

}
catch {
    #this try catch exists because of 500 errors when the app principal does not exist. :)
}
# if the app svc principal exists, consent app permissions
$apps = $ExpectedPermissions 
#get current roles
#If 
$Grants = foreach ($App in $apps.requiredResourceAccess) {
    try {
        $svcPrincipalId = New-GraphGETRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$($app.resourceAppId)')" -tenantid $tenantfilter
    }
    catch {
        continue
    }
    foreach ($SingleResource in $app.ResourceAccess | Where-Object -Property Type -EQ "Role") {
        if ($singleresource.id -In $currentroles.appRoleId) { continue }
        [pscustomobject]@{
            principalId = $($ourSVCPrincipal.id)
            resourceId  = $($svcPrincipalId.id)
            appRoleId   = "$($SingleResource.Id)"
        }
    } 
} 
foreach ($Grant in $grants) {
    try {
        $SettingsRequest = New-GraphPOSTRequest -body ($grant | ConvertTo-Json) -uri "https://graph.microsoft.com/beta/servicePrincipals/$($ourSVCPrincipal.id)/appRoleAssignedTo" -tenantid $tenantfilter -type POST
    }
    catch {
        "Failed to grant $($grant.appRoleId) to $($grant.resourceId): $($_.Exception.Message). "
    }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{Results = $GraphRequest }
    })
