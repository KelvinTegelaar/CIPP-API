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
    if ($Settings.remediate -eq $true) {
        $Settings.transportRuleTemplate ? ($Settings | Add-Member -NotePropertyName 'TemplateList' -NotePropertyValue $Settings.transportRuleTemplate) : $null
        foreach ($Template in $Settings.TemplateList) {
            $Table = Get-CippTable -tablename 'templates'
            $Filter = "PartitionKey eq 'TransportTemplate' and RowKey eq '$($Template.value)'"
            $RequestParams = (Get-AzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json
            $Existing = $existingRules | Where-Object -Property Identity -EQ $RequestParams.name

            try {
                if ($Existing) {
                    if ($Settings.overwrite) {
                        $RequestParams | Add-Member -NotePropertyValue $RequestParams.name -NotePropertyName Identity
                        $GraphRequest = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-TransportRule' -cmdParams ($RequestParams | Select-Object -Property * -ExcludeProperty GUID, Comments, HasSenderOverride, ExceptIfHasSenderOverride, ExceptIfMessageContainsDataClassifications, MessageContainsDataClassifications, UseLegacyRegex) -useSystemMailbox $true
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully set transport rule for $tenant" -sev 'Info'
                    } else {
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Skipping transport rule for $tenant as it already exists" -sev 'Info'
                    }
                } else {
                    $GraphRequest = New-ExoRequest -tenantid $Tenant -cmdlet 'New-TransportRule' -cmdParams ($RequestParams | Select-Object -Property * -ExcludeProperty GUID, Comments, HasSenderOverride, ExceptIfHasSenderOverride, ExceptIfMessageContainsDataClassifications, MessageContainsDataClassifications, UseLegacyRegex) -useSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully created transport rule for $tenant" -sev 'Info'
                }

                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created transport rule for $($tenantFilter)" -sev 'Debug'
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not create transport rule for $($tenantFilter): $ErrorMessage" -sev 'Error'
            }
        }
    }
    if ($Settings.report -eq $true) {
        $rules = $Settings.transportRuleTemplate.JSON | ConvertFrom-Json -Depth 10
        $MissingRules = foreach ($rule in $rules) {
            $CheckExististing = $existingRules | Where-Object -Property identity -EQ $rule.displayname
            if (!$CheckExististing) {
                $rule.displayname
            }
        }

        $CurrentValue = @{
            DeployedTransportRules = $existingRules.DisplayName | Where-Object { $rules.displayname -contains $_ } | Sort-Object
            MissingTransportRules  = $MissingRules ? @($MissingRules) : @()
        }
        $ExpectedValue = @{
            DeployedTransportRules = $rules.displayname | Sort-Object
            MissingTransportRules  = @()
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.TransportRuleTemplate' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
