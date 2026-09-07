function Invoke-CippWebhookProcessing {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $Data,
        $Resource,
        $Operations,
        $CIPPURL,
        $AlertComment,
        $APIName = 'Process webhook',
        $Headers,
        # Optional accumulator. When supplied, the completed audit-log row is added to it instead of
        # being written here, so the caller can flush a batch of them in one transaction - they all
        # share the tenant partition key. A list rather than a return value on purpose: this
        # function's output stream already carries whatever Send-CIPPAlert returns, and adding to it
        # would push that further up into Test-CIPPAuditLogRules' own output.
        [System.Collections.Generic.List[object]]$PendingAuditLogWrites
    )

    $AuditLogTable = Get-CIPPTable -TableName 'AuditLogs'

    # Claim the event ID immediately, with no read first. The claim is an Insert without -Force, so
    # a conflict already tells us another worker (or an earlier run) owns this event - the read that
    # used to precede it answered the same question a round trip earlier and could not make the
    # claim any safer, because a row could still appear between the two. It was one extra table read
    # per MATCHED record, measured at 28% of the processing stage once rules actually fire.
    # A duplicate now costs one failed insert instead of one read; a new event costs one insert
    # instead of a read plus an insert.
    # -ErrorAction Stop ensures non-terminating errors enter the catch block.
    try {
        Add-CIPPAzDataTableEntity @AuditLogTable -Entity @{
            PartitionKey = $TenantFilter
            RowKey       = $Data.Id
            Title        = 'Processing'
            Tenant       = $TenantFilter
        } -ErrorAction Stop
    } catch {
        Write-Host "Audit log $($Data.Id) already claimed or already processed. Skipping."
        return
    }

    # Memoised per tenant. Get-Tenants does no in-process caching of its own: every call reads the
    # tenants table twice, filters through the pipeline and sorts the whole list, measured at 26 ms
    # against a 16-tenant list and growing with the tenant count. This function runs once per
    # MATCHED audit record, so at a few hundred tenants each matching a handful of records per
    # cycle, the pipeline spent minutes per cycle re-deriving an answer that is identical every
    # time. Five minutes, because the tenant list is itself a cached table that turns over on the
    # order of hours; a tenant onboarded mid-window resolves on the next cycle.
    # A miss caches the null result too - an unknown tenant must not re-query per record either.
    if ($null -eq $script:WebhookTenantCache) {
        $script:WebhookTenantCache = @{}
    }
    $TenantCacheNow = [datetime]::UtcNow
    $TenantEntry = $script:WebhookTenantCache[$TenantFilter]
    if ($TenantEntry -and $TenantEntry.Expires -gt $TenantCacheNow) {
        $Tenant = $TenantEntry.Tenant
    } else {
        foreach ($CachedTenant in @($script:WebhookTenantCache.Keys)) {
            if ($script:WebhookTenantCache[$CachedTenant].Expires -le $TenantCacheNow) {
                $script:WebhookTenantCache.Remove($CachedTenant)
            }
        }
        $Tenant = Get-Tenants -IncludeErrors | Where-Object { $_.defaultDomainName -eq $TenantFilter }
        $script:WebhookTenantCache[$TenantFilter] = [PSCustomObject]@{
            Expires = $TenantCacheNow.AddMinutes(5)
            Tenant  = $Tenant
        }
    }
    Write-Host "Received data. Our Action List is $($Data.CIPPAction)"

    $ActionList = ($Data.CIPPAction | ConvertFrom-Json -ErrorAction SilentlyContinue).value
    $ActionResults = foreach ($action in $ActionList) {
        # Serialising every action at depth 15 just to print it, once per action per MATCHED
        # record, is not worth paying for at alerting volume. Left in place rather than deleted
        # because it is genuinely useful when working on a specific tenant's actions - uncomment
        # it then. Write-Host targets the host stream, not the output stream, so this does not
        # affect what $ActionResults collects.
        #Write-Host "this is our action: $($action | ConvertTo-Json -Depth 15 -Compress)"
        switch ($action) {
            'disableUser' {
                try {
                    Set-CIPPSignInState -TenantFilter $TenantFilter -User $Data.UserId -AccountEnabled $false -APIName 'Alert Engine' -Headers 'Alert Engine'
                } catch {
                    Write-Host "Failed to disable user $($Data.UserId)`: $($_.Exception.Message)"
                }
            }
            'becremediate' {
                $Username = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Data.UserId)" -tenantid $TenantFilter).UserPrincipalName
                try {
                    Set-CIPPResetPassword -UserID $Username -tenantFilter $TenantFilter -APIName 'Alert Engine' -Headers 'Alert Engine'
                } catch {
                    Write-Host "Failed to reset password for $Username`: $($_.Exception.Message)"
                }
                try {
                    Set-CIPPSignInState -userid $Username -AccountEnabled $false -tenantFilter $TenantFilter -APIName 'Alert Engine' -Headers 'Alert Engine'
                } catch {
                    Write-Host "Failed to disable sign-in for $Username`: $($_.Exception.Message)"
                }
                try {
                    Revoke-CIPPSessions -userid $Username -username $Username -Headers 'Alert Engine' -APIName 'Alert Engine' -tenantFilter $TenantFilter
                } catch {
                    Write-Host "Failed to revoke sessions for $Username`: $($_.Exception.Message)"
                }
                $RuleDisabled = 0
                New-ExoRequest -anchor $Username -tenantid $TenantFilter -cmdlet 'Get-InboxRule' -cmdParams @{Mailbox = $Username; IncludeHidden = $true } | Where-Object { $_.Name -ne 'Junk E-Mail Rule' -and $_.Name -notlike 'Microsoft.Exchange.OOF.*' } | ForEach-Object {
                    $null = New-ExoRequest -anchor $Username -tenantid $TenantFilter -cmdlet 'Disable-InboxRule' -cmdParams @{Confirm = $false; Identity = $_.Identity }
                    "Disabled Inbox Rule $($_.Identity) for $Username"
                    $RuleDisabled++
                }
                if ($RuleDisabled) {
                    "Disabled $RuleDisabled Inbox Rules for $Username"
                } else {
                    "No Inbox Rules found for $Username. We have not disabled any rules."
                }
                "Completed BEC Remediate for $Username"
                Write-LogMessage -API 'BECRemediate' -tenant $tenantfilter -message "Executed Remediation for $Username" -sev 'Info'
            }
            <#'cippcommand' {
                $CommandSplat = @{}
                $action.parameters.psobject.properties | ForEach-Object { $CommandSplat.Add($_.name, $_.value) }
                if ($CommandSplat['userid']) { $CommandSplat['userid'] = $Data.UserId }
                if ($CommandSplat['tenantfilter']) { $CommandSplat['tenantfilter'] = $TenantFilter }
                if ($CommandSplat['tenant']) { $CommandSplat['tenant'] = $TenantFilter }
                if ($CommandSplat['user']) { $CommandSplat['user'] = $Data.UserId }
                if ($CommandSplat['username']) { $CommandSplat['username'] = $Data.UserId }
                & $action.command.value @CommandSplat
            }#>
            default {
                Write-Host "Unknown action: $action"
            }
        }
    }

    # Save audit log entry to table
    $LocationInfo = $Data.CIPPLocationInfo | ConvertFrom-Json -ErrorAction SilentlyContinue
    $AuditRecord = $Data.AuditRecord | ConvertFrom-Json -ErrorAction SilentlyContinue
    $GenerateJSON = New-CIPPAlertTemplate -format 'json' -data $Data -ActionResults $ActionResults -CIPPURL $CIPPURL -AlertComment $AlertComment -CustomSubject $Data.CIPPCustomSubject -Tenant $Tenant.defaultDomainName
    $JsonContent = @{
        Title                 = $GenerateJSON.Title
        ActionUrl             = $GenerateJSON.ButtonUrl
        ActionText            = $GenerateJSON.ButtonText
        RawData               = $Data
        IP                    = $Data.ClientIP
        PotentialLocationInfo = $LocationInfo
        ActionsTaken          = $ActionResults
        AuditRecord           = $AuditRecord
        AlertComment          = $AlertComment
    } | ConvertTo-Json -Depth 15 -Compress

    # Built here, written at the very bottom - after the alerts have gone out. See the note there.
    $AuditLogRow = @{
        PartitionKey = $TenantFilter
        RowKey       = $Data.Id
        Title        = $GenerateJSON.Title
        Data         = [string]$JsonContent
        Tenant       = $TenantFilter
    }
    $LogId = $Data.Id

    $AuditLogLink = '{0}/tenant/administration/audit-logs/log?logId={1}&tenantFilter={2}' -f $CIPPURL, $LogId, $Tenant.defaultDomainName
    # The html render is deferred to the generatemail branch below, which is its only consumer.
    # Rendering it here meant every matched record paid for an email body whether or not any rule
    # asked for one - two template renders per alert where one was needed, ~15% of the processing
    # stage between them.

    # Derive the affected end-user from the audit record so PSA tickets can be linked to the
    # right HaloPSA contact when HaloPSA.LinkTicketsToUsers is enabled. The upstream GUID mapper
    # has already attached CIPP-prefixed properties (e.g. CIPPObjectId) holding the resolved UPN
    # for any property that contained a user's Object ID; the raw property usually still holds
    # the original GUID, which we can use directly as the AzureOID for the Halo lookup.
    $AffectedUser = $null
    $GuidRegex = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    $UserCandidates = @(
        @{ Raw = 'ObjectId'; Mapped = 'CIPPObjectId' }
        @{ Raw = 'UserId';   Mapped = 'CIPPUserId' }
        @{ Raw = 'Userkey';  Mapped = 'CIPPUserkey' }
    )
    foreach ($Candidate in $UserCandidates) {
        $RawValue = $Data.$($Candidate.Raw)
        $MappedValue = $Data.$($Candidate.Mapped)
        if (-not $RawValue -and -not $MappedValue) { continue }

        $UPN = $null; $OID = $null
        if ($MappedValue -is [string] -and $MappedValue -match '@') { $UPN = $MappedValue }
        elseif ($RawValue -is [string] -and $RawValue -match '@')   { $UPN = $RawValue }

        if ($RawValue -is [string] -and $RawValue -match $GuidRegex) { $OID = $RawValue }

        if ($UPN -or $OID) {
            $AffectedUser = [pscustomobject]@{
                UPN      = $UPN
                AzureOID = $OID
            }
            break
        }
    }

    Write-Host 'Going to create the content'
    foreach ($action in $ActionList ) {
        switch ($action) {
            'generatemail' {
                $GenerateEmail = New-CIPPAlertTemplate -format 'html' -data $Data -ActionResults $ActionResults -CIPPURL $CIPPURL -Tenant $Tenant.defaultDomainName -AuditLogLink $AuditLogLink -AlertComment $AlertComment -CustomSubject $Data.CIPPCustomSubject
                $CIPPAlert = @{
                    Type         = 'email'
                    Title        = $GenerateEmail.title
                    HTMLContent  = $GenerateEmail.htmlcontent
                    TenantFilter = $TenantFilter
                }
                Write-Host 'Going to send the mail'
                Send-CIPPAlert @CIPPAlert
                Write-Host 'email should be sent'
            }
            'generatePSA' {
                $GeneratePSA = New-CIPPAlertTemplate -format 'psa' -data $Data -ActionResults $ActionResults -CIPPURL $CIPPURL -Tenant $Tenant.defaultDomainName -AuditLogLink $AuditLogLink -AlertComment $AlertComment -CustomSubject $Data.CIPPCustomSubject
                $CIPPAlert = @{
                    Type         = 'psa'
                    Title        = $GeneratePSA.title
                    HTMLContent  = $GeneratePSA.htmlcontent
                    TenantFilter = $TenantFilter
                }
                if ($AffectedUser) {
                    $CIPPAlert.AffectedUser = $AffectedUser
                }
                # Per-alert priority rides on the record rather than a function parameter, the same
                # way CustomSubject does above - this function has a second caller
                # (Push-PublicWebhookProcess) that has no alert config to pass.
                if ($Data.CIPPPsaTicketPriority) {
                    $CIPPAlert.PsaTicketPriority = $Data.CIPPPsaTicketPriority
                }
                Send-CIPPAlert @CIPPAlert
            }
            'generateWebhook' {
                $CippAlert = @{
                    Type            = 'webhook'
                    Title           = $GenerateJSON.Title
                    JSONContent     = $JsonContent
                    TenantFilter    = $TenantFilter
                    APIName         = 'Audit Log Alerts'
                    SchemaSource    = 'Audit Log Alert'
                    InvokingCommand = 'Start-AuditLogProcessingOrchestrator'
                }
                Write-Host 'Sending Webhook Content'
                Send-CIPPAlert @CippAlert
            }
        }
    }

    # Written last, and optionally handed to the caller to batch.
    #
    # It used to be written before the alerts went out, which put the silent failure in the worst
    # place: a crash between the write and the send left a row that looks complete for an alert
    # nobody ever received, and the claim row makes a retry skip the record, so it is lost without
    # trace. Writing after the send inverts that - a crash there means the alert HAS gone out and
    # only the stored copy is missing, which is visible in the UI as a row still marked Processing.
    # Nothing downstream de-duplicates: Send-CIPPAlert posts to email, webhook and PSA
    # unconditionally, and its 'table' path even keys on a fresh guid per call. This claim row is
    # the only thing standing between a retry and a second alert, which is why the claim stays
    # where it is, before any work.
    #
    # When the caller supplies a list, the row is queued rather than written, so a batch of them
    # goes out in one transaction - every row shares the tenant partition key. The caller is
    # responsible for flushing, including on failure.
    if ($null -ne $PendingAuditLogWrites) {
        $null = $PendingAuditLogWrites.Add($AuditLogRow)
    } else {
        Add-CIPPAzDataTableEntity @AuditLogTable -Entity $AuditLogRow -Force
    }
}

