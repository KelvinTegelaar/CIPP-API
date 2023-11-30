using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)


$WebhookTable = Get-CIPPTable -TableName webhookTable
$Webhooks = Get-CIPPAzDataTableEntity @WebhookTable
Write-Host "Received request"
Write-Host "CIPPID: $($request.Query.CIPPID)"
$url = ($request.headers.'x-ms-original-url').split('/API') | Select-Object -First 1
Write-Host $url
if ($Request.CIPPID -in $Webhooks.CIPPID) {
    Write-Host "Found matching CIPPID"

    if ($Request.query.ValidationToken -or $Request.body.validationCode) {
        Write-Host "Validation token received"
        $body = $request.query.ValidationToken
    } else {
        Push-OutputBinding -Name QueueWebhook -Value $Request
        $Body = 'Webhook Recieved'
    }
} else {
    $body = "This webhook is not authorized."
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
