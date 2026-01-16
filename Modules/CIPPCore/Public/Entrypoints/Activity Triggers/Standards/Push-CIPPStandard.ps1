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
    $FunctionName = 'Invoke-CIPPStandard{0}' -f $Standard

    Write-Information "We'll be running $FunctionName"

    if ($Standard -in @('IntuneTemplate', 'ConditionalAccessTemplate')) {
        $API = "$($Standard)_$($Item.TemplateId)_$($Item.Settings.TemplateList.value)"
    } else {
        $API = "$($Standard)_$($Item.TemplateId)"
    }

    $Rerun = Test-CIPPRerun -Type Standard -Tenant $Tenant -API $API
    if ($Rerun) {
        Write-Information 'Detected rerun. Exiting cleanly'
        exit 0
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

    # Initialize AsyncLocal storage for thread-safe per-invocation context
    if (-not $script:CippStandardInfoStorage) {
        $script:CippStandardInfoStorage = [System.Threading.AsyncLocal[object]]::new()
    }
    $script:CippStandardInfoStorage.Value = $StandardInfo

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
        # Convert settings to JSON, replace %variables%, then convert back to object
        $SettingsJSON = $Item.Settings | ConvertTo-Json -Depth 10 -Compress
        if ($SettingsJSON -match '%') {
            $Settings = Get-CIPPTextReplacement -TenantFilter $Item.Tenant -Text $SettingsJSON | ConvertFrom-Json
        } else {
            $Settings = $Item.Settings
        }

        # Prepare telemetry metadata for standard execution
        $metadata = @{
            Standard     = $Standard
            Tenant       = $Tenant
            TemplateId   = $Item.TemplateId
            FunctionName = $FunctionName
            TriggerType  = 'Standard'
        }

        if ($Standard -eq 'IntuneTemplate' -and $Item.Settings.TemplateList.value) {
            $metadata['IntuneTemplateId'] = $Item.Settings.TemplateList.value
        }
        if ($Standard -eq 'ConditionalAccessTemplate' -and $Item.Settings.TemplateList.value) {
            $metadata['CATemplateId'] = $Item.Settings.TemplateList.value
        }

        Measure-CippTask -TaskName $Standard -EventName 'CIPP.StandardCompleted' -Metadata $metadata -Script {
            & $FunctionName -Tenant $Item.Tenant -Settings $Settings -ErrorAction Stop
        }

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

        if ($script:CippStandardInfoStorage) {
            $script:CippStandardInfoStorage.Value = $null
        }
    }
}
