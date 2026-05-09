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
            {"report":false,"warn":true,"remediate":false}
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

    $ReadOnlyProperties = @(
        'GUID', 'comments', 'PolicyParams',
        'Identity', 'Guid', 'Id', 'ImmutableId', 'IsValid',
        'WhenCreated', 'WhenChanged', 'WhenCreatedUTC', 'WhenChangedUTC',
        'CreatedBy', 'ModifiedBy', 'LastModifiedBy', 'ObjectState',
        'Type', 'PublishedInPolicies', 'Disabled'
    )

    function ConvertTo-CleanParams {
        param($Source)
        $clean = @{}
        foreach ($prop in $Source.PSObject.Properties) {
            if ($prop.Name -in $ReadOnlyProperties) { continue }
            $val = $prop.Value
            if ($null -eq $val) { continue }
            if ($val -is [string] -and [string]::IsNullOrWhiteSpace($val)) { continue }
            if (($val -is [array] -or $val -is [System.Collections.IList]) -and @($val).Count -eq 0) { continue }
            $clean[$prop.Name] = $val
        }
        return $clean
    }

    function ConvertTo-CleanPolicyParams {
        param($Source)
        $clean = @{}
        foreach ($prop in $Source.PSObject.Properties) {
            $val = $prop.Value
            if ($null -eq $val) { continue }
            if ($val -is [string] -and [string]::IsNullOrWhiteSpace($val)) { continue }
            if (($val -is [array] -or $val -is [System.Collections.IList]) -and @($val).Count -eq 0) { continue }
            $clean[$prop.Name] = $val
        }
        return $clean
    }

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

    try {
        $ExistingLabels = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Label' -Compliance | Select-Object Name, DisplayName
    } catch {
        $ExistingLabels = @()
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not list existing sensitivity labels: $($_.Exception.Message)" -sev Warning
    }

    try {
        $ExistingLabelPolicies = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-LabelPolicy' -Compliance | Select-Object Name
    } catch {
        $ExistingLabelPolicies = @()
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not list existing sensitivity label policies: $($_.Exception.Message)" -sev Warning
    }

    if ($Settings.remediate -eq $true) {
        foreach ($Template in @($Templates)) {
            $TemplateName = $Template.Name ?? $Template.name
            try {
                $LabelParams = ConvertTo-CleanParams -Source $Template
                $LabelExists = [bool]($ExistingLabels | Where-Object { $_.Name -eq $TemplateName -or $_.DisplayName -eq $TemplateName })

                if ($LabelExists) {
                    $SetParams = @{} + $LabelParams
                    $SetParams.Remove('Name')
                    $SetParams['Identity'] = $TemplateName
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-Label' -cmdParams $SetParams -Compliance -useSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated sensitivity label '$TemplateName' in place" -sev Info
                } else {
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'New-Label' -cmdParams $LabelParams -Compliance -useSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created sensitivity label '$TemplateName'" -sev Info
                }

                $PolicySource = $Template.PolicyParams
                if ($PolicySource) {
                    $PolicyHash = ConvertTo-CleanPolicyParams -Source $PolicySource
                    if (-not $PolicyHash.ContainsKey('Labels') -or -not $PolicyHash['Labels']) {
                        $PolicyHash['Labels'] = @($TemplateName)
                    }
                    $PolicyName = if ($PolicyHash.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace([string]$PolicyHash['Name'])) {
                        $PolicyHash['Name']
                    } else {
                        "$TemplateName Policy"
                    }
                    $PolicyHash['Name'] = $PolicyName

                    $LabelPolicyExists = [bool]($ExistingLabelPolicies | Where-Object { $_.Name -eq $PolicyName })

                    if ($LabelPolicyExists) {
                        $SetPolicyHash = @{} + $PolicyHash
                        $SetPolicyHash.Remove('Name')
                        $SetPolicyHash['Identity'] = $PolicyName
                        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-LabelPolicy' -cmdParams $SetPolicyHash -Compliance -useSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated sensitivity label policy '$PolicyName'" -sev Info
                    } else {
                        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'New-LabelPolicy' -cmdParams $PolicyHash -Compliance -useSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created sensitivity label policy '$PolicyName'" -sev Info
                    }
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to deploy sensitivity label '$TemplateName'. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.report -eq $true) {
        $MissingLabels = foreach ($Template in @($Templates)) {
            $TemplateName = $Template.Name ?? $Template.name
            if (-not ($ExistingLabels | Where-Object { $_.Name -eq $TemplateName -or $_.DisplayName -eq $TemplateName })) { $TemplateName }
        }

        $CurrentValue = @{ MissingLabels = $MissingLabels ? @($MissingLabels) : @() }
        $ExpectedValue = @{ MissingLabels = @() }

        Set-CIPPStandardsCompareField -FieldName 'standards.SensitivityLabelTemplate' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
    }
}
