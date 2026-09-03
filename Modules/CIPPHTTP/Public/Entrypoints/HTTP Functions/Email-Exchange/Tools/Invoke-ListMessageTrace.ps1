function Invoke-ListMessageTrace {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Traces email delivery in Exchange Online via the Graph message trace API
        (/beta/admin/exchange/tracing/messageTraces), searchable by sender, recipient, subject,
        status, IP, message ID and date range. Graph works over GDAP/app-only where the legacy
        reporting endpoints do not. Requires the "Transport Data Platform" service principal
        (8bd644d1-64a1-4d4b-ae52-2e0cbf64e373) in the tenant; it is provisioned on demand. Until
        that SP activates (which can take hours), or where the Graph permission is not yet
        consented, the request falls back to Get-MessageTraceV2 so results are returned immediately.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TransportAppId = '8bd644d1-64a1-4d4b-ae52-2e0cbf64e373'
    $GraphBase = 'https://graph.microsoft.com/beta/admin/exchange/tracing/messageTraces'
    $State = @{ Fallback = $false }

    # Escape a value for an OData string literal (single quotes are doubled).
    function ConvertTo-ODataLiteral { param([string]$Value) return ($Value -replace "'", "''") }

    # Runs the Graph scriptblock; on a missing service principal or a consent/permission error it
    # provisions the SP (best effort) and runs the Get-MessageTraceV2 scriptblock instead, so the
    # first call in a tenant still returns data while Graph activates.
    $RunWithFallback = {
        param($GraphBlock, $V2Block)
        try {
            return (& $GraphBlock)
        } catch {
            $Message = $_.Exception.Message
            $SpMissing = $Message -match $TransportAppId -or $Message -match 'service principal'
            $Consent = $Message -match 'Authorization_RequestDenied' -or $Message -match 'insufficient' -or $Message -match 'consent' -or $Message -match 'Forbidden' -or $Message -match 'AADSTS'
            if ($SpMissing -or $Consent) {
                # Provision the SP only when it is genuinely absent. Once created it can still take
                # hours to activate, during which Graph keeps reporting it missing - checking first
                # avoids re-issuing (and log-spamming) a create that would fail as 'already in use'.
                if ($SpMissing) {
                    $SpPresent = $false
                    try {
                        $SpPresent = [bool](New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/servicePrincipals(appId='$TransportAppId')" -tenantid $TenantFilter -NoAuthCheck $true).id
                    } catch {
                        $SpPresent = $false
                    }
                    if (-not $SpPresent) {
                        try {
                            $null = New-GraphPostRequest -Uri 'https://graph.microsoft.com/beta/servicePrincipals' -tenantid $TenantFilter -type POST -body (@{ appId = $TransportAppId } | ConvertTo-Json -Compress) -NoAuthCheck $true
                        } catch {
                            # Lost a race with a concurrent provision - the V2 fallback covers this request.
                        }
                    }
                }
                $State.Fallback = $true
                return (& $V2Block)
            }
            throw
        }
    }

    try {
        $TenantFilter = $Request.Body.tenantFilter
        $Recipient = $Request.Body.recipient.value ?? $Request.Body.recipient

        if ($Request.Body.traceDetail) {
            $DetailUri = "$GraphBase/$($Request.Body.ID)/getDetailsByRecipient(recipientAddress='$(ConvertTo-ODataLiteral $Recipient)')"
            $GraphDetail = {
                New-GraphGetRequest -uri $DetailUri -tenantid $TenantFilter -AsApp $true |
                    Select-Object @{ Name = 'Date'; Expression = { $_.dateTime ? ([DateTime]$_.dateTime).ToString('u') : $null } },
                    @{ Name = 'Event'; Expression = { $_.event } },
                    @{ Name = 'Action'; Expression = { $_.action } },
                    @{ Name = 'Detail'; Expression = { $_.description } }
            }
            $V2Detail = {
                New-ExoRequest -TenantId $TenantFilter -Cmdlet 'Get-MessageTraceDetailV2' -CmdParams @{ MessageTraceId = $Request.Body.ID; RecipientAddress = $Recipient } |
                    Select-Object @{ Name = 'Date'; Expression = { $_.Date.ToString('u') } }, Event, Action, Detail
            }
            $Detail = @(& $RunWithFallback $GraphDetail $V2Detail)
            $Body = @{ Results = @($Detail); Metadata = @{ TraceDetail = $true; Source = $State.Fallback ? 'Get-MessageTraceV2' : 'Graph' } }
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $Body })
        }

        # Parse the shared search inputs.
        if ($Request.Body.days) {
            # Single UtcNow capture keeps the window exactly N days, not N days plus call latency.
            $End = [DateTime]::UtcNow
            $Start = $End.AddDays(-[double]$Request.Body.days)
        } elseif ($Request.Body.startDate -or $Request.Body.endDate) {
            $Start = $Request.Body.startDate ? ($Request.Body.startDate -match '^\d+$' ? [DateTimeOffset]::FromUnixTimeSeconds([int64]$Request.Body.startDate).UtcDateTime : [DateTime]::Parse($Request.Body.startDate, [cultureinfo]::InvariantCulture, 'AdjustToUniversal')) : $null
            $End = $Request.Body.endDate ? ($Request.Body.endDate -match '^\d+$' ? [DateTimeOffset]::FromUnixTimeSeconds([int64]$Request.Body.endDate).UtcDateTime : [DateTime]::Parse($Request.Body.endDate, [cultureinfo]::InvariantCulture, 'AdjustToUniversal')) : $null
        }
        if ($Start -and $End) {
            if (($End - $Start).TotalDays -gt 10) {
                throw 'Message trace queries are limited to a 10 day window. Narrow the date range, or use a historical search for longer periods.'
            }
            if (([DateTime]::UtcNow - $Start).TotalDays -gt 90) {
                throw 'Message trace data is only available for the last 90 days.'
            }
        }

        $MessageId = $Request.Body.messageId ?? $Request.Body.MessageId
        $MessageTraceId = $Request.Body.messageTraceId
        $Senders = @(@($Request.Body.sender).value ?? @($Request.Body.sender) | Where-Object { -not [string]::IsNullOrEmpty($_) })
        $Recipients = @(@($Request.Body.recipient).value ?? @($Request.Body.recipient) | Where-Object { -not [string]::IsNullOrEmpty($_) })
        $Statuses = @(@($Request.Body.status).value ?? @($Request.Body.status) | Where-Object { -not [string]::IsNullOrEmpty($_) })
        $ToIP = $Request.Body.toIP
        $FromIP = $Request.Body.fromIP
        $Subject = $Request.Body.subject
        $SubjectType = ($Request.Body.subjectFilterType.value ?? $Request.Body.subjectFilterType ?? 'StartsWith')

        # Graph search: build the $filter clause.
        $Filters = [System.Collections.Generic.List[string]]::new()
        if ($Start -and $End) {
            $Filters.Add("receivedDateTime ge $($Start.ToString('yyyy-MM-ddTHH:mm:ssZ')) and receivedDateTime le $($End.ToString('yyyy-MM-ddTHH:mm:ssZ'))")
        }
        if (![string]::IsNullOrEmpty($MessageId)) { $Filters.Add("messageId eq '$(ConvertTo-ODataLiteral $MessageId)'") }
        if (![string]::IsNullOrEmpty($MessageTraceId)) { $Filters.Add("id eq '$(ConvertTo-ODataLiteral $MessageTraceId)'") }
        if ($Senders) { $Filters.Add('(' + (($Senders | ForEach-Object { "senderAddress eq '$(ConvertTo-ODataLiteral $_)'" }) -join ' or ') + ')') }
        if ($Recipients) { $Filters.Add('(' + (($Recipients | ForEach-Object { "recipientAddress eq '$(ConvertTo-ODataLiteral $_)'" }) -join ' or ') + ')') }
        if ($Statuses) {
            # Graph status enum is camelCase (delivered, filteredAsSpam, ...); the UI sends PascalCase.
            $Filters.Add('(' + (($Statuses | ForEach-Object { "status eq '$($_.Substring(0, 1).ToLower() + $_.Substring(1))'" }) -join ' or ') + ')')
        }
        if (![string]::IsNullOrEmpty($ToIP)) { $Filters.Add("toIP eq '$(ConvertTo-ODataLiteral $ToIP)'") }
        # Note: Graph cannot filter on fromIP (returned but not queryable); the V2 fallback can.
        if (![string]::IsNullOrEmpty($Subject)) {
            $Func = switch ($SubjectType) { 'Contains' { 'contains' } 'EndsWith' { 'endswith' } default { 'startswith' } }
            $Filters.Add("$Func(subject, '$(ConvertTo-ODataLiteral $Subject)')")
        }
        $Uri = $GraphBase + '?$top=5000'
        if ($Filters.Count -gt 0) { $Uri += "&`$filter=$([uri]::EscapeDataString($Filters -join ' and '))" }

        $GraphSearch = {
            New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -AsApp $true |
                Select-Object @{ Name = 'MessageTraceId'; Expression = { $_.id } },
                @{ Name = 'MessageId'; Expression = { $_.messageId } },
                @{ Name = 'Status'; Expression = { $_.status ? ($_.status.Substring(0, 1).ToUpper() + $_.status.Substring(1)) : $null } },
                @{ Name = 'Subject'; Expression = { $_.subject } },
                @{ Name = 'RecipientAddress'; Expression = { $_.recipientAddress } },
                @{ Name = 'SenderAddress'; Expression = { $_.senderAddress } },
                @{ Name = 'Received'; Expression = { $_.receivedDateTime ? ([DateTime]$_.receivedDateTime).ToString('u') : $null } },
                @{ Name = 'Size'; Expression = { $_.size } },
                @{ Name = 'FromIP'; Expression = { $_.fromIP } },
                @{ Name = 'ToIP'; Expression = { $_.toIP } }
        }
        $V2Search = {
            $CmdParams = @{ ResultSize = 5000 }
            if ($Start -and $End) { $CmdParams.StartDate = $Start.ToString('s'); $CmdParams.EndDate = $End.ToString('s') }
            if (![string]::IsNullOrEmpty($MessageId)) { $CmdParams.MessageId = @($MessageId) }
            if (![string]::IsNullOrEmpty($MessageTraceId)) { $CmdParams.MessageTraceId = $MessageTraceId }
            if ($Senders) { $CmdParams.SenderAddress = @($Senders) }
            if ($Recipients) { $CmdParams.RecipientAddress = @($Recipients) }
            if ($Statuses) { $CmdParams.Status = @($Statuses) }
            if (![string]::IsNullOrEmpty($ToIP)) { $CmdParams.ToIP = $ToIP }
            if (![string]::IsNullOrEmpty($FromIP)) { $CmdParams.FromIP = $FromIP }
            if (![string]::IsNullOrEmpty($Subject)) { $CmdParams.Subject = $Subject; $CmdParams.SubjectFilterType = $SubjectType }
            New-ExoRequest -TenantId $TenantFilter -Cmdlet 'Get-MessageTraceV2' -CmdParams $CmdParams |
                Select-Object MessageTraceId, MessageId, Status, Subject, RecipientAddress, SenderAddress,
                @{ Name = 'Received'; Expression = { $_.Received.ToString('u') } }, Size, FromIP, ToIP
        }

        $Trace = @(& $RunWithFallback $GraphSearch $V2Search)
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message 'Executed message trace' -Sev 'Info'

        $Metadata = @{ Returned = @($Trace).Count; Source = $State.Fallback ? 'Get-MessageTraceV2' : 'Graph' }
        if ($State.Fallback) {
            $Metadata.Note = 'Served via Get-MessageTraceV2 while the Graph message trace service principal activates for this tenant (this can take a few hours on first use).'
        }
        $Body = @{ Results = @($Trace); Metadata = $Metadata }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -message $_.Exception.Message
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Failed executing Message Trace. Error: $ErrorMessage" -Sev 'Error'
        $Body = @{
            Results  = @()
            Metadata = @{ Error = "Failed to retrieve message trace: $ErrorMessage" }
        }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
