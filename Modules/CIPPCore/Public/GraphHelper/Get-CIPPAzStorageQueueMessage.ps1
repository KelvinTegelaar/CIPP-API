function Get-CIPPAzStorageQueueMessage {
    <#
    .SYNOPSIS
        Peeks at messages in an Azure Storage Queue without removing them.
    .DESCRIPTION
        Uses New-CIPPAzStorageRequest to call the Queue service Peek Messages REST API.
        When NumberOfMessages is not specified, the approximate message count is read from
        queue metadata and used as the peek count (capped at the API maximum of 32).
        MessageText values are automatically base64-decoded.
    .PARAMETER Name
        The name of the queue to peek messages from.
    .PARAMETER NumberOfMessages
        Number of messages to peek (1-32). When omitted, the approximate message count
        from queue metadata is used, capped at 32.
    .PARAMETER ConnectionString
        Azure Storage connection string. Defaults to $env:AzureWebJobsStorage
    .PARAMETER NoAutoCount
        If set, skips the metadata call and peeks up to 32 messages regardless of queue depth.
    .EXAMPLE
        Get-CIPPAzStorageQueueMessage -Name 'myqueue'
        Peeks up to the approximate number of messages (capped at 32).
    .EXAMPLE
        Get-CIPPAzStorageQueueMessage -Name 'myqueue' -NumberOfMessages 10
        Peeks exactly 10 messages.
    .EXAMPLE
        Get-CIPPAzStorageQueueMessage -Name 'myqueue' -NoAutoCount
        Peeks up to 32 messages without a prior metadata call.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 32)]
        [int]$NumberOfMessages,

        [Parameter(Mandatory = $false)]
        [string]$ConnectionString = $env:AzureWebJobsStorage,

        [Parameter(Mandatory = $false)]
        [switch]$NoAutoCount
    )

    process {
        $count = 32

        if ($PSBoundParameters.ContainsKey('NumberOfMessages')) {
            $count = $NumberOfMessages
        } elseif (-not $NoAutoCount) {
            # Use approximate message count from metadata to avoid over-peeking
            try {
                $meta = New-CIPPAzStorageRequest -Service 'queue' -Component 'metadata' -Resource $Name -ConnectionString $ConnectionString -Method 'GET'
                if ($meta -and $null -ne $meta.ApproximateMessagesCount) {
                    if ([int]$meta.ApproximateMessagesCount -eq 0) {
                        Write-Verbose "Queue '$Name' reports 0 approximate messages."
                        return @()
                    }
                    $count = [Math]::Min([int]$meta.ApproximateMessagesCount, 32)
                    Write-Verbose "Using approximate message count: $count"
                }
            } catch {
                Write-Verbose "Could not retrieve queue metadata; defaulting to numofmessages=32. Error: $($_.Exception.Message)"
                $count = 32
            }
        }

        $response = New-CIPPAzStorageRequest -Service 'queue' -Resource "$Name/messages" -QueryParams @{
            peekonly      = 'true'
            numofmessages = $count
        } -ConnectionString $ConnectionString -Method 'GET'

        if (-not $response) { return @() }

        # New-CIPPAzStorageRequest parses //QueueMessage nodes into PSObjects.
        # If the queue was empty the response may be an XmlDocument or XmlNode (empty QueueMessagesList).
        if ($response -is [System.Xml.XmlDocument] -or $response -is [System.Xml.XmlNode]) {
            Write-Verbose "Queue '$Name' returned no messages."
            return @()
        }

        # Ensure array output even for a single message
        @($response)
    }
}
