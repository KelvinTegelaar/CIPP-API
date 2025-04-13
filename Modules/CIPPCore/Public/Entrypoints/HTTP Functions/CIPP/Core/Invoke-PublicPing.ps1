function Invoke-PublicPing {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Public
    #>
    [CmdletBinding()]
    Param(
        $Request,
        $TriggerMetadata
    )

    $KeepaliveTable = Get-CippTable -tablename 'CippKeepAlive'
    $LastKeepalive = Get-CippAzDataTableEntity @KeepaliveTable -Filter "PartitionKey eq 'Ping' and RowKey eq 'Ping'"

    if ($LastKeepalive.Timestamp) {
        $LastKeepalive = $LastKeepalive.Timestamp.DateTime.ToUniversalTime()
    } else {
        $LastKeepalive = (Get-Date).AddSeconds(-600).ToUniversalTime()
    }
    $KeepaliveInterval = -300
    $NextKeepAlive = (Get-Date).AddSeconds($KeepaliveInterval).ToUniversalTime()

    $IsColdStart = $Request.Headers.'x-ms-coldstart' -eq 1

    if ($LastKeepalive -le $NextKeepAlive -or $IsColdStart) {
        $Keepalive = @{
            PartitionKey = 'Ping'
            RowKey       = 'Ping'
        }
        Add-AzDataTableEntity @KeepaliveTable -Entity $Keepalive -Force

        if ($IsColdStart) {
            $Milliseconds = 500
        } else {
            $Milliseconds = 150
        }

        Start-Sleep -Milliseconds $Milliseconds
    }

    $Body = @{
        Results = @{
            Message   = 'Pong'
            ColdStart = $IsColdStart
            Timestamp = (Get-Date).ToUniversalTime()
            RequestId = $TriggerMetadata.InvocationId
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ($Body | ConvertTo-Json -Depth 5)
        })
}
