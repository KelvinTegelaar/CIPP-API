function Invoke-ListBECPhishingSpread {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .SYNOPSIS
        Lists who else received mail from a sender, from message-trace metadata.
    .DESCRIPTION
        Given a sender address (and optionally a subject fragment), walks the message trace for the last N days and groups the recipients: address, internal or external, message count, first and last delivery and the subjects seen. Use it to find the spread of a phishing message from a compromised or look-alike sender. Metadata only - no message content is read.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    # the sender to trace
    $SenderAddress = [string]$Request.Query.sender
    # optional subject fragment to narrow the trace (case-insensitive contains)
    $Subject = [string]$Request.Query.subject

    try {
        if (-not $SenderAddress) { throw 'sender is required' }
        # look-back in days (1-90)
        $Days = [Math]::Min([Math]::Max([int]($Request.Query.days ?? 7), 1), 90)
        $End = (Get-Date).ToUniversalTime()
        $Start = $End.AddDays(-$Days)
        $Accepted = try { @((New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AcceptedDomain').DomainName | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() }) } catch { @() }

        # Trace V2 takes at most 10 days per query; walk the range in 10-day windows, newest first.
        $Rows = [System.Collections.Generic.List[object]]::new()
        $Complete = $true
        $WindowEnd = $End
        while ($WindowEnd -gt $Start) {
            $WindowStart = $WindowEnd.AddDays(-10)
            if ($WindowStart -lt $Start) { $WindowStart = $Start }
            $Trace = Get-CIPPBecMessageTrace -TenantFilter $TenantFilter -SenderAddress $SenderAddress -StartDate $WindowStart -EndDate $WindowEnd
            foreach ($Row in $Trace.Rows) { $Rows.Add($Row) }
            if (-not $Trace.Complete) { $Complete = $false }
            $WindowEnd = $WindowStart
        }
        if ($Subject) { $Rows = [System.Collections.Generic.List[object]]@($Rows | Where-Object { [string]$_.Subject -like "*$Subject*" }) }

        $Recipients = @($Rows | Where-Object { $_.RecipientAddress } | Group-Object -Property { ([string]$_.RecipientAddress).ToLowerInvariant() } | ForEach-Object {
                $Times = @($_.Group | ForEach-Object { try { ([datetime]$_.Received).ToUniversalTime() } catch { $null } } | Where-Object { $_ } | Sort-Object)
                $Domain = ($_.Name -split '@')[-1]
                [pscustomobject]@{
                    Recipient     = $_.Name
                    Internal      = ($Accepted.Count -gt 0 -and $Domain -in $Accepted)
                    MessageCount  = @($_.Group.MessageTraceId | Select-Object -Unique).Count
                    FirstReceived = if ($Times.Count -gt 0) { $Times[0].ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
                    LastReceived  = if ($Times.Count -gt 0) { $Times[-1].ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
                    Statuses      = (@($_.Group.Status | Where-Object { $_ } | Select-Object -Unique) -join ', ')
                    Subjects      = (@($_.Group.Subject | Where-Object { $_ } | Select-Object -Unique | Select-Object -First 3) -join ' | ')
                }
            } | Sort-Object -Property @{ Expression = { $_.Internal }; Descending = $true }, Recipient)

        $Body = [pscustomobject]@{
            Sender       = $SenderAddress
            Days         = $Days
            Complete     = $Complete
            TotalMessages = @($Rows.MessageTraceId | Select-Object -Unique).Count
            Recipients   = $Recipients
            InternalCount = @($Recipients | Where-Object { $_.Internal }).Count
            ExternalCount = @($Recipients | Where-Object { -not $_.Internal }).Count
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = @{ Results = "Failed to trace the spread from $SenderAddress`: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
