function Invoke-AddDefenderIndicator {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Defender.ReadWrite
    .SYNOPSIS
        Add Defender custom indicators to one or more tenants
    .DESCRIPTION
        Adds up to 500 Microsoft Defender for Endpoint custom indicators (100,000 characters in total) of one type, with one action, to each selected tenant. Before writing, CIPP reads the tenant's indicators: a value that already exists there with a different action, or that is limited to device groups, is skipped in that tenant and left unchanged; a value that exists with the same action is updated. A single named tenant is written during the request: the reply holds one result per value, with 207 when only some succeed. AllTenants, or two or more tenants, is queued with one task per tenant: the reply is 202 with Metadata.QueueId, the queue tracks progress, and each tenant's results are written to the logbook. Defender shows the CIPP application as the creator; the indicator description starts with the technician who sent it.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    # One tenant, a list of tenants, or AllTenants. A tenant is its default domain or tenant id.
    $TenantFilter = $Request.Body.tenantFilter
    # FileSha1, FileSha256, FileMd5, CertificateThumbprint, IpAddress, Url or DomainName.
    $IndicatorType = $Request.Body.IndicatorType
    # The values to add, one per entry: up to 500 values and 100,000 characters in total.
    $Values = $Request.Body.Values
    # Allowed, Audit, Warn, Block or BlockAndRemediate. Certificates take Allowed or BlockAndRemediate; IP addresses, URLs and domains take Allowed, Audit, Warn or Block.
    $Action = $Request.Body.Action
    # Shown as the indicator's title in Defender.
    $Title = $Request.Body.Title
    # Optional note, added to the description in Defender after the technician's name.
    $Description = $Request.Body.Description
    # Optional expiry, an ISO 8601 date and time in the future.
    $ExpirationTime = $Request.Body.ExpirationTime
    # Optional alert severity: Informational, Low, Medium or High.
    $Severity = $Request.Body.Severity
    # Must be true when Action is Allowed: the technician confirms that Defender will trust these values in every selected tenant.
    $AcknowledgeAllow = $Request.Body.acknowledgeAllow

    $ActionsByType = @{
        FileSha1              = @('Allowed', 'Audit', 'Warn', 'Block', 'BlockAndRemediate')
        FileSha256            = @('Allowed', 'Audit', 'Warn', 'Block', 'BlockAndRemediate')
        FileMd5               = @('Allowed', 'Audit', 'Warn', 'Block', 'BlockAndRemediate')
        CertificateThumbprint = @('Allowed', 'BlockAndRemediate')
        IpAddress             = @('Allowed', 'Audit', 'Warn', 'Block')
        Url                   = @('Allowed', 'Audit', 'Warn', 'Block')
        DomainName            = @('Allowed', 'Audit', 'Warn', 'Block')
    }

    if ($IndicatorType -isnot [string] -or $IndicatorType -cnotin @($ActionsByType.Keys)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'IndicatorType must be FileSha1, FileSha256, FileMd5, CertificateThumbprint, IpAddress, Url or DomainName.' } })
    }
    if ($Action -isnot [string] -or $Action -cnotin $ActionsByType[$IndicatorType]) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "Action for $IndicatorType must be $($ActionsByType[$IndicatorType] -join ', ')." } })
    }
    if ($Action -ceq 'Allowed' -and ($AcknowledgeAllow -isnot [bool] -or -not $AcknowledgeAllow)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'acknowledgeAllow must be true to add Allowed indicators: Defender will trust these values on every device in the selected tenants.' } })
    }
    if ($Title -isnot [string] -or [string]::IsNullOrWhiteSpace($Title)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Title is required.' } })
    }
    if ($null -ne $Description -and $Description -isnot [string]) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Description must be text.' } })
    }
    if ($null -ne $Severity -and ($Severity -isnot [string] -or $Severity -cnotin 'Informational', 'Low', 'Medium', 'High')) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Severity must be Informational, Low, Medium or High.' } })
    }
    $Expiry = $null
    if ($null -ne $ExpirationTime) {
        $Parsed = [datetimeoffset]::MinValue
        if ($ExpirationTime -is [datetime]) {
            $Expiry = if ($ExpirationTime.Kind -eq [System.DateTimeKind]::Unspecified) { [datetime]::SpecifyKind($ExpirationTime, [System.DateTimeKind]::Utc) } else { $ExpirationTime.ToUniversalTime() }
        } elseif ($ExpirationTime -is [string] -and [datetimeoffset]::TryParse($ExpirationTime, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Parsed)) {
            $Expiry = $Parsed.UtcDateTime
        }
        if ($null -eq $Expiry -or $Expiry -le [datetime]::UtcNow) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ExpirationTime must be a date and time in the future.' } })
        }
    }

    $Submitted = [System.Collections.Generic.List[string]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $Invalid = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in @($Values)) {
        if ($null -eq $Entry) { continue }
        if ($Entry -isnot [string]) { $Invalid.Add("$Entry"); continue }
        $Value = $Entry.Trim()
        if (-not $Value) { continue }
        $Valid = switch -CaseSensitive ($IndicatorType) {
            'FileSha1' { $Value -match '\A[0-9a-f]{40}\z' }
            'FileSha256' { $Value -match '\A[0-9a-f]{64}\z' }
            'FileMd5' { $Value -match '\A[0-9a-f]{32}\z' }
            'CertificateThumbprint' { $Value -match '\A[0-9a-f]{40}\z' }
            'IpAddress' {
                $Octet = '(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
                if ($Value -match "\A$Octet\.$Octet\.$Octet\.$Octet\z") {
                    $A, $B = [int]$Matches[1], [int]$Matches[2]
                    -not ($A -in 0, 10, 127 -or $A -ge 224 -or ($A -eq 100 -and $B -ge 64 -and $B -le 127) -or ($A -eq 169 -and $B -eq 254) -or ($A -eq 172 -and $B -ge 16 -and $B -le 31) -or ($A -eq 192 -and $B -eq 168) -or ($A -eq 192 -and $B -eq 0 -and [int]$Matches[3] -eq 0) -or ($A -eq 198 -and $B -in 18, 19))
                } else {
                    $Value -match '\A([0-9a-f]{4}:){7}[0-9a-f]{4}\z' -and $Value -notmatch '\A(00|f[c-f])'
                }
            }
            'Url' {
                $Uri = $null
                $Value -match '\Ahttps?://[^\s/?#]+[^\s]*\z' -and [uri]::TryCreate($Value, [System.UriKind]::Absolute, [ref]$Uri) -and $Uri.Host -and $Value -notmatch '%(?![0-9a-f]{2})'
            }
            'DomainName' { $Value -match '\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?\z' }
        }
        if (-not $Valid) { $Invalid.Add($Value); continue }
        $Value = $Value.ToLowerInvariant()
        if ($Seen.Add($Value)) { $Submitted.Add($Value) }
    }
    if ($Invalid.Count -gt 0) {
        $Hint = switch -CaseSensitive ($IndicatorType) {
            'FileSha1' { 'Enter SHA-1 hashes of 40 hexadecimal characters.' }
            'FileSha256' { 'Enter SHA-256 hashes of 64 hexadecimal characters.' }
            'FileMd5' { 'Enter MD5 hashes of 32 hexadecimal characters.' }
            'CertificateThumbprint' { 'Enter certificate SHA-1 thumbprints of 40 hexadecimal characters.' }
            'IpAddress' { 'Enter single public IPv4 addresses, or IPv6 addresses written in full as eight groups of four digits. Ranges, CIDR and private addresses are not accepted.' }
            'Url' { 'Enter full http:// or https:// URLs without spaces. Each percent sign must start a two-digit hexadecimal escape.' }
            'DomainName' { 'Enter domain names without http://, a path or wildcards.' }
        }
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "These values are not valid $IndicatorType indicators: $(@($Invalid)[0..([Math]::Min(9, $Invalid.Count - 1))] -join ', '). $Hint" } })
    }
    if ($Submitted.Count -eq 0 -or $Submitted.Count -gt 500) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Values must hold between 1 and 500 different values.' } })
    }
    $Characters = 0
    foreach ($Value in $Submitted) { $Characters = $Characters + $Value.Length }
    if ($Characters -gt 100000) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "These values hold $($Characters.ToString('N0', [cultureinfo]::InvariantCulture)) characters in total; one add takes up to 100,000. Split them into smaller adds." } })
    }

    $Named = [System.Collections.Generic.List[string]]::new()
    foreach ($Item in @($TenantFilter)) {
        if ($null -eq $Item) { continue }
        $Name = if ($Item -is [string]) { $Item } elseif ($Item.value -is [string] -and $Item.type -ne 'Group') { $Item.value }
        if ([string]::IsNullOrWhiteSpace($Name) -or $Name -like 'group:*') {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter must name tenants or AllTenants. Tenant groups are not accepted for this action.' } })
        }
        $Named.Add($Name.Trim())
    }
    if ($Named.Count -eq 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter must name at least one tenant.' } })
    }
    if ($Named -contains 'AllTenants' -and @($Named.Where({ $_ -ne 'AllTenants' })).Count -gt 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter cannot combine AllTenants with named tenants.' } })
    }

    try {
        $Known = @(Get-Tenants)
    } catch {
        return ([HttpResponseContext]@{ StatusCode = Get-CippErrorStatusCode -ErrorRecord $_; Body = @{ Results = "Failed to read the tenant list: $($_.Exception.Message)" } })
    }
    $Lookup = Get-CIPPTenantLookup -Tenants $Known
    $Targets = [System.Collections.Generic.List[object]]::new()
    $TargetIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Unknown = [System.Collections.Generic.List[string]]::new()
    $Candidates = if ($Named -contains 'AllTenants') {
        $Known
    } else {
        foreach ($Name in $Named) {
            if ($Lookup.ContainsKey($Name)) { $Lookup[$Name] } elseif (-not $Unknown.Contains($Name)) { $Unknown.Add($Name) }
        }
    }
    foreach ($Tenant in $Candidates) {
        if ($Tenant.customerId -and $TargetIds.Add($Tenant.customerId)) { $Targets.Add($Tenant) }
    }
    if ($Unknown.Count -gt 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "These tenants are not managed by CIPP or are not available to you: $($Unknown -join ', ')." } })
    }
    if ($Targets.Count -eq 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'No tenants are available to you.' } })
    }

    $Technician = try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { $null }
    if (-not $Technician) { $Technician = $Headers.'x-ms-client-principal-name' }
    if (-not $Technician) { $Technician = 'CIPP' }
    $Template = @{
        indicatorType = $IndicatorType
        action        = $Action
        title         = $Title.Trim()
        description   = if ([string]::IsNullOrWhiteSpace($Description)) { "$Technician via CIPP" } else { "$Technician via CIPP: $($Description.Trim())" }
    }
    if ($Expiry) { $Template.expirationTime = $Expiry.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture) }
    if ($Severity) { $Template.severity = $Severity }
    if ($Action -ceq 'Audit') { $Template.generateAlert = $true }

    if ($Targets.Count -eq 1 -and $Named -notcontains 'AllTenants') {
        $Outcome = Add-CIPPDefenderIndicator -TenantFilter $Targets[0].defaultDomainName -TenantId $Targets[0].customerId -Values $Submitted.ToArray() -Template $Template -Headers $Headers -APIName $APIName
        $StatusCode = if ($Outcome.Conflicts -eq $Submitted.Count) { [HttpStatusCode]::BadRequest } else { Get-CippBulkStatusCode -Total $Submitted.Count -Failed $Outcome.Failed }
        return ([HttpResponseContext]@{
                StatusCode = $StatusCode
                Body       = @{ Results = @($Outcome.Results) }
            })
    }

    $AuditHeaders = @{}
    if ($Headers.'x-ms-client-principal-idp' -eq 'aad') {
        $AuditHeaders['x-ms-client-principal-idp'] = 'aad'
        $AuditHeaders['x-ms-client-principal-name'] = [string]$Headers.'x-ms-client-principal-name'
    } else {
        $AuditHeaders['x-ms-client-principal'] = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((@{ userDetails = $Technician } | ConvertTo-Json -Compress)))
    }
    $ForwardedFor = ([string]$Headers.'x-forwarded-for' -split ',')[0].Trim()
    if ($ForwardedFor) { $AuditHeaders['x-forwarded-for'] = $ForwardedFor }

    try {
        $Queue = New-CippQueueEntry -Name "Add Defender indicators - $Action $IndicatorType" -Link '/security/defender/indicators' -TotalTasks $Targets.Count
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Did not queue $Action $IndicatorType indicators for $($Targets.Count) tenants: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = @{ Results = "Nothing was added: CIPP could not create the queue. $($ErrorMessage.NormalizedError)" } })
    }

    $TenantValues = $Submitted.ToArray()
    $TemplateJson = ConvertTo-Json -InputObject $Template -Compress
    $Batch = foreach ($Tenant in $Targets) {
        [pscustomobject]@{
            FunctionName = 'ExecAddDefenderIndicator'
            Tenant       = $Tenant.defaultDomainName
            TenantId     = $Tenant.customerId
            Values       = $TenantValues
            TemplateJson = $TemplateJson
            AuditHeaders = $AuditHeaders
            QueueId      = $Queue.RowKey
        }
    }
    try {
        $null = Start-CIPPOrchestrator -InputObject ([pscustomobject]@{ OrchestratorName = 'DefenderIndicatorOrchestrator'; Batch = @($Batch); SkipLog = $true }) -ErrorAction Stop
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        try {
            $null = Update-CippQueueEntry -RowKey $Queue.RowKey -Status 'Failed'
        } catch {
            Write-LogMessage -headers $Headers -API $APIName -message "Could not mark queue $($Queue.RowKey) as failed: $($_.Exception.Message)" -sev Warning
        }
        Write-LogMessage -headers $Headers -API $APIName -message "Could not confirm the start of adding $Action $IndicatorType indicators for $($Targets.Count) tenants (queue $($Queue.RowKey)): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = @{ Results = "CIPP could not confirm that it started adding the indicators for queue $($Queue.RowKey). $($ErrorMessage.NormalizedError) Check the queue and the logbook before you try again." } })
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Accepted
            Body       = @{
                Results  = "Queued $($Submitted.Count) $Action $IndicatorType $(if ($Submitted.Count -eq 1) { 'indicator' } else { 'indicators' }) for $($Targets.Count) $(if ($Targets.Count -eq 1) { 'tenant' } else { 'tenants' })."
                Metadata = @{ QueueId = $Queue.RowKey }
            }
        })
}
