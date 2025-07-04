function Invoke-PublicPing {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Public
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $KeepAliveTable = Get-CippTable -tablename 'CippKeepAlive'
    $LastKeepAlive = Get-CippAzDataTableEntity @KeepAliveTable -Filter "PartitionKey eq 'Ping' and RowKey eq 'Ping'"

    if ($LastKeepAlive.Timestamp) {
        $LastKeepAlive = $LastKeepAlive.Timestamp.DateTime.ToUniversalTime()
    } else {
        $LastKeepAlive = (Get-Date).AddSeconds(-600).ToUniversalTime()
    }
    $KeepAliveInterval = -300
    $NextKeepAlive = (Get-Date).AddSeconds($KeepAliveInterval).ToUniversalTime()

    $IsColdStart = $Request.Headers.'x-ms-coldstart' -eq 1

    if ($LastKeepAlive -le $NextKeepAlive -or $IsColdStart) {
        $KeepAlive = @{
            PartitionKey = 'Ping'
            RowKey       = 'Ping'
        }
        Add-AzDataTableEntity @KeepAliveTable -Entity $KeepAlive -Force

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

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = ($Body | ConvertTo-Json -Depth 5)
    }
}
