using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$WebhookTable = Get-CIPPTable -TableName webhookTable
$Webhooks = Get-AzDataTableEntity @WebhookTable
Write-Host "Received request"
Write-Host "CIPPID: $($request.Query.CIPPID)"
$url = ($request.headers.'x-ms-original-url').split('/api') | Select-Object -First 1
  
if ($Request.CIPPID -in $Webhooks.CIPPID) {
    Write-Host "Found matching CIPPID"

    $Webhookinfo = $Webhooks | Where-Object -Property RowKey -EQ $Request.query.CIPPID
    Write-Host "Webhookinfo: $($Webhookinfo | ConvertTo-Json -Depth 10)"
    if ($Request.query.ValidationToken -or $Request.body.validationCode) {
        Write-Host "Validation token received"
        $body = $request.query.ValidationToken
    }

    if ($Request.body.ContentUri) {
        Write-Host "ContentUri received"
        if ($Request.body.ContentUri -notlike "https://manage.office.com/api/v1.0/*") { exit }
        $TenantFilter = (Get-Tenants | Where-Object -Property customerId -EQ $Request.body.TenantId).defaultDomainName
        Write-Host "TenantFilter: $TenantFilter"
        $Data = New-GraphPostRequest -type GET -uri "$($request.body.contenturi)" -tenantid $TenantFilter -scope "https://manage.office.com/.default"
    }
    else {
        $TenantFilter = $Data.Tenant
        $Data = $Request.body
    }

    Write-Host "Data to process found: $(($data.operation).count) items"
    $operations = $Webhookinfo.Operations -split ','
    Write-Host "Operations to process for this client: $($Webhookinfo.Operations)"
    foreach ($Item in $Data) {
        Write-Host "Processing $($item.operation)"
        if ($item.Operation -in $operations) {
            Write-Host "Working on $($item.operation)."
            Invoke-CippWebhookProcessing -TenantFilter $TenantFilter -Data $Data -CIPPPURL $url -allowedlocations $Webhookinfo.AllowedLocations
        }
        $body = "OK"
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
