using namespace System.Net

# Input bindings are passed in via param block.
param($QueueItem, $TriggerMetadata)

$Request = $QueueItem

$WebhookTable = Get-CIPPTable -TableName webhookTable
$Webhooks = Get-AzDataTableEntity @WebhookTable
Write-Host 'Received request'
Write-Host "CIPPID: $($request.Query.CIPPID)"
$url = ($request.headers.'x-ms-original-url').split('/API') | Select-Object -First 1
Write-Host $url
if ($Request.query.CIPPID -in $Webhooks.RowKey) {
    Write-Host 'Found matching CIPPID'
    $Webhookinfo = $Webhooks | Where-Object -Property RowKey -EQ $Request.query.CIPPID

    if ($Request.Query.Type -eq 'GraphSubscription') {
        # Graph Subscriptions
        [pscustomobject]$ReceivedItem = $Request.Body.value
        Invoke-CippGraphWebhookProcessing -Data $ReceivedItem -CIPPID $request.Query.CIPPID -WebhookInfo $Webhookinfo

    } else {
        # Auditlog Subscriptions
        $Webhookinfo = $Webhooks | Where-Object -Property RowKey -EQ $Request.query.CIPPID
        foreach ($ReceivedItem In ($Request.body)) {
            $ReceivedItem = [pscustomobject]$ReceivedItem
            $TenantFilter = (Get-Tenants | Where-Object -Property customerId -EQ $ReceivedItem.TenantId).defaultDomainName
            Write-Host "TenantFilter: $TenantFilter"
            $Data = New-GraphPostRequest -type GET -uri "https://manage.office.com/api/v1.0/$($ReceivedItem.tenantId)/activity/feed/audit/$($ReceivedItem.contentid)" -tenantid $TenantFilter -scope 'https://manage.office.com/.default'
            Write-Host "Data to process found: $(($ReceivedItem.operation).count) items"
            Write-Host "Operations to process for this client: $($Webhookinfo.Operations)"
            foreach ($Item in $Data) {
                Write-Host "Processing $($item.operation)"
                Invoke-CippWebhookProcessing -TenantFilter $TenantFilter -Data $Item -CIPPPURL $url
            }
        }
    }

} else {
    Write-Host 'Unauthorised Webhook'
}
