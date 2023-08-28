using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$WebhookTable = Get-CIPPTable -TableName webhookTable
$Webhooks = Get-AzDataTableEntity @WebhookTable
Write-Host "Received request"
Write-Host "CIPPID: $($request.Query.CIPPID)"
$url = ($request.headers.'x-ms-original-url').split('/API') | Select-Object -First 1
Write-Host $url
if ($Request.CIPPID -in $Webhooks.CIPPID) {
    Write-Host "Found matching CIPPID"

    $Webhookinfo = $Webhooks | Where-Object -Property RowKey -EQ $Request.query.CIPPID
    $operations = $Webhookinfo.Operations -split ','
    if ($Request.query.ValidationToken -or $Request.body.validationCode) {
        Write-Host "Validation token received"
        $body = $request.query.ValidationToken
    }

    foreach ($ReceivedItem In ($Request.body)) {
        $ReceivedItem = [pscustomobject]$ReceivedItem
        $TenantFilter = (Get-Tenants | Where-Object -Property customerId -EQ $ReceivedItem.TenantId).defaultDomainName
        Write-Host "TenantFilter: $TenantFilter"
        $Data = New-GraphPostRequest -type GET -uri "https://manage.office.com/api/v1.0/$($ReceivedItem.tenantId)/activity/feed/audit/$($ReceivedItem.contentid)" -tenantid $TenantFilter -scope "https://manage.office.com/.default"
        Write-Host "Data to process found: $(($ReceivedItem.operation).count) items"
        Write-Host "Operations to process for this client: $($Webhookinfo.Operations)"
        foreach ($Item in $Data) {
            Write-Host "Processing $($item.operation)"
            if ($item.operation -in $operations) {
                Invoke-CippWebhookProcessing -TenantFilter $TenantFilter -Data $Item -CIPPPURL $url -allowedlocations $Webhookinfo.AllowedLocations -Operations $operations
            } 
            if ($item.operation -eq "UserLoggedIn" -and "UserLoggedInFromUnknownLocation" -in $operations) {
                Invoke-CippWebhookProcessing -TenantFilter $TenantFilter -Data $Item -CIPPPURL $url -allowedlocations $Webhookinfo.AllowedLocations -Operations $operations
            }
            if ($item.operation -eq "UserLoggedIn" -and "AdminLoggedIn" -in $operations) {
                Invoke-CippWebhookProcessing -TenantFilter $TenantFilter -Data $Item -CIPPPURL $url -allowedlocations $Webhookinfo.AllowedLocations -Operations $operations
            }
            $body = "OK"
        }
    }

}
else {
    $body = "This webhook is not authorized."
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
