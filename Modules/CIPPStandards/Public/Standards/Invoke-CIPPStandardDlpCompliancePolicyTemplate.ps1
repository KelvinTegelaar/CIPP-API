function Invoke-CIPPStandardDlpCompliancePolicyTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DlpCompliancePolicyTemplate
    .SYNOPSIS
        (Label) DLP Compliance Policy Template
    .DESCRIPTION
        (Helptext) Deploy Microsoft Purview DLP compliance policies from CIPP templates. Existing policies are overwritten in place.
        (DocsDescription) Deploy Microsoft Purview DLP compliance policies from CIPP templates. If a policy or rule with the same name already exists in the tenant, it is updated in place; otherwise it is created. Microsoft built-in default policies are skipped.
    .NOTES
        MULTI
            True
        CAT
            Templates
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-05-10
        EXECUTIVETEXT
            Deploys Data Loss Prevention policies from a standardized template library. Ensures consistent DLP coverage across tenants for sensitive data such as financial, identity, and regulated content.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"creatable":false,"name":"dlpCompliancePolicyTemplate","label":"Select DLP Compliance Policy Templates","api":{"url":"/api/ListDlpCompliancePolicyTemplates","labelField":"name","valueField":"GUID","queryKey":"ListDlpCompliancePolicyTemplates"}}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)

    $TemplateSelection = $Settings.dlpCompliancePolicyTemplate ?? $Settings.TemplateList ?? $Settings.'standards.DlpCompliancePolicyTemplate.TemplateIds'
    $TemplateIds = @($TemplateSelection | ForEach-Object {
            if ($_ -is [string]) { $_ } elseif ($_.value) { $_.value } else { $null }
        }) | Where-Object { $_ }

    if (-not $TemplateIds -or $TemplateIds.Count -eq 0) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No DLP compliance policy templates selected.' -sev Error
        return
    }

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'DlpCompliancePolicyTemplate' and (RowKey eq '$($TemplateIds -join "' or RowKey eq '")')"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json

    if (-not $Templates) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No DLP compliance policy templates resolved from the selected IDs.' -sev Error
        return
    }

    # Compare each template against the live policy + rules. Remediate only what actually drifts (or is
    # missing) - an in-sync policy is left untouched. After a successful remediation we re-compare so the
    # report/alert reflect the corrected state. A PendingDeletion policy can't be modified, so it is
    # surfaced as non-compliant rather than redeployed (the deploy would just fail).
    $Comparisons = foreach ($Template in @($Templates)) {
        $Comparison = Compare-CIPPDlpCompliancePolicy -TenantFilter $Tenant -Template $Template

        if ($Settings.remediate -eq $true -and $Comparison.State -in @('Missing', 'Drift')) {
            $DeployResult = Set-CIPPDlpCompliancePolicy -TenantFilter $Tenant -Template $Template -APIName 'Standards'
            if ($DeployResult -match '^(Could not deploy|Failed)') {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message $DeployResult -sev Error
                $Comparison | Add-Member -NotePropertyName DeployError -NotePropertyValue "$DeployResult" -Force
            } else {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Remediated DLP policy '$($Comparison.Name)' ($($Comparison.State)): $DeployResult" -sev Info
                $Comparison = Compare-CIPPDlpCompliancePolicy -TenantFilter $Tenant -Template $Template
            }
        }
        $Comparison
    }

    $NonCompliant = @($Comparisons | Where-Object { $_.State -ne 'InSync' })

    if ($Settings.alert -eq $true) {
        if ($NonCompliant.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All selected DLP compliance policy templates are deployed and in sync.' -sev Info
        } else {
            $Summary = $NonCompliant | ForEach-Object {
                if ($_.State -eq 'Drift') {
                    $Fields = @($_.Differences | ForEach-Object { "$($_.Scope)/$($_.Field)" }) -join ', '
                    "$($_.Name): drift in $Fields"
                } else {
                    "$($_.Name): $($_.State)"
                }
            }
            $AlertMessage = "DLP compliance policy templates not in sync: $($Summary -join '; ')"
            Write-StandardsAlert -message $AlertMessage -object @{ NonCompliantPolicies = $NonCompliant } -tenant $Tenant -standardName 'DlpCompliancePolicyTemplate' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message $AlertMessage -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        # Expose the actual drift (per policy: state + the differing fields with expected vs current
        # values) rather than just a list of missing names.
        $CurrentValue = @{ NonCompliantPolicies = $NonCompliant }
        $ExpectedValue = @{ NonCompliantPolicies = @() }

        Set-CIPPStandardsCompareField -FieldName 'standards.DlpCompliancePolicyTemplate' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DlpCompliancePolicyTemplate' -FieldValue ($NonCompliant.Count -eq 0) -StoreAs bool -Tenant $Tenant
    }
}
