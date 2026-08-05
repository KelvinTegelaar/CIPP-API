function Push-CIPPStandard {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param (
        $Item
    )

    Write-Information "Received queue item for $($Item.Tenant) and standard $($Item.Standard)."

    $Tenant = $Item.Tenant
    $Standard = $Item.Standard

    # FUTURE USE - ZAC
    # Grouped Conditional Access batch: deploy all of a tenant's CA templates in one sequential
    # pass. Per-template rerun checks and standard-info context are handled inside the batch
    # function, so we bypass the generic per-item dispatch below.
    # if ($Item.BatchTemplates) {
    #     $TemplateCount = @($Item.BatchTemplates).Count
    #     Write-Information "Received Conditional Access batch for $Tenant with $TemplateCount template(s)."
    #     Set-CippUserAgentContext -Source 'standard' -TemplateId $Item.TemplateId
    #     $QueuedTime = if ($Item.QueuedTime) { [int64]$Item.QueuedTime } else { 0 }
    #     try {
    #         Invoke-CIPPCATemplateBatch -Tenant $Tenant -Templates $Item.BatchTemplates -QueuedTime $QueuedTime
    #         Write-Information "Conditional Access batch completed for tenant $Tenant"
    #     } catch {
    #         Write-LogMessage -API 'Standards' -tenant $Tenant -message "Error running Conditional Access batch for tenant $Tenant - $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    #         Write-Warning "Error running Conditional Access batch for tenant $Tenant - $($_.Exception.Message)"
    #         throw $_.Exception.Message
    #     }
    #     return
    # }

    $FunctionName = 'Invoke-CIPPStandard{0}' -f $Standard

    Write-Information "We'll be running $FunctionName"

    if ($Standard -in @('IntuneTemplate', 'ConditionalAccessTemplate')) {
        $API = "$($Standard)_$($Item.TemplateId)_$($Item.Settings.TemplateList.value)"
    } else {
        $API = "$($Standard)_$($Item.TemplateId)"
    }

    $Rerun = Test-CIPPRerun -Type Standard -Tenant $Tenant -API $API -BaseTime ([int64]$Item.QueuedTime)
    if ($Rerun) {
        Write-Information 'Detected rerun. Exiting cleanly'
        return
    } else {
        Write-Information "Rerun is set to false. We'll be running $FunctionName"
    }

    $StandardInfo = @{
        Standard           = $Standard
        StandardTemplateId = $Item.TemplateId
    }
    if ($Standard -eq 'IntuneTemplate') {
        $StandardInfo.IntuneTemplateId = $Item.Settings.TemplateList.value
    }
    if ($Standard -eq 'ConditionalAccessTemplate') {
        $StandardInfo.ConditionalAccessTemplateId = $Item.Settings.TemplateList.value
    }

    if (-not (Get-Command -Name $FunctionName -Module CIPPStandards -ErrorAction SilentlyContinue)) {
        Write-LogMessage -tenant $Tenant -message "The standard $Standard was not found. This may have been deprecated or replaced with a new standard." -sev 'Warning' -API 'Standards'
        Write-Warning "Function $FunctionName not found"
        return
    }

    # Store standard info in CIPPCore module-scoped AsyncLocal storage so Write-LogMessage and
    # Set-CIPPStandardsCompareField can read it - global vars are unreliable in Azure Functions
    Set-CippStandardInfoContext -StandardInfo $StandardInfo

    # Store action source + template id for outbound User-Agent attribution
    Set-CippUserAgentContext -Source 'standard' -TemplateId $Item.TemplateId

    # ---- Standard execution telemetry ----
    $runId = [guid]::NewGuid().ToString()
    $invocationId = if ($ExecutionContext -and $ExecutionContext.InvocationId) {
        "$($ExecutionContext.InvocationId)"
    } else {
        $null
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $result = 'Unknown'
    $err = $null

    Write-Information -Tag 'CIPPStandardStart' -MessageData (@{
            Kind         = 'CIPPStandardStart'
            RunId        = $runId
            InvocationId = $invocationId
            Tenant       = $Tenant
            Standard     = $Standard
            TemplateId   = $Item.TemplateId
            API          = $API
            FunctionName = $FunctionName
        } | ConvertTo-Json -Compress)
    # -------------------------------------

    try {
        # Convert settings to JSON, replace %variables%, then convert back to object.
        #
        # Two things have to hold for that round trip to be safe. The template picker's rawData
        # snapshot is dropped first: it is a second copy of the selected template that no standard
        # reads, and being a JSON document nested inside a JSON document it needs a different amount
        # of escaping than the text around it. And because replacement runs against serialized JSON,
        # values are escaped for that context - a variable holding a logon banner that reads
        # 'property of "Contoso"' otherwise closes the string it lands in and the reparse fails.
        $SettingsForRun = Remove-CIPPStandardSettingsRawData -Settings $Item.Settings
        $SettingsJSON = $SettingsForRun | ConvertTo-Json -Depth 10 -Compress
        if ($SettingsJSON -match '%') {
            $Settings = Get-CIPPTextReplacement -TenantFilter $Item.Tenant -Text $SettingsJSON -EscapeForJson | ConvertFrom-Json
        } else {
            $Settings = $SettingsForRun
        }

        & $FunctionName -Tenant $Item.Tenant -Settings $Settings -ErrorAction Stop

        $result = 'Success'
        Write-Information "Standard $($Standard) completed for tenant $($Tenant)"
    } catch {
        $result = 'Failed'
        $err = $_.Exception.Message

        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Error running standard $($Standard) for tenant $($Tenant) - $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        Write-Warning "Error running standard $($Standard) for tenant $($Tenant) - $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
        throw $_.Exception.Message
    } finally {
        $sw.Stop()

        Write-Information -Tag 'CIPPStandardEnd' -MessageData (@{
                Kind         = 'CIPPStandardEnd'
                RunId        = $runId
                InvocationId = $invocationId
                Tenant       = $Tenant
                Standard     = $Standard
                TemplateId   = $Item.TemplateId
                API          = $API
                FunctionName = $FunctionName
                Result       = $result
                ElapsedMs    = $sw.ElapsedMilliseconds
                Error        = $err
            } | ConvertTo-Json -Compress)

        Set-CippStandardInfoContext -StandardInfo $null
    }
}
