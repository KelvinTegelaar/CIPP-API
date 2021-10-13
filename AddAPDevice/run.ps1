using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
$TenantFilter = (get-content Tenants.cache.json | convertfrom-json | where-object { $_.defaultdomainname -eq $Request.body.TenantFilter }).customerid
$GroupName = if ($Request.body.Groupname) { $Request.body.Groupname } else { new-guid }
$rawDevices = ($Request.body.Devices | convertfrom-csv -header "SerialNumber", "oemManufacturerName", "modelName", "productKey", "hardwareHash" -delimiter ",")
$Devices = convertto-json @($rawDevices)

$Result = try {
    $CurrentStatus = (New-GraphgetRequest -uri "https://api.partnercenter.microsoft.com/v1/customers/$tenantfilter/DeviceBatches" -scope 'https://api.partnercenter.microsoft.com/user_impersonation')
    if ($groupname -in $CurrentStatus.items.id) { throw "This device batch name already exists. Please try with another name." }
    $body = '{"batchId":"' + $($GroupName) + '","devices":' + $Devices + '}'
    $GraphRequest = (New-GraphPostRequest -uri "https://api.partnercenter.microsoft.com/v1/customers/$TenantFilter/DeviceBatches" -body $body -scope 'https://api.partnercenter.microsoft.com/user_impersonation')
    start-sleep 3
    $NewStatus = New-GraphgetRequest -uri "https://api.partnercenter.microsoft.com/v1/customers/$tenantfilter/DeviceBatches" -scope 'https://api.partnercenter.microsoft.com/user_impersonation'
    if ($Newstatus.totalcount -eq $CurrentStatus.totalcount) { throw "We could not find the new autopilot device. Please check if your input is correct." }
    write-host $CurrentStatus.Items
    Log-Request -user $user -message "Created Autopilot devices group for $($Request.body.TenantFilter). Group ID is $GroupName" -Sev "Info"
    "Created Autopilot devices group for $($Request.body.TenantFilter). Group ID is $GroupName"
}
catch {
    "$($Request.body.TenantFilter): Failed to create autopilot devices. $($_.Exception.Message)"
    Log-Request -user $user -message "$($Request.body.TenantFilter): Failed to create autopilot devices. $($_.Exception.Message)" -Sev "Error"
}

$body = [pscustomobject]@{"Results" = $Result }
write-host $body
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body

    })