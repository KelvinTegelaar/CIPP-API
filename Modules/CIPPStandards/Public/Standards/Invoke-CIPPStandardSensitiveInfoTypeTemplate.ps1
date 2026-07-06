function Invoke-CIPPStandardSensitiveInfoTypeTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SensitiveInfoTypeTemplate
    .SYNOPSIS
        (Label) Sensitive Information Type Template
    .DESCRIPTION
        (Helptext) Deploy custom Microsoft Purview Sensitive Information Types from CIPP templates. Existing custom SITs with the same name are overwritten in place.
        (DocsDescription) Deploy custom Sensitive Information Types from CIPP templates. Supports the simple-mode template (Name + Pattern + Confidence — backend synthesizes the rule pack XML) and the advanced-mode template (caller-supplied FileDataBase64 rule pack). If a SIT with the same name already exists, its rule pack is updated in place. Built-in Microsoft SITs are skipped.
    .NOTES
        MULTI
            True
        CAT
            Templates
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        IMPACT
            Low Impact
        ADDEDDATE
            2026-05-10
        EXECUTIVETEXT
            Deploys custom Sensitive Information Types so DLP policies can detect organization-specific identifiers — employee IDs, project codenames, internal account numbers — across tenants consistently.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"creatable":false,"name":"sensitiveInfoTypeTemplate","label":"Select Sensitive Information Type Templates","api":{"url":"/api/ListSensitiveInfoTypeTemplates","labelField":"name","valueField":"GUID","queryKey":"ListSensitiveInfoTypeTemplates"}}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)

    $TemplateSelection = $Settings.sensitiveInfoTypeTemplate ?? $Settings.TemplateList ?? $Settings.'standards.SensitiveInfoTypeTemplate.TemplateIds'
    $TemplateIds = @($TemplateSelection | ForEach-Object {
            if ($_ -is [string]) { $_ } elseif ($_.value) { $_.value } else { $null }
        }) | Where-Object { $_ }

    if (-not $TemplateIds -or $TemplateIds.Count -eq 0) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No sensitive information type templates selected.' -sev Error
        return
    }

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'SensitiveInfoTypeTemplate' and (RowKey eq '$($TemplateIds -join "' or RowKey eq '")')"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json

    if (-not $Templates) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No sensitive information type templates resolved from the selected IDs.' -sev Error
        return
    }

    # Compare each template against the live SIT's rule pack and remediate only what drifts (or is
    # missing). After a successful remediation, re-compare so the report/alert reflect the fixed state.
    $Comparisons = foreach ($Template in @($Templates)) {
        $Comparison = Compare-CIPPSensitiveInfoType -TenantFilter $Tenant -Template $Template

        if ($Settings.remediate -eq $true -and $Comparison.State -in @('Missing', 'Drift')) {
            $DeployResult = Set-CIPPSensitiveInfoType -TenantFilter $Tenant -Template $Template -APIName 'Standards'
            if ($DeployResult -match '^(Created|Updated)') {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Remediated SIT '$($Comparison.Name)' ($($Comparison.State)): $DeployResult" -sev Info
                $Comparison = Compare-CIPPSensitiveInfoType -TenantFilter $Tenant -Template $Template
            } else {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message $DeployResult -sev Error
                $Comparison | Add-Member -NotePropertyName DeployError -NotePropertyValue "$DeployResult" -Force
            }
        }
        $Comparison
    }

    # Non-compliant when the SIT is missing, drifted, or the template is invalid. Built-in and in-sync
    # SITs are compliant.
    $NonCompliant = @($Comparisons | Where-Object { $_.State -in @('Missing', 'Drift', 'Invalid') })

    if ($Settings.alert -eq $true) {
        if ($NonCompliant.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All selected Sensitive Information Type templates are deployed and in sync.' -sev Info
        } else {
            $Summary = $NonCompliant | ForEach-Object {
                if ($_.State -eq 'Drift') {
                    $Fields = @($_.Differences | ForEach-Object { "$($_.Scope)/$($_.Field)" }) -join ', '
                    "$($_.Name): drift in $Fields"
                } else {
                    "$($_.Name): $($_.State)"
                }
            }
            $AlertMessage = "Sensitive Information Type templates not in sync: $($Summary -join '; ')"
            Write-StandardsAlert -message $AlertMessage -object @{ NonCompliantSensitiveInfoTypes = $NonCompliant } -tenant $Tenant -standardName 'SensitiveInfoTypeTemplate' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message $AlertMessage -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        # Expose the actual drift (per SIT: state + the differing fields with expected vs current values).
        $CurrentValue = @{ NonCompliantSensitiveInfoTypes = $NonCompliant }
        $ExpectedValue = @{ NonCompliantSensitiveInfoTypes = @() }

        Set-CIPPStandardsCompareField -FieldName 'standards.SensitiveInfoTypeTemplate' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'SensitiveInfoTypeTemplate' -FieldValue ($NonCompliant.Count -eq 0) -StoreAs bool -Tenant $Tenant
    }
}
