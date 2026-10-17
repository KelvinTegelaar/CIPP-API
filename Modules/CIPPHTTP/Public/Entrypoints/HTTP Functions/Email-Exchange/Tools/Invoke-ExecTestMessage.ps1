function Invoke-ExecTestMessage {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.TransportRule.ReadWrite
    .DESCRIPTION
        Runs Exchange Online's Test-Message against a tenant: a test message is pushed through the
        mail flow rule (and optionally unified DLP) evaluation pipeline and Exchange emails a report
        of every rule that matched to the SendReportTo mailbox. Nothing is returned inline. The
        message is either an uploaded .eml (MessageFileBase64) or a minimal one CIPP builds from
        Subject and Body. Because the message really enters the pipeline, rule actions such as
        block, moderate or notify can fire for it. The dropped message's trace carries the rules
        that acted, so an async deployment job (DeploymentId) waits for it on the queue and
        pushes the verdict live; the page follows it through ListAsyncDeployment.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $Sender = [string]($Request.Body.Sender.value ?? $Request.Body.Sender)
    $SendReportTo = [string]($Request.Body.SendReportTo.value ?? $Request.Body.SendReportTo)
    $Recipients = @($Request.Body.Recipients | ForEach-Object { [string]($_.value ?? $_) } | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $TransportRules = if ($null -eq $Request.Body.TransportRules) { $true } else { [bool]$Request.Body.TransportRules }
    $UnifiedDlpRules = [bool]$Request.Body.UnifiedDlpRules

    try {
        if (-not $TenantFilter) { throw 'tenantFilter is required.' }
        if ($Recipients.Count -eq 0) { throw 'At least one recipient is required.' }
        if ([string]::IsNullOrWhiteSpace($SendReportTo)) { throw 'SendReportTo is required; the results are emailed there.' }
        if (-not $TransportRules -and -not $UnifiedDlpRules) { throw 'Select mail flow rules, unified DLP rules, or both.' }

        # Exchange's admin API hangs until it times out on a recipient domain that cannot receive
        # mail, so refuse those up front. Only external domains need MX; a failed lookup is not proof.
        $AcceptedDomains = try { @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AcceptedDomain' | ForEach-Object { "$($_.DomainName)".ToLowerInvariant() }) } catch { @() }
        $ExternalDomains = @($Recipients | ForEach-Object { ($_ -split '@')[-1].ToLowerInvariant() } | Select-Object -Unique | Where-Object { $_ -and $_ -notin $AcceptedDomains })
        $NoMailDomains = foreach ($Domain in $ExternalDomains) {
            try { $Mx = Resolve-DnsHttpsQuery -Domain $Domain -RecordType 'MX' -ErrorAction Stop } catch { continue }
            $Hosts = @($Mx.Answer | Where-Object { $_.type -eq 15 } | ForEach-Object { ("$($_.data)" -split ' ', 2)[-1].Trim() })
            # NXDOMAIN, no MX at all, or a null MX ('0 .', RFC 7505) all mean the domain takes no mail.
            if ($Mx.Status -eq 3 -or ($Mx.Status -eq 0 -and ($Hosts.Count -eq 0 -or @($Hosts | Where-Object { $_ -ne '.' }).Count -eq 0))) { $Domain }
        }
        if (@($NoMailDomains).Count -gt 0) {
            throw "These recipient domains do not accept mail (no MX record): $(@($NoMailDomains) -join ', '). Use a recipient on a domain that receives mail."
        }

        $SubmittedUtc = [datetime]::UtcNow
        if (![string]::IsNullOrWhiteSpace($Request.Body.MessageFileBase64)) {
            $MessageBytes = [System.Convert]::FromBase64String([string]$Request.Body.MessageFileBase64)
            # The subject lets the frontend find the dropped message in the trace afterwards.
            $HeaderBlock = ([System.Text.Encoding]::UTF8.GetString($MessageBytes) -split "`r?`n`r?`n", 2)[0]
            $SubjectLine = @($HeaderBlock -split "`r?`n" | Where-Object { $_ -match '^(?i)Subject:' })[0]
            $Subject = if ($SubjectLine) { ($SubjectLine -replace '^(?i)Subject:\s*', '').Trim() } else { '' }
        } else {
            # Minimal RFC 5322 message. CRLF line endings and a Message-ID keep it well-formed for
            # the pipeline; the sender and recipients on the command still decide the envelope.
            $Subject = if ([string]::IsNullOrWhiteSpace($Request.Body.Subject)) { 'CIPP mail flow rule test' } else { [string]$Request.Body.Subject }
            $BodyText = if ([string]::IsNullOrWhiteSpace($Request.Body.Body)) { 'This is a test message sent by CIPP to evaluate mail flow rules.' } else { [string]$Request.Body.Body }
            $From = if ($Sender) { $Sender } else { $SendReportTo }
            $Eml = @(
                "From: $From"
                "To: $($Recipients -join ', ')"
                "Subject: $Subject"
                "Date: $([datetime]::UtcNow.ToString('r'))"
                "Message-ID: <$([guid]::NewGuid().Guid)@cipp.test>"
                'MIME-Version: 1.0'
                'Content-Type: text/plain; charset=utf-8'
                'Content-Transfer-Encoding: 8bit'
                ''
                $BodyText
            ) -join "`r`n"
            $MessageBytes = [System.Text.Encoding]::UTF8.GetBytes($Eml)
        }

        $CmdParams = @{
            MessageFileData = $MessageBytes
            Recipients      = $Recipients
            SendReportTo    = $SendReportTo
            Force           = $true
        }
        if ($Sender) { $CmdParams.Sender = $Sender }
        if ($TransportRules) { $CmdParams.TransportRules = $true }
        if ($UnifiedDlpRules) { $CmdParams.UnifiedDlpRules = $true }

        $PrimaryRecipient = $Recipients[0]
        $JobId = New-CIPPAsyncDeployment -Names @($PrimaryRecipient) -StepTitles @('Submit the test message', 'Locate it in the message trace', 'Evaluate the mail flow rules') -Source 'TestMessage' -TenantFilter $TenantFilter
        Set-CIPPAsyncDeploymentStep -JobId $JobId -Name $PrimaryRecipient -StepIndex 0 -StepStatus 'running' -Message 'Submitting to Exchange'
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Test-Message' -cmdParams $CmdParams
        } catch {
            # The admin API runs the cmdlet, Exchange submits the message and emails the report,
            # and only then the proxy fails to serialise the cmdlet's TestMessageResult object
            # ("Unable to cast ... to System.Collections.IEnumerable"). That is a proxy defect after
            # the work is done, so it counts as submitted. Anything else is a real failure.
            if ($_.Exception.Message -notmatch 'TestMessageResult' -and $_.ErrorDetails.Message -notmatch 'TestMessageResult') { throw }
        }
        $Scope = @(@{ Key = $TransportRules; Label = 'mail flow rules' }, @{ Key = $UnifiedDlpRules; Label = 'unified DLP rules' }) | Where-Object { $_.Key } | ForEach-Object { $_.Label }
        Set-CIPPAsyncDeploymentStep -JobId $JobId -Name $PrimaryRecipient -StepIndex 0 -StepStatus 'succeeded' -Message "Submitted; the report goes to $SendReportTo"
        $null = Start-CIPPOrchestrator -InputObject @{
            OrchestratorName = 'TestMessageTraceOrchestrator'
            Batch            = @([pscustomobject]@{
                    FunctionName = 'ExecTestMessageTrace'
                    TenantFilter = $TenantFilter
                    DeploymentId = $JobId
                    Name         = $PrimaryRecipient
                    Sender       = $Sender
                    Recipient    = $PrimaryRecipient
                    Subject      = $Subject
                    SubmittedUtc = $SubmittedUtc.ToString('o')
                })
            SkipLog          = $true
        }
        $Result = "Test message submitted for $($Recipients -join ', ') against $($Scope -join ' and '). Exchange will email the rule evaluation report to $SendReportTo; it usually arrives within a few minutes."
        $Body = @{
            Results      = $Result
            DeploymentId = $JobId
            Sender       = $Sender
            Recipients   = @($Recipients)
            Subject      = $Subject
            SubmittedUtc = $SubmittedUtc.ToString('o')
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Submitted a Test-Message run ($($Scope -join ' and ')) for $($Recipients -join ', ') with the report going to $SendReportTo" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to submit the test message: $($ErrorMessage.NormalizedError)"
        if ($JobId) {
            Set-CIPPAsyncDeploymentStep -JobId $JobId -Name $PrimaryRecipient -StepIndex 0 -StepStatus 'failed' -Message $ErrorMessage.NormalizedError
            Set-CIPPAsyncDeploymentStatus -JobId $JobId -Name $PrimaryRecipient -Status 'failed'
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{ Results = $Result }
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
