function Invoke-CIPPStandardSensitivityLabelTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SensitivityLabelTemplate
    .SYNOPSIS
        (Label) Sensitivity Label Template
    .DESCRIPTION
        (Helptext) Deploy Microsoft Purview sensitivity labels from CIPP templates. Existing labels and label policies are overwritten in place.
        (DocsDescription) Deploy Microsoft Purview sensitivity labels from CIPP templates. If a label or label policy with the same name already exists, it is updated in place; otherwise it is created.
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
            Deploys sensitivity labels for classification and protection of files, emails, and Microsoft 365 group content. Ensures consistent classification taxonomy and encryption settings across tenants.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"creatable":false,"name":"sensitivityLabelTemplate","label":"Select Sensitivity Label Templates","api":{"url":"/api/ListSensitivityLabelTemplates","labelField":"name","valueField":"GUID","queryKey":"ListSensitivityLabelTemplates"}}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)

    $TemplateSelection = $Settings.sensitivityLabelTemplate ?? $Settings.TemplateList ?? $Settings.'standards.SensitivityLabelTemplate.TemplateIds'
    $TemplateIds = @($TemplateSelection | ForEach-Object {
            if ($_ -is [string]) { $_ } elseif ($_.value) { $_.value } else { $null }
        }) | Where-Object { $_ }

    if (-not $TemplateIds -or $TemplateIds.Count -eq 0) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No sensitivity label templates selected.' -sev Error
        return
    }

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'SensitivityLabelTemplate' and (RowKey eq '$($TemplateIds -join "' or RowKey eq '")')"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json

    if (-not $Templates) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No sensitivity label templates resolved from the selected IDs.' -sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        foreach ($Template in @($Templates)) {
            $null = Set-CIPPSensitivityLabel -TenantFilter $Tenant -Template $Template -APIName 'Standards'
        }
    }

    $ExistingLabels = try {
        New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Label' -Compliance | Select-Object Name, DisplayName
    } catch { @() }

    $MissingLabels = @(foreach ($Template in @($Templates)) {
            $TemplateName = $Template.Name ?? $Template.name
            if (-not ($ExistingLabels | Where-Object { $_.Name -eq $TemplateName -or $_.DisplayName -eq $TemplateName })) { $TemplateName }
        })

    if ($Settings.alert -eq $true) {
        if ($MissingLabels.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All selected sensitivity label templates are deployed.' -sev Info
        } else {
            $AlertMessage = "Sensitivity labels not deployed in tenant: $($MissingLabels -join ', ')"
            Write-StandardsAlert -message $AlertMessage -object @{ MissingLabels = $MissingLabels } -tenant $Tenant -standardName 'SensitivityLabelTemplate' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message $AlertMessage -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{ MissingLabels = $MissingLabels }
        $ExpectedValue = @{ MissingLabels = @() }

        Set-CIPPStandardsCompareField -FieldName 'standards.SensitivityLabelTemplate' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'SensitivityLabelTemplate' -FieldValue ($MissingLabels.Count -eq 0) -StoreAs bool -Tenant $Tenant
    }
}
