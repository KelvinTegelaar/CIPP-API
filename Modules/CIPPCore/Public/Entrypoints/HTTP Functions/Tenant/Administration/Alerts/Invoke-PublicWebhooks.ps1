using namespace System.Net
function Invoke-PublicWebhooks {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Public
    #>
    param($Request, $TriggerMetadata)

    Set-Location (Get-Item $PSScriptRoot).Parent.FullName
    $WebhookTable = Get-CIPPTable -TableName webhookTable
    $WebhookIncoming = Get-CIPPTable -TableName WebhookIncoming
    $Webhooks = Get-CIPPAzDataTableEntity @WebhookTable
    Write-Host 'Received request'
    $url = ($request.headers.'x-ms-original-url').split('/API') | Select-Object -First 1
    $CIPPURL = [string]$url
    Write-Host $url
    if ($Webhooks.Resource -eq 'M365AuditLogs') {
        Write-Host "Found M365AuditLogs - This is an old entry, we'll deny so Microsoft stops sending it."
        $body = 'This webhook is not authorized, its an old entry.'
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    if ($Request.query.ValidationToken) {
        Write-Host 'Validation token received - query ValidationToken'
        $body = $request.query.ValidationToken
        $StatusCode = [HttpStatusCode]::OK
    } elseif ($Request.body.validationCode) {
        Write-Host 'Validation token received - body validationCode'
        $body = $request.body.validationCode
        $StatusCode = [HttpStatusCode]::OK
    } elseif ($Request.query.validationCode) {
        Write-Host 'Validation token received - query validationCode'
        $body = $request.query.validationCode
        $StatusCode = [HttpStatusCode]::OK
    } elseif ($Request.Query.CIPPID -in $Webhooks.RowKey) {
        Write-Host 'Found matching CIPPID'
        $url = ($request.headers.'x-ms-original-url').split('/API') | Select-Object -First 1
        $Webhookinfo = $Webhooks | Where-Object -Property RowKey -EQ $Request.query.CIPPID

        if ($Request.Query.Type -eq 'GraphSubscription') {
            # Graph Subscriptions
            [pscustomobject]$ReceivedItem = $Request.Body.value
            $Entity = [PSCustomObject]@{
                PartitionKey = 'Webhook'
                RowKey       = [string](New-Guid).Guid
                Type         = $Request.Query.Type
                Data         = [string]($ReceivedItem | ConvertTo-Json -Depth 10)
                CIPPID       = $Request.Query.CIPPID
                WebhookInfo  = [string]($WebhookInfo | ConvertTo-Json -Depth 10)
                FunctionName = 'PublicWebhookProcess'
            }
            Add-CIPPAzDataTableEntity @WebhookIncoming -Entity $Entity
            ## Push webhook data to queue
            #Invoke-CippGraphWebhookProcessing -Data $ReceivedItem -CIPPID $request.Query.CIPPID -WebhookInfo $Webhookinfo

        } elseif ($Request.Query.Type -eq 'PartnerCenter') {
            [pscustomobject]$ReceivedItem = $Request.Body
            $Entity = [PSCustomObject]@{
                PartitionKey = 'Webhook'
                RowKey       = [string](New-Guid).Guid
                Type         = $Request.Query.Type
                Data         = [string]($ReceivedItem | ConvertTo-Json -Depth 10)
                CIPPID       = $Request.Query.CIPPID
                WebhookInfo  = [string]($WebhookInfo | ConvertTo-Json -Depth 10)
                FunctionName = 'PublicWebhookProcess'
            }
            Add-CIPPAzDataTableEntity @WebhookIncoming -Entity $Entity
        } else {
            $Body = 'This webhook is not authorized.'
            $StatusCode = [HttpStatusCode]::Forbidden
        }
        $Body = 'Webhook Recieved'
        $StatusCode = [HttpStatusCode]::OK

    } else {
        $Body = 'This webhook is not authorized.'
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
