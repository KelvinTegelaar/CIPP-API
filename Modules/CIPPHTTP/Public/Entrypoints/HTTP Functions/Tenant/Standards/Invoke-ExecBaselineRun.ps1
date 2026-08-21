function Invoke-ExecBaselineRun {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.BaselinesRun.ReadWrite
    .DESCRIPTION
        Starts an on-demand baseline run directly as a durable orchestration: a full baseline
        run (templateId), a tenant- or standard-scoped run, a compare (no remediation), or a
        oneoff (single standard, remediation forced on - the declarative deploy).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $Mode = $Request.Body.mode ?? 'run'
        if ($Mode -notin @('run', 'compare', 'oneoff')) {
            throw "Unknown mode '$Mode'. Use run, compare, or oneoff."
        }
        # The tenant selector posts its option object; a group ID or 'AllTenants' are valid
        # scopes too - the orchestrator expands them.
        $TenantFilter = $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter
        if ($TenantFilter -in @('AllTenants', 'allTenants')) { $TenantFilter = $null }
        $StandardName = $Request.Body.standard
        $TemplateId = $Request.Body.templateId
        if ($Mode -eq 'oneoff' -and -not ($TenantFilter -and $StandardName)) {
            throw 'A oneoff run requires tenantFilter and standard.'
        }
        if (-not ($TenantFilter -or $TemplateId)) {
            throw 'Provide a tenantFilter or a templateId to scope the run.'
        }

        # A manual run always carries the force flag: if remediation applies, we write 100%.
        # TriggeredBy carries the operator so run history reads "triggered by <user>".
        $User = $(try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { $null }) ?? 'manual'
        $Queued = Start-CIPPBaselineOrchestrator -TenantFilter $TenantFilter -StandardName $StandardName -TemplateId $TemplateId -Mode $Mode -TriggeredBy $User -Force

        $Target = $TemplateId ? "baseline $TemplateId" : ("$($StandardName ? "$StandardName on " : '')$TenantFilter")
        if ([int]$Queued -eq 0) {
            # Never claim a run started when nothing resolved - that is undiagnosable from the UI.
            Write-LogMessage -headers $Request.Headers -API $APIName -message "Baseline $Mode for $Target resolved nothing - no checks queued." -Sev 'Warning'
            $Results = [pscustomobject]@{ Results = "Nothing ran: no assigned baseline (or tenant override) resolves $Target. Check the baseline's standards, assignment, and exclusions." }
        } else {
            Write-LogMessage -headers $Request.Headers -API $APIName -message "Started baseline $Mode for $Target ($Queued checks)." -Sev 'Info'
            $Results = [pscustomobject]@{ Results = "Started the ${Mode}: $Queued check$($Queued -eq 1 ? '' : 's') queued. Results appear on the alignment page as each check completes." }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to start baseline run: $($_.Exception.Message)" -Sev 'Error'
        $Results = [pscustomobject]@{ Results = "Failed to start baseline run: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
