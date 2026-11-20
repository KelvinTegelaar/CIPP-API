function Invoke-PublicWebhooks {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Public
    #>
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers
    Write-Information 'Received request'
    $url = ($Headers.'x-ms-original-url').split('/API') | Select-Object -First 1
    $CIPPURL = [string]$url
    Write-Information $url

    # Graph (and Partner Center) validate a new subscription by POSTing a token and comparing the raw
    # response body to it byte for byte. The response has to be the bare token as text/plain - the
    # default application/json content type re-quotes the string, and Graph then rejects the
    # subscription with "did not return the expected validation token".
    $ContentType = 'application/json'
    if ($Request.Query.ValidationToken) {
        Write-Information 'Validation token received - query ValidationToken'
        $body = [string]$Request.Query.ValidationToken
        $ContentType = 'text/plain'
        $StatusCode = [HttpStatusCode]::OK
    } elseif ($Request.Body.validationCode) {
        Write-Information 'Validation token received - body validationCode'
        $body = [string]$Request.Body.validationCode
        $ContentType = 'text/plain'
        $StatusCode = [HttpStatusCode]::OK
    } elseif ($Request.Query.validationCode) {
        Write-Information 'Validation token received - query validationCode'
        $body = [string]$Request.Query.validationCode
        $ContentType = 'text/plain'
        $StatusCode = [HttpStatusCode]::OK
    } elseif ($Request.Query.CIPPID) {
        $CIPPID = ConvertTo-CIPPODataFilterValue -Value $Request.Query.CIPPID -Type Guid
        $WebhookTable = Get-CIPPTable -TableName webhookTable
        $Webhookinfo = Get-CIPPAzDataTableEntity @WebhookTable -Filter "RowKey eq '$CIPPID'" -First 1
        if (-not $Webhookinfo) {
            Write-Information "No matching CIPPID found: $($Request.Query.CIPPID)"
            $Body = 'This webhook is not authorized.'
            $StatusCode = [HttpStatusCode]::Forbidden
        } elseif ($Webhookinfo.Resource -eq 'M365AuditLogs') {
            Write-Information "Found M365AuditLogs - This is an old entry, we'll deny so Microsoft stops sending it."
            $Body = 'This webhook is not authorized, its an old entry.'
            $StatusCode = [HttpStatusCode]::Forbidden
        } else {
            Write-Information 'Found matching CIPPID'
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
                Write-LogMessage -headers $Headers -API ($Request.Params.CIPPEndpoint ?? 'PublicWebhooks') -tenant 'Global' -message "Graph subscription webhook received and queued (CIPPID=$($Request.Query.CIPPID))" -Sev 'Info'

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
                Write-LogMessage -headers $Headers -API ($Request.Params.CIPPEndpoint ?? 'PublicWebhooks') -tenant 'Global' -message "Partner Center webhook received and queued (CIPPID=$($Request.Query.CIPPID))" -Sev 'Info'
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
            StatusCode  = $StatusCode
            Body        = $Body
            ContentType = $ContentType
        })
}
