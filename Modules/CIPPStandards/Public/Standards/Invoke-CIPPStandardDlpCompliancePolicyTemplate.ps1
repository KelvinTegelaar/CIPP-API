function Invoke-CIPPStandardDlpCompliancePolicyTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DlpCompliancePolicyTemplate
    .SYNOPSIS
        (Label) DLP Compliance Policy Template
    .DESCRIPTION
        (Helptext) Deploy Microsoft Purview DLP compliance policies from CIPP templates. Existing policies and rules are overwritten in place.
        (DocsDescription) Deploy Microsoft Purview DLP compliance policies from CIPP templates. If a policy or rule with the same name already exists in the tenant, it is updated in place; otherwise it is created.
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
            Deploys Data Loss Prevention policies from a standardized template library. Ensures consistent DLP coverage across tenants for sensitive data such as financial, identity, and regulated content.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"creatable":false,"name":"dlpCompliancePolicyTemplate","label":"Select DLP Compliance Policy Templates","api":{"url":"/api/ListDlpCompliancePolicyTemplates","labelField":"name","valueField":"GUID","queryKey":"ListDlpCompliancePolicyTemplates"}}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)

    $ReadOnlyProperties = @(
        'GUID', 'comments', 'RuleParams',
        'Workload', 'DistributionStatus', 'DistributionResults', 'LastStatusUpdate',
        'Enabled', 'Identity', 'Guid', 'Id', 'ImmutableId', 'IsValid',
        'WhenCreated', 'WhenChanged', 'WhenCreatedUTC', 'WhenChangedUTC',
        'CreatedBy', 'ModifiedBy', 'LastModifiedBy', 'ObjectState',
        'PolicyCategory', 'PolicyVersion', 'Type', 'DisplayName',
        'AssociatedRules', 'RuleCount'
    )

    $LocationProperties = @(
        'ExchangeLocation', 'ExchangeLocationException',
        'SharePointLocation', 'SharePointLocationException',
        'OneDriveLocation', 'OneDriveLocationException',
        'TeamsLocation', 'TeamsLocationException',
        'EndpointDlpLocation', 'EndpointDlpLocationException',
        'OnPremisesScannerDlpLocation', 'OnPremisesScannerDlpLocationException',
        'ThirdPartyAppDlpLocation', 'ThirdPartyAppDlpLocationException',
        'PowerBIDlpLocation', 'PowerBIDlpLocationException',
        'ModernGroupLocation', 'ModernGroupLocationException'
    )

    function ConvertTo-LocationValue {
        param($Value)
        if ($null -eq $Value) { return $null }
        if ($Value -is [string]) { return $Value }
        $items = @($Value) | ForEach-Object {
            if ($null -eq $_) { return }
            if ($_ -is [string]) { $_ }
            elseif ($_.Name) { $_.Name }
            elseif ($_.PrimarySmtpAddress) { $_.PrimarySmtpAddress }
            elseif ($_.DisplayName) { $_.DisplayName }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if ($items.Count -eq 0) { return $null }
        if ($items -contains 'All') { return 'All' }
        return @($items)
    }

    function ConvertTo-CleanParams {
        param($Source)
        $clean = @{}
        foreach ($prop in $Source.PSObject.Properties) {
            if ($prop.Name -in $ReadOnlyProperties) { continue }
            $val = $prop.Value
            if ($null -eq $val) { continue }
            if ($val -is [string] -and [string]::IsNullOrWhiteSpace($val)) { continue }
            if (($val -is [array] -or $val -is [System.Collections.IList]) -and @($val).Count -eq 0) { continue }
            if ($prop.Name -in $LocationProperties) {
                $normalized = ConvertTo-LocationValue -Value $val
                if ($null -eq $normalized) { continue }
                $clean[$prop.Name] = $normalized
            } else {
                $clean[$prop.Name] = $val
            }
        }
        return $clean
    }

    function ConvertTo-CleanRuleParams {
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

    try {
        $ExistingPolicies = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-DlpCompliancePolicy' -Compliance | Select-Object Name
    } catch {
        $ExistingPolicies = @()
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not list existing DLP compliance policies: $($_.Exception.Message)" -sev Warning
    }

    try {
        $ExistingRules = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-DlpComplianceRule' -Compliance | Select-Object Name, ParentPolicyName
    } catch {
        $ExistingRules = @()
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not list existing DLP compliance rules: $($_.Exception.Message)" -sev Warning
    }

    if ($Settings.remediate -eq $true) {
        foreach ($Template in @($Templates)) {
            $TemplateName = $Template.Name ?? $Template.name
            try {
                $PolicyParams = ConvertTo-CleanParams -Source $Template
                $PolicyExists = [bool]($ExistingPolicies | Where-Object { $_.Name -eq $TemplateName })

                if ($PolicyExists) {
                    $SetParams = @{} + $PolicyParams
                    $SetParams.Remove('Name')
                    $SetParams['Identity'] = $TemplateName
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-DlpCompliancePolicy' -cmdParams $SetParams -Compliance -useSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated DLP compliance policy '$TemplateName' in place" -sev Info
                } else {
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'New-DlpCompliancePolicy' -cmdParams $PolicyParams -Compliance -useSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created DLP compliance policy '$TemplateName'" -sev Info
                }

                $RuleSource = $Template.RuleParams
                if ($RuleSource) {
                    $RuleHash = ConvertTo-CleanRuleParams -Source $RuleSource
                    $RuleHash['Policy'] = $TemplateName
                    $RuleName = if ($RuleHash.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace([string]$RuleHash['Name'])) {
                        $RuleHash['Name']
                    } else {
                        "$TemplateName Rule"
                    }
                    $RuleHash['Name'] = $RuleName

                    $RuleExists = [bool]($ExistingRules | Where-Object { $_.Name -eq $RuleName -or $_.ParentPolicyName -eq $TemplateName })

                    if ($RuleExists) {
                        $SetRuleHash = @{} + $RuleHash
                        $SetRuleHash.Remove('Name')
                        $SetRuleHash.Remove('Policy')
                        $SetRuleHash['Identity'] = $RuleName
                        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-DlpComplianceRule' -cmdParams $SetRuleHash -Compliance -useSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated DLP rule '$RuleName' for policy '$TemplateName'" -sev Info
                    } else {
                        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'New-DlpComplianceRule' -cmdParams $RuleHash -Compliance -useSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created DLP rule '$RuleName' for policy '$TemplateName'" -sev Info
                    }
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to deploy DLP compliance policy '$TemplateName'. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.report -eq $true) {
        $MissingPolicies = foreach ($Template in @($Templates)) {
            $TemplateName = $Template.Name ?? $Template.name
            if (-not ($ExistingPolicies | Where-Object { $_.Name -eq $TemplateName })) { $TemplateName }
        }

        $CurrentValue = @{ MissingPolicies = $MissingPolicies ? @($MissingPolicies) : @() }
        $ExpectedValue = @{ MissingPolicies = @() }

        Set-CIPPStandardsCompareField -FieldName 'standards.DlpCompliancePolicyTemplate' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
    }
}
