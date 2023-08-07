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

    $Webhookinfo = $Webhooks | Where-Object -Property CIPPID -EQ $Request.CIPPID
    if ($Request.query.ValidationToken -or $Request.body.validationCode) {
        Write-Host "Validation token received"
        $body = $request.query.ValidationToken
    }

    if ($Request.body.ContentUri) {
        Write-Host "ContentUri received"
        if ($Request.body.ContentUri -notlike "https://manage.office.com/api/v1.0/*") { exit }
        $TenantFilter = (Get-Tenants | Where-Object -Property customerId -EQ $Request.body.TenantID).defaultDomainName
        $Data = New-GraphPostRequest -type GET -uri "$($request.body.contenturi)" -tenantid $TenantFilter -scope "https://manage.office.com/.default"
    }
    else {
        $TenantFilter = $Data.Tenant
        $Data = $Request.body
    }

    foreach ($Item in $Data) {
        Write-Host "Data to process found."

        if ($item.Operation -in ($Webhookinfo.Operations -split ',')) {
            Write-Host "Working on $($item.operation)."
            Invoke-CippWebhookProcessing -TenantFilter $TenantFilter -Data $Data -CIPPPURL $url -allowedlocations $Webhookinfo.AllowedLocations
        }
    }

    $body = "OK"
}
else {
    $body = "This webhook is not authorized."
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
