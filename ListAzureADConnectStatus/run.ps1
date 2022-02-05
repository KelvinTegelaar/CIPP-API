using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$DataToReturn = $Request.Query.DataToReturn

if (($DataToReturn -eq 'AzureADConnectSettings') -or ([string]::IsNullOrEmpty($DataToReturn)) ) {
    $ADConnectStatusGraph = New-ClassicAPIGetRequest -Resource "74658136-14ec-4630-ad9b-26e160ff0fc6" -TenantID $TenantFilter -Uri "https://main.iam.ad.ext.azure.com/api/Directories/ADConnectStatus" -Method "GET"
    $PasswordSyncStatusGraph = New-ClassicAPIGetRequest -Resource "74658136-14ec-4630-ad9b-26e160ff0fc6" -TenantID $TenantFilter -Uri "https://main.iam.ad.ext.azure.com/api/Directories/GetPasswordSyncStatus" -Method "GET"
    $AzureADConnectSettings = [PSCustomObject]@{
        dirSyncEnabled                   = $ADConnectStatusGraph.dirSyncEnabled
        dirSyncConfigured                = $ADConnectStatusGraph.dirSyncConfigured
        passThroughAuthenticationEnabled = $ADConnectStatusGraph.passThroughAuthenticationEnabled
        seamlessSingleSignOnEnabled      = $ADConnectStatusGraph.seamlessSingleSignOnEnabled
        numberOfHoursFromLastSync        = $ADConnectStatusGraph.numberOfHoursFromLastSync
        passwordSyncStatus               = $PasswordSyncStatusGraph
    }
}

if (($DataToReturn -eq 'AzureADObjectsInError') -or ([string]::IsNullOrEmpty($DataToReturn)) ) {
    $selectlist = "id", "displayName", "onPremisesProvisioningErrors", "createdDateTime"
    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$select=$($selectlist -join ',')" -tenantid $TenantFilter | ForEach-Object {
        $_ | Add-Member -NotePropertyName ObjectType -NotePropertyValue "User"
        $_
    }
    
    $GraphRequest2 = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$select=$($selectlist -join ',')" -tenantid $TenantFilter | ForEach-Object {
        $_ | Add-Member -NotePropertyName ObjectType -NotePropertyValue "Group"
        $_
    }
    
    
    $GraphRequest3 = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/contacts?`$select=$($selectlist -join ',')" -tenantid $TenantFilter | ForEach-Object {
        $_ | Add-Member -NotePropertyName ObjectType -NotePropertyValue "Contact"
        $_
    }
    
    $ObjectsInError = $GraphRequest + $GraphRequest2 + $GraphRequest3
}

if ([string]::IsNullOrEmpty($DataToReturn)) {
    $FinalObject = [PSCustomObject]@{
        AzureADConnectSettings = $AzureADConnectSettings
        ObjectsInError         = $ObjectsInError
    }
}
if ($DataToReturn -eq 'AzureADConnectSettings') {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $AzureADConnectSettings
        })
}
elseif ($DataToReturn -eq 'AzureADObjectsInError') {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($ObjectsInError)
        })
}
else {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($FinalObject)
        })
}

