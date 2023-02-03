using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
if ($TenantFilter -eq 'AllTenants') {
    Push-OutputBinding -Name Msg -Value (Get-Date).ToString()
    [PSCustomObject]@{
        Tenant   = 'Report does not support all tenants'
        Licenses = 'Report does not support all tenants'
    }
}

#Data Fetching
$StaleDate = (get-date).AddDays(-30)
$StaleUsers = 
 try{
    New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=accountEnabled eq true and assignedLicenses/`$count ne 0&`$count=true &`$select=displayName,userPrincipalName,signInActivity" -tenantid $TenantFilter -ComplexFilter
 }catch{
    New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=accountEnabled eq true and assignedLicenses/`$count ne 0&`$count=true &`$select=displayName,userPrincipalName" -tenantid $TenantFilter -ComplexFilter
 }
$OutlookActivity = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getEmailActivityUserDetail(period='D30')" -tenantid $TenantFilter | convertfrom-csv
$OnedriveActivity = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getOneDriveActivityUserDetail(period='D30')" -tenantid $TenantFilter | convertfrom-csv
$SharepointActivity = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getSharepointActivityUserDetail(period='D30')" -tenantid $TenantFilter | convertfrom-csv
$TeamsActivity = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getTeamsUserActivityUserDetail(period='D30')" -tenantid $TenantFilter | convertfrom-csv

#Stale Licensed Users List
$AllStaleUsers = @()
foreach ($StaleUser in $StaleUsers) {
    $TeamsMessages = $TeamsActivity | Where-Object 'User Principal Name' -eq $StaleUser.userPrincipalName | Select-Object -ExpandProperty 'Team Chat Message Count'
    $PrivateMessages = $TeamsActivity | Where-Object 'User Principal Name' -eq $StaleUser.userPrincipalName | Select-Object -ExpandProperty 'Private Chat Message Count'
    $StaleUserObject = 
    [PSCustomObject]@{
        DisplayName    = $StaleUser.displayName
        UPN            = $StaleUser.userPrincipalName
        lastSignInDate = $StaleUser.signInActivity.lastSignInDateTime
        OutlookActivity = $OutlookActivity | Where-Object 'User Principal Name' -eq $StaleUser.userPrincipalName | Select-Object -ExpandProperty 'Last Activity Date'
        EmailsSent = $OutlookActivity | Where-Object 'User Principal Name' -eq $StaleUser.userPrincipalName | Select-Object -ExpandProperty 'Send Count'
        OnedriveActivity = $OnedriveActivity | Where-Object 'User Principal Name' -eq $StaleUser.userPrincipalName | Select-Object -ExpandProperty 'Last Activity Date'
        ODViewedFileCount = $OnedriveActivity | Where-Object 'User Principal Name' -eq $StaleUser.userPrincipalName | Select-Object -ExpandProperty 'Viewed or Edited File Count'
        SharepointActivity = $SharepointActivity | Where-Object 'User Principal Name' -eq $StaleUser.userPrincipalName | Select-Object -ExpandProperty 'Last Activity Date'
        SPViewedFileCount = $SharepointActivity | Where-Object 'User Principal Name' -eq $StaleUser.userPrincipalName | Select-Object -ExpandProperty 'Viewed or Edited File Count'
        TeamsActivity = $TeamsActivity | Where-Object 'User Principal Name' -eq $StaleUser.userPrincipalName | Select-Object -ExpandProperty 'Last Activity Date'
        MessageCount = [int]$TeamsMessages + [int]$PrivateMessages 
    }
    if ($null -ne $StaleUserObject.lastSignInDate) {
        if ((get-date $StaleUserObject.lastSignInDate) -le $StaleDate) { $AllStaleUsers += $StaleUserObject }
    }
    else { $AllStaleUsers += $StaleUserObject }
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($AllStaleUsers)
    }) -Clobber