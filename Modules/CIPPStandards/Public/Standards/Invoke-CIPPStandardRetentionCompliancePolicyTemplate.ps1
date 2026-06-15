function Invoke-CIPPStandardRetentionCompliancePolicyTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) RetentionCompliancePolicyTemplate
    .SYNOPSIS
        (Label) Retention Compliance Policy Template
    .DESCRIPTION
        (Helptext) Deploy Microsoft Purview retention compliance policies from CIPP templates. Existing policies and rules are overwritten in place.
        (DocsDescription) Deploy Microsoft Purview retention compliance policies from CIPP templates. If a policy or rule with the same name already exists in the tenant, it is updated in place; otherwise it is created. Uses the application token to bypass GDAP delegated-identity restrictions on retention cmdlets.
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
            Deploys retention policies that govern how long content is preserved in Exchange, SharePoint, OneDrive, and Teams. Enforces consistent compliance retention across tenants for regulatory and legal hold needs.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"creatable":false,"name":"retentionCompliancePolicyTemplate","label":"Select Retention Compliance Policy Templates","api":{"url":"/api/ListRetentionCompliancePolicyTemplates","labelField":"name","valueField":"GUID","queryKey":"ListRetentionCompliancePolicyTemplates"}}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)

    $TemplateSelection = $Settings.retentionCompliancePolicyTemplate ?? $Settings.TemplateList ?? $Settings.'standards.RetentionCompliancePolicyTemplate.TemplateIds'
    $TemplateIds = @($TemplateSelection | ForEach-Object {
            if ($_ -is [string]) { $_ } elseif ($_.value) { $_.value } else { $null }
        }) | Where-Object { $_ }

    if (-not $TemplateIds -or $TemplateIds.Count -eq 0) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No retention compliance policy templates selected.' -sev Error
        return
    }

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'RetentionCompliancePolicyTemplate' and (RowKey eq '$($TemplateIds -join "' or RowKey eq '")')"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json

    if (-not $Templates) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No retention compliance policy templates resolved from the selected IDs.' -sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        foreach ($Template in @($Templates)) {
            $null = Set-CIPPRetentionCompliancePolicy -TenantFilter $Tenant -Template $Template -APIName 'Standards'
        }
    }

    $ExistingPolicyNames = try {
        @(New-ExoRequest -tenantid $Tenant -cmdlet 'Get-RetentionCompliancePolicy' -Compliance -AsApp | Select-Object -ExpandProperty Name)
    } catch { @() }

    $MissingPolicies = @(foreach ($Template in @($Templates)) {
            $TemplateName = $Template.Name ?? $Template.name
            if ($ExistingPolicyNames -notcontains $TemplateName) { $TemplateName }
        })

    if ($Settings.alert -eq $true) {
        if ($MissingPolicies.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All selected retention compliance policy templates are deployed.' -sev Info
        } else {
            $AlertMessage = "Retention compliance policies not deployed in tenant: $($MissingPolicies -join ', ')"
            Write-StandardsAlert -message $AlertMessage -object @{ MissingPolicies = $MissingPolicies } -tenant $Tenant -standardName 'RetentionCompliancePolicyTemplate' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message $AlertMessage -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{ MissingPolicies = $MissingPolicies }
        $ExpectedValue = @{ MissingPolicies = @() }

        Set-CIPPStandardsCompareField -FieldName 'standards.RetentionCompliancePolicyTemplate' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'RetentionCompliancePolicyTemplate' -FieldValue ($MissingPolicies.Count -eq 0) -StoreAs bool -Tenant $Tenant
    }
}
