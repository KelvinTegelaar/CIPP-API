    using namespace System.Net

    Function Invoke-AddAPDevice {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

        $APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
$TenantFilter = (Get-Tenants | Where-Object { $_.defaultDomainName -eq $Request.body.TenantFilter }).customerId
$GroupName = if ($Request.body.Groupname) { $Request.body.Groupname } else { (New-Guid).GUID }
$rawDevices = $request.body.autopilotData
$Devices = ConvertTo-Json @($rawDevices)
Write-Host $Devices
$Result = try {
    $CurrentStatus = (New-GraphgetRequest -uri "https://api.partnercenter.microsoft.com/v1/customers/$tenantfilter/DeviceBatches" -scope 'https://api.partnercenter.microsoft.com/user_impersonation')
    if ($groupname -in $CurrentStatus.items.id) { throw "This device batch name already exists. Please try with another name." }
    $body = '{"batchId":"' + $($GroupName) + '","devices":' + $Devices + '}'
    $GraphRequest = (New-GraphPostRequest -uri "https://api.partnercenter.microsoft.com/v1/customers/$TenantFilter/DeviceBatches" -body $body -scope 'https://api.partnercenter.microsoft.com/user_impersonation')
    Write-Host ($GraphRequest | ConvertTo-Json)
    Start-Sleep 5
    $NewStatus = New-GraphgetRequest -uri "https://api.partnercenter.microsoft.com/v1/customers/$tenantfilter/DeviceBatches" -scope 'https://api.partnercenter.microsoft.com/user_impersonation'
    Write-Host $($Newstatus | ConvertTo-Json)
    if ($Newstatus.totalcount -eq $CurrentStatus.totalcount) { throw "We could not find the new autopilot device. Please check if your input is correct." }
    Write-Host $CurrentStatus.Items
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $($Request.body.TenantFilter) -message "Created Autopilot devices group. Group ID is $GroupName" -Sev "Info"
    "Created Autopilot devices group for $($Request.body.TenantFilter). Group ID is $GroupName"
}
catch {
    "$($Request.body.TenantFilter): Failed to create autopilot devices. $($_.Exception.Message)"
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $($Request.body.TenantFilter) -message "Failed to create autopilot devices. $($_.Exception.Message)" -Sev "Error"
}

$body = [pscustomobject]@{"Results" = $Result }
Write-Host $body
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body

    })

    }
