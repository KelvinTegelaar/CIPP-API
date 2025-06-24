using namespace System.Net
function Invoke-PublicWebhooks {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Public
    #>
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    Set-Location (Get-Item $PSScriptRoot).Parent.FullName
    $WebhookTable = Get-CIPPTable -TableName webhookTable
    $WebhookIncoming = Get-CIPPTable -TableName WebhookIncoming
    $Webhooks = Get-CIPPAzDataTableEntity @WebhookTable
    Write-Host 'Received request'
    $url = ($Headers.'x-ms-original-url').split('/API') | Select-Object -First 1
    $CIPPURL = [string]$url
    Write-Host $url
    if ($Webhooks.Resource -eq 'M365AuditLogs') {
        Write-Host "Found M365AuditLogs - This is an old entry, we'll deny so Microsoft stops sending it."
        $body = 'This webhook is not authorized, its an old entry.'
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    if ($Request.Query.ValidationToken) {
        Write-Host 'Validation token received - query ValidationToken'
        $body = $Request.Query.ValidationToken
        $StatusCode = [HttpStatusCode]::OK
    } elseif ($Request.Body.validationCode) {
        Write-Host 'Validation token received - body validationCode'
        $body = $Request.Body.validationCode
        $StatusCode = [HttpStatusCode]::OK
    } elseif ($Request.Query.validationCode) {
        Write-Host 'Validation token received - query validationCode'
        $body = $Request.Query.validationCode
        $StatusCode = [HttpStatusCode]::OK
    } elseif ($Request.Query.CIPPID -in $Webhooks.RowKey) {
        Write-Host 'Found matching CIPPID'
        $url = ($Headers.'x-ms-original-url').split('/API') | Select-Object -First 1
        $Webhookinfo = $Webhooks | Where-Object -Property RowKey -EQ $Request.Query.CIPPID

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
