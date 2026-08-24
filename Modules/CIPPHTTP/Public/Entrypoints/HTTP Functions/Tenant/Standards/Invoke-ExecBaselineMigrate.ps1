function Invoke-ExecBaselineMigrate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Baselines.ReadWrite
    .DESCRIPTION
        Migrates classic StandardsTemplateV2 templates (standards + drift) into baselines.
        action 'preview' returns the full mapping report without writing; 'commit' migrates
        the selected templates (all when none selected). reportOnly (default true) imports
        every standard with remediation off - the report carries each standard's faithful
        V2 posture so the operator re-enables deliberately. addDetectStandards optionally
        adds the admin-drift detection standards to migrated drift templates. The V2
        templates themselves are never modified.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $Action = $Request.Body.action ?? 'preview'
        $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
        $Splat = @{
            TemplateIds        = $(if ($Request.Body.templateIds) { @($Request.Body.templateIds) } else { $null })
            ReportOnly         = $($Request.Body.reportOnly ?? $true)
            AddDetectStandards = [bool]$Request.Body.addDetectStandards
            User               = "$User"
        }
        $MigrationReport = if ($Action -eq 'commit') {
            Invoke-CIPPBaselineMigration @Splat
        } else {
            Invoke-CIPPBaselineMigration @Splat -Preview
        }

        $Summary = $MigrationReport.summary
        # The frontend colors the result bar red when the text matches error/failed/
        # exception - so those words only appear when something genuinely went wrong.
        $Message = if ($Action -eq 'commit' -and $Summary.failed -gt 0) {
            "Migrated $($Summary.migrated) template$($Summary.migrated -eq 1 ? '' : 's'), but $($Summary.failed) failed - see the list below for details."
        } elseif ($Action -eq 'commit') {
            "Migrated $($Summary.migrated) template$($Summary.migrated -eq 1 ? '' : 's') ($($Summary.upToDate) already up to date, $($Summary.skipped) skipped)."
        } else {
            "$($Summary.ready) of $($Summary.total) templates are ready to migrate ($($Summary.upToDate) already up to date, $($Summary.skipped) cannot be migrated)."
        }
        if ($Action -eq 'commit') {
            Write-LogMessage -headers $Request.Headers -API $APIName -message $Message -Sev 'Info'
        }
        $Results = [pscustomobject]@{ Results = $Message; Metadata = $MigrationReport }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Baseline migration failed: $($_.Exception.Message)" -Sev 'Error'
        $Results = [pscustomobject]@{ Results = "Baseline migration failed: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
