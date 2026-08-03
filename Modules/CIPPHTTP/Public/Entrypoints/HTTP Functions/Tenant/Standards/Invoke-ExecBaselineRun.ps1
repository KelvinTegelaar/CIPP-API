function Invoke-ExecBaselineRun {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    .DESCRIPTION
        Queues a Baseline run: a full baseline run (templateId), or a single-standard
        compare/oneoff for one tenant. The run request is picked up by the V3 engine; queuing
        keeps this endpoint fast and lets the engine batch work per (tenant, standard).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $Mode = $Request.Body.mode ?? 'run'
        if ($Mode -notin @('run', 'compare', 'oneoff')) {
            throw "Unknown run mode '$Mode'. Use run, compare, or oneoff."
        }
        if ($Mode -in @('compare', 'oneoff') -and -not ($Request.Body.tenantFilter -and $Request.Body.standard)) {
            throw "Mode '$Mode' requires tenantFilter and standard."
        }
        if ($Mode -eq 'run' -and -not $Request.Body.templateId) {
            throw "Mode 'run' requires templateId."
        }

        $Table = Get-CippTable -tablename 'BaselineRunRequests'
        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey = 'RunRequest'
            RowKey       = (New-Guid).GUID
            Status       = 'Queued'
            Mode         = "$Mode"
            TenantFilter = "$($Request.Body.tenantFilter)"
            Standard     = "$($Request.Body.standard)"
            TemplateId   = "$($Request.Body.templateId)"
            RequestedBy  = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
            RequestedAt  = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
        }

        $Target = if ($Mode -eq 'run') { "baseline $($Request.Body.templateId)" } else { "$($Request.Body.standard) on $($Request.Body.tenantFilter)" }
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Queued Baseline $Mode for $Target." -Sev 'Info'
        $Results = [pscustomobject]@{ Results = "Queued $Mode for $Target. The engine processes queued runs on its next cycle." }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to queue baseline run: $($_.Exception.Message)" -Sev 'Error'
        $Results = [pscustomobject]@{ Results = "Failed to queue baseline run: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
