function Invoke-PublicWebhooks {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Public
    #>
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers
    Write-Host 'Received request'
    $url = ($Headers.'x-ms-original-url').split('/API') | Select-Object -First 1
    $CIPPURL = [string]$url
    Write-Host $url

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
    } elseif ($Request.Query.CIPPID) {
        $WebhookTable = Get-CIPPTable -TableName webhookTable
        $Webhookinfo = Get-CIPPAzDataTableEntity @WebhookTable -Filter "RowKey eq '$($Request.Query.CIPPID)'" -First 1
        if (-not $Webhookinfo) {
            Write-Host "No matching CIPPID found: $($Request.Query.CIPPID)"
            $Body = 'This webhook is not authorized.'
            $StatusCode = [HttpStatusCode]::Forbidden
        } elseif ($Webhookinfo.Resource -eq 'M365AuditLogs') {
            Write-Host "Found M365AuditLogs - This is an old entry, we'll deny so Microsoft stops sending it."
            $Body = 'This webhook is not authorized, its an old entry.'
            $StatusCode = [HttpStatusCode]::Forbidden
        } else {
            Write-Host 'Found matching CIPPID'
            $WebhookIncoming = Get-CIPPTable -TableName WebhookIncoming

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
            $Body = 'Webhook Received'
            $StatusCode = [HttpStatusCode]::OK
        }

    } else {
        $Body = 'This webhook is not authorized.'
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
