using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

Push-OutputBinding -Name QueueWebhook -Value $Request

if ($Request.query.ValidationToken -or $Request.body.validationCode) {
    Write-Host "Validation token received"
    $body = $request.query.ValidationToken
} else {
    $Body = 'Webhook Recieved'
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
