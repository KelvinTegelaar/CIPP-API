function Invoke-CIPPStandardTransportRuleTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TransportRuleTemplate
    .SYNOPSIS
        (Label) Transport Rule Template
    .DESCRIPTION
        (Helptext) Deploy transport rules to manage email flow.
        (DocsDescription) Deploy transport rules to manage email flow.
    .NOTES
        CAT
            Templates
        DISABLEDFEATURES
            {"report":true,"warn":true,"remediate":false}
        IMPACT
            Medium Impact
        ADDEDDATE
            2023-12-30
        EXECUTIVETEXT
            Deploys standardized email flow rules that automatically manage how emails are processed, filtered, and routed within the organization. These templates ensure consistent email security policies, compliance requirements, and business rules are applied across all email communications.
        ADDEDCOMPONENT
            {"type":"autoComplete","name":"transportRuleTemplate","label":"Select Transport Rule Template","api":{"url":"/api/ListTransportRulesTemplates","labelField":"name","valueField":"GUID","queryKey":"ListTransportRulesTemplates"}}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'TransportRuleTemplate' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    $existingRules = New-ExoRequest -ErrorAction SilentlyContinue -tenantid $Tenant -cmdlet 'Get-TransportRule' -useSystemMailbox $true
    $Table = Get-CippTable -tablename 'templates'
    $TemplateList = @($Settings.transportRuleTemplate) | Where-Object { $_ -and $_.value }
    $ResolvedRules = foreach ($Template in $TemplateList) {
        $TemplateId = $Template.value
        $Filter = "PartitionKey eq 'TransportTemplate' and RowKey eq '$TemplateId'"
        $TemplateEntity = Get-AzDataTableEntity @Table -Filter $Filter

        if (-not $TemplateEntity -or [string]::IsNullOrWhiteSpace($TemplateEntity.JSON)) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to find transport rule template $TemplateId." -sev 'Error'
            continue
        }

        try {
            $TemplateEntity.JSON | ConvertFrom-Json -Depth 10
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to parse transport rule template $TemplateId $ErrorMessage" -sev 'Error'
        }
    }

    $ExistingRuleNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Rule in @($existingRules)) {
        if (-not [string]::IsNullOrWhiteSpace($Rule.Identity)) {
            [void]$ExistingRuleNames.Add($Rule.Identity)
        }
        if (-not [string]::IsNullOrWhiteSpace($Rule.DisplayName)) {
            [void]$ExistingRuleNames.Add($Rule.DisplayName)
        }
    }

    if ($Settings.remediate -eq $true) {
        foreach ($RequestParams in $ResolvedRules) {
            $Existing = $ExistingRuleNames.Contains($RequestParams.name)

            try {
                if ($Existing) {
                    if ($Settings.overwrite) {
                        $RequestParams | Add-Member -NotePropertyValue $RequestParams.name -NotePropertyName Identity
                        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-TransportRule' -cmdParams ($RequestParams | Select-Object -Property * -ExcludeProperty GUID, Comments, HasSenderOverride, ExceptIfHasSenderOverride, ExceptIfMessageContainsDataClassifications, MessageContainsDataClassifications, UseLegacyRegex) -useSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully set transport rule for $tenant" -sev 'Info'
                    } else {
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Skipping transport rule for $tenant as it already exists" -sev 'Info'
                    }
                } else {
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'New-TransportRule' -cmdParams ($RequestParams | Select-Object -Property * -ExcludeProperty GUID, Comments, HasSenderOverride, ExceptIfHasSenderOverride, ExceptIfMessageContainsDataClassifications, MessageContainsDataClassifications, UseLegacyRegex) -useSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully created transport rule for $tenant" -sev 'Info'
                    [void]$ExistingRuleNames.Add($RequestParams.name)
                }

                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created transport rule for $Tenant" -sev 'Debug'
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not create transport rule for $Tenant $ErrorMessage" -sev 'Error'
            }
        }
    }
    if ($Settings.report -eq $true) {
        $RuleNames = @(foreach ($rule in $ResolvedRules) {
                $rule.name
            }) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        $MissingRules = foreach ($RuleName in $RuleNames) {
            if (-not $ExistingRuleNames.Contains($RuleName)) {
                $RuleName
            }
        }

        $CurrentValue = @{
            DeployedTransportRules = $RuleNames | Where-Object { $ExistingRuleNames.Contains($_) } | Sort-Object -Unique
            MissingTransportRules  = $MissingRules ? @($MissingRules) : @()
        }
        $ExpectedValue = @{
            DeployedTransportRules = $RuleNames | Sort-Object -Unique
            MissingTransportRules  = @()
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.TransportRuleTemplate' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
