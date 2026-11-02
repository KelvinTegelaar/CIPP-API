function Push-ExecTestMessageTrace {
    <#
    .FUNCTIONALITY
        Entrypoint
    .DESCRIPTION
        Queue worker behind Invoke-ExecTestMessage. Exchange drops a Test-Message submission after
        evaluating the rules, and the dropped message's trace carries one event per rule that acted.
        Waits for that trace to appear, reads its detail, lines it up against every mail flow rule in
        the tenant, and records the verdict on the async deployment job so the page gets it live.
    #>
    param($Item)
    $Item = $Item | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $JobId = $Item.DeploymentId
    $Name = $Item.Name
    $TenantFilter = $Item.TenantFilter
    $GraphBase = 'https://graph.microsoft.com/beta/admin/exchange/tracing/messageTraces'
    # Same escaping the trace endpoint applies to its own OData string literals.
    function ConvertTo-ODataLiteral { param([string]$Value) $Value -replace "'", "''" }
    try {
        Set-CIPPAsyncDeploymentStatus -JobId $JobId -Name $Name -Status 'running'
        Set-CIPPAsyncDeploymentStep -JobId $JobId -Name $Name -StepIndex 1 -StepStatus 'running' -Message 'Waiting for the dropped test message to appear in the message trace'

        $SubmittedUtc = ([datetimeoffset]$Item.SubmittedUtc).UtcDateTime
        $Start = $SubmittedUtc.AddMinutes(-2).ToString('yyyy-MM-ddTHH:mm:ssZ')
        $End = $SubmittedUtc.AddMinutes(30).ToString('yyyy-MM-ddTHH:mm:ssZ')
        $Filters = [System.Collections.Generic.List[string]]::new()
        $Filters.Add("receivedDateTime ge $Start and receivedDateTime le $End")
        $Filters.Add("recipientAddress eq '$(ConvertTo-ODataLiteral $Item.Recipient)'")
        if ($Item.Sender) { $Filters.Add("senderAddress eq '$(ConvertTo-ODataLiteral $Item.Sender)'") }
        if ($Item.Subject) { $Filters.Add("contains(subject, '$(ConvertTo-ODataLiteral $Item.Subject)')") }
        $SearchUri = $GraphBase + '?$top=50&$filter=' + [uri]::EscapeDataString($Filters -join ' and ')

        # Poll for up to five minutes; the trace usually has the message inside one.
        $Deadline = (Get-Date).AddMinutes(5)
        $Trace = $null
        do {
            $Rows = @(New-GraphGetRequest -uri $SearchUri -tenantid $TenantFilter -AsApp $true)
            $Trace = $Rows | Where-Object { $_.receivedDateTime -and ([datetime]$_.receivedDateTime).ToUniversalTime() -ge $SubmittedUtc.AddMinutes(-1) } | Sort-Object receivedDateTime -Descending | Select-Object -First 1
            if (-not $Trace) { Start-Sleep -Seconds 15 }
        } until ($Trace -or (Get-Date) -gt $Deadline)

        if (-not $Trace) {
            Set-CIPPAsyncDeploymentStep -JobId $JobId -Name $Name -StepIndex 1 -StepStatus 'failed' -Message 'The test message did not appear in the message trace within five minutes. The emailed report is the fallback.'
            Set-CIPPAsyncDeploymentStatus -JobId $JobId -Name $Name -Status 'failed'
            return
        }
        Set-CIPPAsyncDeploymentStep -JobId $JobId -Name $Name -StepIndex 1 -StepStatus 'succeeded' -Message "Found in the trace, status $($Trace.status), received $($Trace.receivedDateTime)"
        Set-CIPPAsyncDeploymentStep -JobId $JobId -Name $Name -StepIndex 2 -StepStatus 'running' -Message 'Reading the trace detail and the mail flow rules'

        $DetailUri = "$GraphBase/$($Trace.id)/getDetailsByRecipient(recipientAddress='$(ConvertTo-ODataLiteral $Item.Recipient)')"
        # The detail fills in after the message shows up, and rule events can follow the Drop, so
        # read until it holds a final Drop/Fail and stops growing between two reads.
        $PreviousCount = -1
        do {
            $Events = @(New-GraphGetRequest -uri $DetailUri -tenantid $TenantFilter -AsApp $true | ForEach-Object {
                    [pscustomobject]@{ Date = $_.dateTime; Event = $_.event; Detail = $_.description; Action = $_.action }
                })
            $Settled = $Events.Count -eq $PreviousCount -and @($Events | Where-Object { $_.Event -in 'Drop', 'Fail' }).Count -gt 0
            $PreviousCount = $Events.Count
            if (-not $Settled) { Start-Sleep -Seconds 15 }
        } until ($Settled -or (Get-Date) -gt $Deadline)
        $Rules = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-TransportRule' | Select-Object Name, Guid, Priority, State, Mode, StopRuleProcessing)

        # Trace detail names each rule by GUID: "Transport rule: 'Name', ID: ('GUID'), DLP policy: ..."
        $ActedById = @{}
        foreach ($Event in ($Events | Where-Object { $_.Event -match '(?i)transport rule|dlp' })) {
            if ("$($Event.Detail)" -match "ID:\s*\('?([0-9a-f-]{36})'?\)") {
                $Id = $Matches[1].ToLowerInvariant()
                # Exchange logs each acting rule once per pass, so the same action repeats.
                if (-not $ActedById.ContainsKey($Id)) { $ActedById[$Id] = [System.Collections.Generic.List[string]]::new() }
                if ($Event.Action -and -not $ActedById[$Id].Contains("$($Event.Action)")) { $ActedById[$Id].Add("$($Event.Action)") }
            }
        }
        # A rule that did not act was not matched, disabled, or never reached because an applied
        # rule above it stops processing; tell the three apart so "Not applied" means not matched.
        $StoppedAfter = $null
        $RuleRows = foreach ($Rule in ($Rules | Sort-Object Priority)) {
            $Id = "$($Rule.Guid)".ToLowerInvariant()
            $Actions = $ActedById[$Id]
            $Result = if ($null -ne $Actions) {
                if ($Rule.StopRuleProcessing -and $null -eq $StoppedAfter) { $StoppedAfter = [int]$Rule.Priority }
                'Applied'
            } elseif ("$($Rule.State)" -eq 'Disabled') { 'Disabled' }
            elseif ($null -ne $StoppedAfter -and [int]$Rule.Priority -gt $StoppedAfter) { 'Not reached' }
            else { 'Not applied' }
            [pscustomobject]@{
                Priority           = $Rule.Priority
                Name               = $Rule.Name
                Result             = $Result
                Actions            = ($Actions -join ', ')
                Mode               = "$($Rule.Mode)"
                StopRuleProcessing = [bool]$Rule.StopRuleProcessing
            }
        }
        $Applied = @($RuleRows | Where-Object Result -EQ 'Applied').Count
        $Considered = @($RuleRows | Where-Object Result -NE 'Disabled').Count
        $Logs = @{ Trace = @{ MessageTraceId = $Trace.id; Status = $Trace.status; Received = $Trace.receivedDateTime }; Events = $Events; Rules = @($RuleRows) } | ConvertTo-Json -Depth 6 -Compress
        Set-CIPPAsyncDeploymentStep -JobId $JobId -Name $Name -StepIndex 2 -StepStatus 'succeeded' -Message "$Applied of $Considered enabled rule$(if ($Considered -eq 1) { '' } else { 's' }) applied"
        Set-CIPPAsyncDeploymentStatus -JobId $JobId -Name $Name -Status 'succeeded' -Logs $Logs
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'ExecTestMessage' -tenant $TenantFilter -message "Could not evaluate the test message trace: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        Set-CIPPAsyncDeploymentStep -JobId $JobId -Name $Name -StepIndex 2 -StepStatus 'failed' -Message $ErrorMessage.NormalizedError
        Set-CIPPAsyncDeploymentStatus -JobId $JobId -Name $Name -Status 'failed'
    }
}
