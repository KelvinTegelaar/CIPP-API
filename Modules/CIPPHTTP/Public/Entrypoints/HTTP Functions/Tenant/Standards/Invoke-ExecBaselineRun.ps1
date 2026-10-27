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
    $Mode = $Request.Body.mode ?? 'run'
    # The tenant selector posts its option object; a group ID or 'AllTenants' are valid
    # scopes too - the orchestrator expands them.
    $TenantFilter = $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter
    $AllTenants = $TenantFilter -in @('AllTenants', 'allTenants')
    if ($AllTenants) { $TenantFilter = $null }
    $StandardName = $Request.Body.standard
    $TemplateId = $Request.Body.templateId

    $ValidationError = if ($Mode -notin @('run', 'compare', 'oneoff')) {
        "Unknown mode '$Mode'. Use run, compare, or oneoff."
    } elseif ($Mode -eq 'oneoff' -and -not $StandardName) {
        'A oneoff run deploys a single standard: provide the standard to deploy.'
    } elseif (-not ($TenantFilter -or $TemplateId -or ($AllTenants -and $StandardName))) {
        $AllTenants ? 'A run across all tenants needs a standard or a templateId to limit what runs.' : 'Provide a tenantFilter, a templateId, or a standard with tenantFilter AllTenants to scope the run.'
    }
    if ($ValidationError) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = $ValidationError } })
    }

    try {
        # A tenant-scoped run is checked by the dispatcher; a whole-baseline run needs every assignment in the caller's scope.
        if ($TemplateId -and -not $TenantFilter) {
            $OutOfScope = @(Get-CIPPBaselineOutOfScopeAssignment -Assignments (Get-CIPPBaseline -ID $TemplateId | Select-Object -First 1).assignments)
            if ($OutOfScope.Count -gt 0) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::Forbidden; Body = @{ Results = "Your role can't run this whole baseline, because it is assigned to tenants outside your access: $($OutOfScope -join ', '). Run it on one of your tenants instead." } })
            }
        }

        # A manual run always carries the force flag: if remediation applies, we write 100%.
        # TriggeredBy carries the operator so run history reads "triggered by <user>".
        $User = $(try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { $null }) ?? 'manual'
        $Queued = Start-CIPPBaselineOrchestrator -TenantFilter $TenantFilter -StandardName $StandardName -TemplateId $TemplateId -Mode $Mode -TriggeredBy $User -Force

        $Target = $TemplateId ? "baseline $TemplateId" : ("$($StandardName ? "$StandardName on " : '')$($TenantFilter ?? 'all tenants')")
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
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
