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

    if ($Settings.remediate -eq $true) {
        foreach ($Template in @($Templates)) {
            $null = Set-CIPPDlpCompliancePolicy -TenantFilter $Tenant -Template $Template -APIName 'Standards'
        }
    }

    # Determine which templated policies are present in the tenant for alert/report modes
    $ExistingPolicyNames = try {
        @(New-ExoRequest -tenantid $Tenant -cmdlet 'Get-DlpCompliancePolicy' -Compliance | Select-Object -ExpandProperty Name)
    } catch { @() }

    $MissingPolicies = @(foreach ($Template in @($Templates)) {
            $TemplateName = $Template.Name ?? $Template.name
            if ($ExistingPolicyNames -notcontains $TemplateName) { $TemplateName }
        })

    if ($Settings.alert -eq $true) {
        if ($MissingPolicies.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All selected DLP compliance policy templates are deployed.' -sev Info
        } else {
            $AlertMessage = "DLP compliance policies not deployed in tenant: $($MissingPolicies -join ', ')"
            Write-StandardsAlert -message $AlertMessage -object @{ MissingPolicies = $MissingPolicies } -tenant $Tenant -standardName 'DlpCompliancePolicyTemplate' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message $AlertMessage -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{ MissingPolicies = $MissingPolicies }
        $ExpectedValue = @{ MissingPolicies = @() }

        Set-CIPPStandardsCompareField -FieldName 'standards.DlpCompliancePolicyTemplate' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DlpCompliancePolicyTemplate' -FieldValue ($MissingPolicies.Count -eq 0) -StoreAs bool -Tenant $Tenant
    }
}
