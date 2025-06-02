function Invoke-CIPPStandardSafeLinksTemplatePolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SafeLinksTemplatePolicy
    .SYNOPSIS
        (Label) SafeLinks Policy Template
    .DESCRIPTION
        (Helptext) This applies selected SafeLinks policy templates to the tenant, creating or updating as needed
        (DocsDescription) This applies selected SafeLinks policy templates to the tenant, creating or updating as needed
    .NOTES
        CAT
            Defender Standards
        TAG
            "CIS"
            "mdo_safelinksforemail"
            "mdo_safelinksforOfficeApps"
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"name":"standards.SafeLinksTemplatePolicy.TemplateIds","label":"SafeLinks Templates","loadingMessage":"Loading templates...","api":{"url":"/api/ListSafeLinksPolicyTemplates","labelField":"name","valueField":"GUID","queryKey":"ListSafeLinksPolicyTemplates"}}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-04-29
        POWERSHELLEQUIVALENT
            New-SafeLinksPolicy, Set-SafeLinksPolicy, New-SafeLinksRule, Set-SafeLinksRule
        RECOMMENDEDBY
            "CIS"
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/defender-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'SafeLinksPolicy'

    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Processing SafeLinks template with settings: $($Settings | ConvertTo-Json -Compress)" -sev Debug

    # Verify tenant has necessary license
    $ServicePlans = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus?$select=servicePlans' -tenantid $Tenant
    $ServicePlans = $ServicePlans.servicePlans.servicePlanName
    $MDOLicensed = $ServicePlans -contains 'ATP_ENTERPRISE'

    if (-not $MDOLicensed) {
        if ($Settings.remediate -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Failed to apply SafeLinks templates: Tenant does not have Microsoft Defender for Office 365 license' -sev Error
        }

        if ($Settings.alert -eq $true) {
            Write-StandardsAlert -message 'SafeLinks templates could not be applied: Tenant does not have Microsoft Defender for Office 365 license' -object $MDOLicensed -tenant $Tenant -standardName 'SafeLinksTemplatePolicy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SafeLinks templates could not be applied: Tenant does not have Microsoft Defender for Office 365 license' -sev Info
        }

        if ($Settings.report -eq $true) {
            Add-CIPPBPAField -FieldName 'SafeLinksTemplatePolicy' -FieldValue $false -StoreAs bool -Tenant $tenant
            Set-CIPPStandardsCompareField -FieldName 'standards.SafeLinksTemplatePolicy' -FieldValue $false -Tenant $Tenant
        }

        return
    }

    # Handle remediation
    If ($Settings.remediate -eq $true) {
        # Normalize the template list property based on what's passed - support multiple possible formats
        if ($Settings.'standards.SafeLinksTemplatePolicy.TemplateIds') {
            $Settings | Add-Member -NotePropertyName 'TemplateList' -NotePropertyValue $Settings.'standards.SafeLinksTemplatePolicy.TemplateIds' -Force
        } elseif ($Settings.TemplateIds) {
            $Settings | Add-Member -NotePropertyName 'TemplateList' -NotePropertyValue $Settings.TemplateIds -Force
        }

        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Template list after normalization: $($Settings.TemplateList | ConvertTo-Json -Compress)" -sev Debug

        if (-not $Settings.TemplateList) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to apply SafeLinks templates: No templates selected" -sev Error
            return
        }

        # Initialize overall results tracking
        $OverallSuccess = $true
        $TemplateResults = @{}

        # Process each template
        foreach ($Template in $Settings.TemplateList) {
            $TemplateId = $Template.value
            Write-Host "Working on template ID: $TemplateId"
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Processing SafeLinks template with ID: $TemplateId" -sev Info

            # Get the template by GUID
            $Table = Get-CippTable -tablename 'templates'
            $Filter = "PartitionKey eq 'SafeLinksTemplate' and RowKey eq '$TemplateId'"
            $Template = Get-CIPPAzDataTableEntity @Table -Filter $Filter

            if (-not $Template) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to apply SafeLinks template: Template with ID $TemplateId not found" -sev Error
                $TemplateResults[$TemplateId] = @{
                    Success = $false
                    Message = "Template with ID $TemplateId not found"
                }
                $OverallSuccess = $false
                continue
            }

            # Parse the template JSON
            try {
                $PolicyConfig = $Template.JSON | ConvertFrom-Json -ErrorAction Stop

                # Helper function to process array fields
                function Process-ArrayField {
                    param (
                        [Parameter(Mandatory = $false)]
                        $Field
                    )

                    if ($null -eq $Field) { return @() }

                    # If already an array, process each item
                    if ($Field -is [array]) {
                        $result = @()
                        foreach ($item in $Field) {
                            if ($item -is [string]) {
                                $result += $item
                            }
                            elseif ($item -is [hashtable] -or $item -is [PSCustomObject]) {
                                # Extract value from object
                                if ($null -ne $item.value) {
                                    $result += $item.value
                                }
                                elseif ($null -ne $item.userPrincipalName) {
                                    $result += $item.userPrincipalName
                                }
                                elseif ($null -ne $item.id) {
                                    $result += $item.id
                                }
                                else {
                                    $result += $item.ToString()
                                }
                            }
                            else {
                                $result += $item.ToString()
                            }
                        }
                        return $result
                    }

                    # If it's a single object
                    if ($Field -is [hashtable] -or $Field -is [PSCustomObject]) {
                        if ($null -ne $Field.value) { return @($Field.value) }
                        if ($null -ne $Field.userPrincipalName) { return @($Field.userPrincipalName) }
                        if ($null -ne $Field.id) { return @($Field.id) }
                    }

                    # If it's a string, return as an array with one item
                    if ($Field -is [string]) {
                        return @($Field)
                    }

                    return @($Field)
                }

                # Extract policy name from template
                $PolicyName = $PolicyConfig.PolicyName ?? $PolicyConfig.Name
                $RuleName = $PolicyConfig.RuleName ?? $PolicyName

                # Process arrays in the template
                $DoNotRewriteUrls = Process-ArrayField -Field $PolicyConfig.DoNotRewriteUrls
                $SentTo = Process-ArrayField -Field $PolicyConfig.SentTo
                $SentToMemberOf = Process-ArrayField -Field $PolicyConfig.SentToMemberOf
                $RecipientDomainIs = Process-ArrayField -Field $PolicyConfig.RecipientDomainIs
                $ExceptIfSentTo = Process-ArrayField -Field $PolicyConfig.ExceptIfSentTo
                $ExceptIfSentToMemberOf = Process-ArrayField -Field $PolicyConfig.ExceptIfSentToMemberOf
                $ExceptIfRecipientDomainIs = Process-ArrayField -Field $PolicyConfig.ExceptIfRecipientDomainIs

                # Check if policy and rule exist
                $ExistingPoliciesParam = @{
                    tenantid         = $Tenant
                    cmdlet           = 'Get-SafeLinksPolicy'
                    useSystemMailbox = $true
                }

                $ExistingPolicies = New-ExoRequest @ExistingPoliciesParam
                $PolicyExists = $ExistingPolicies | Where-Object { $_.Name -eq $PolicyName }

                $ExistingRulesParam = @{
                    tenantid         = $Tenant
                    cmdlet           = 'Get-SafeLinksRule'
                    useSystemMailbox = $true
                }

                $ExistingRules = New-ExoRequest @ExistingRulesParam
                $RuleExists = $ExistingRules | Where-Object { $_.Name -eq $RuleName }

                # Build policy parameters
                $policyParams = @{}

                # Only add parameters that are explicitly provided in the template
                if ($null -ne $PolicyConfig.EnableSafeLinksForEmail) { $policyParams.Add('EnableSafeLinksForEmail', $PolicyConfig.EnableSafeLinksForEmail) }
                if ($null -ne $PolicyConfig.EnableSafeLinksForTeams) { $policyParams.Add('EnableSafeLinksForTeams', $PolicyConfig.EnableSafeLinksForTeams) }
                if ($null -ne $PolicyConfig.EnableSafeLinksForOffice) { $policyParams.Add('EnableSafeLinksForOffice', $PolicyConfig.EnableSafeLinksForOffice) }
                if ($null -ne $PolicyConfig.TrackClicks) { $policyParams.Add('TrackClicks', $PolicyConfig.TrackClicks) }
                if ($null -ne $PolicyConfig.AllowClickThrough) { $policyParams.Add('AllowClickThrough', $PolicyConfig.AllowClickThrough) }
                if ($null -ne $PolicyConfig.ScanUrls) { $policyParams.Add('ScanUrls', $PolicyConfig.ScanUrls) }
                if ($null -ne $PolicyConfig.EnableForInternalSenders) { $policyParams.Add('EnableForInternalSenders', $PolicyConfig.EnableForInternalSenders) }
                if ($null -ne $PolicyConfig.DeliverMessageAfterScan) { $policyParams.Add('DeliverMessageAfterScan', $PolicyConfig.DeliverMessageAfterScan) }
                if ($null -ne $PolicyConfig.DisableUrlRewrite) { $policyParams.Add('DisableUrlRewrite', $PolicyConfig.DisableUrlRewrite) }
                if ($null -ne $DoNotRewriteUrls -and $DoNotRewriteUrls.Count -gt 0) { $policyParams.Add('DoNotRewriteUrls', $DoNotRewriteUrls) }
                if ($null -ne $PolicyConfig.AdminDisplayName) { $policyParams.Add('AdminDisplayName', $PolicyConfig.AdminDisplayName) }
                if ($null -ne $PolicyConfig.CustomNotificationText) { $policyParams.Add('CustomNotificationText', $PolicyConfig.CustomNotificationText) }
                if ($null -ne $PolicyConfig.EnableOrganizationBranding) { $policyParams.Add('EnableOrganizationBranding', $PolicyConfig.EnableOrganizationBranding) }

                # Build rule parameters
                $ruleParams = @{}

                # Only add parameters that are explicitly provided
                if ($null -ne $PolicyConfig.Priority) { $ruleParams.Add('Priority', $PolicyConfig.Priority) }
                if ($null -ne $PolicyConfig.Description) { $ruleParams.Add('Comments', $PolicyConfig.Description) }
                if ($null -ne $SentTo -and $SentTo.Count -gt 0) { $ruleParams.Add('SentTo', $SentTo) }
                if ($null -ne $SentToMemberOf -and $SentToMemberOf.Count -gt 0) { $ruleParams.Add('SentToMemberOf', $SentToMemberOf) }
                if ($null -ne $RecipientDomainIs -and $RecipientDomainIs.Count -gt 0) { $ruleParams.Add('RecipientDomainIs', $RecipientDomainIs) }
                if ($null -ne $ExceptIfSentTo -and $ExceptIfSentTo.Count -gt 0) { $ruleParams.Add('ExceptIfSentTo', $ExceptIfSentTo) }
                if ($null -ne $ExceptIfSentToMemberOf -and $ExceptIfSentToMemberOf.Count -gt 0) { $ruleParams.Add('ExceptIfSentToMemberOf', $ExceptIfSentToMemberOf) }
                if ($null -ne $ExceptIfRecipientDomainIs -and $ExceptIfRecipientDomainIs.Count -gt 0) { $ruleParams.Add('ExceptIfRecipientDomainIs', $ExceptIfRecipientDomainIs) }

                $ActionsTaken = @()

                try {
                    if ($PolicyExists) {
                        # Update existing policy
                        $policyParams.Add('Identity', $PolicyName)

                        $ExoPolicyRequestParam = @{
                            tenantid         = $Tenant
                            cmdlet           = 'Set-SafeLinksPolicy'
                            cmdParams        = $policyParams
                            useSystemMailbox = $true
                        }

                        $null = New-ExoRequest @ExoPolicyRequestParam
                        $ActionsTaken += "Updated SafeLinks policy '$PolicyName'"
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated SafeLinks policy '$PolicyName'" -sev 'Info'
                    }
                    else {
                        # Create new policy
                        $policyParams.Add('Name', $PolicyName)

                        $ExoPolicyRequestParam = @{
                            tenantid         = $Tenant
                            cmdlet           = 'New-SafeLinksPolicy'
                            cmdParams        = $policyParams
                            useSystemMailbox = $true
                        }

                        $null = New-ExoRequest @ExoPolicyRequestParam
                        $ActionsTaken += "Created new SafeLinks policy '$PolicyName'"
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created new SafeLinks policy '$PolicyName'" -sev 'Info'
                    }

                    if ($RuleExists) {
                        # Update existing rule
                        $ruleParams.Add('Identity', $RuleName)

                        $ExoRuleRequestParam = @{
                            tenantid         = $Tenant
                            cmdlet           = 'Set-SafeLinksRule'
                            cmdParams        = $ruleParams
                            useSystemMailbox = $true
                        }

                        $null = New-ExoRequest @ExoRuleRequestParam
                        $ActionsTaken += "Updated SafeLinks rule '$RuleName'"
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated SafeLinks rule '$RuleName'" -sev 'Info'
                    }
                    else {
                        # Create new rule
                        $ruleParams.Add('Name', $RuleName)
                        $ruleParams.Add('SafeLinksPolicy', $PolicyName)

                        $ExoRuleRequestParam = @{
                            tenantid         = $Tenant
                            cmdlet           = 'New-SafeLinksRule'
                            cmdParams        = $ruleParams
                            useSystemMailbox = $true
                        }

                        $null = New-ExoRequest @ExoRuleRequestParam
                        $ActionsTaken += "Created new SafeLinks rule '$RuleName'"
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created new SafeLinks rule '$RuleName'" -sev 'Info'
                    }

                    # If State is specified in the template, enable or disable the rule
                    if ($null -ne $PolicyConfig.State) {
                        $Enabled = $PolicyConfig.State -eq "Enabled"
                        $EnableCmdlet = $Enabled ? 'Enable-SafeLinksRule' : 'Disable-SafeLinksRule'
                        $EnableRequestParam = @{
                            tenantid         = $Tenant
                            cmdlet           = $EnableCmdlet
                            cmdParams        = @{
                                Identity = $RuleName
                            }
                            useSystemMailbox = $true
                        }

                        $null = New-ExoRequest @EnableRequestParam
                        $StateMsg = $Enabled ? "enabled" : "disabled"
                        $ActionsTaken += "Rule $StateMsg"
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "SafeLinks rule '$RuleName' $StateMsg" -sev 'Info'
                    }

                    $TemplateResults[$TemplateId] = @{
                        Success = $true
                        ActionsTaken = $ActionsTaken
                        TemplateName = $PolicyConfig.Name
                        PolicyName = $PolicyName
                        RuleName = $RuleName
                    }

                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully applied SafeLinks template '$($PolicyConfig.Name)'" -sev 'Info'
                }
                catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    $TemplateResults[$TemplateId] = @{
                        Success = $false
                        Message = $ErrorMessage
                        TemplateName = $PolicyConfig.Name
                    }
                    $OverallSuccess = $false

                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to apply SafeLinks template '$($PolicyConfig.Name)': $ErrorMessage" -sev 'Error'
                }
            }
            catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                $TemplateResults[$TemplateId] = @{
                    Success = $false
                    Message = $ErrorMessage
                }
                $OverallSuccess = $false

                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to process template with ID $($TemplateId): $ErrorMessage" -sev 'Error'
            }
        }

        # Report on overall results
        if ($OverallSuccess) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully applied all SafeLinks templates" -sev 'Info'
        } else {
            $SuccessCount = ($TemplateResults.Values | Where-Object { $_.Success -eq $true }).Count
            $TotalCount = $Settings.TemplateList.Count
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Applied $SuccessCount out of $TotalCount SafeLinks templates" -sev 'Info'
        }
    }

    # Handle alert mode
    if ($Settings.alert -eq $true) {
        # Normalize the template list property based on what's passed
        if ($Settings.'standards.SafeLinksTemplatePolicy.TemplateIds') {
            $Settings | Add-Member -NotePropertyName 'TemplateList' -NotePropertyValue $Settings.'standards.SafeLinksTemplatePolicy.TemplateIds' -Force
        } elseif ($Settings.TemplateIds) {
            $Settings | Add-Member -NotePropertyName 'TemplateList' -NotePropertyValue $Settings.TemplateIds -Force
        }

        if (-not $Settings.TemplateList) {
            Write-StandardsAlert -message "SafeLinks templates could not be checked: No templates selected" -object $null -tenant $Tenant -standardName 'SafeLinksTemplatePolicy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "SafeLinks templates could not be checked: No templates selected" -sev Info
            return
        }

        $AllTemplatesApplied = $true
        $AlertMessages = @()

        foreach ($Template in $Settings.TemplateList) {
            $TemplateId = $Template.value

            # Get the template
            $Table = Get-CippTable -tablename 'templates'
            $Filter = "PartitionKey eq 'SafeLinksTemplate' and RowKey eq '$TemplateId'"
            $Template = Get-CIPPAzDataTableEntity @Table -Filter $Filter

            if (-not $Template) {
                $AlertMessages += "Template with ID $TemplateId not found"
                $AllTemplatesApplied = $false
                continue
            }

            try {
                $PolicyConfig = $Template.JSON | ConvertFrom-Json -ErrorAction Stop
                $PolicyName = $PolicyConfig.PolicyName ?? $PolicyConfig.Name
                $RuleName = $PolicyConfig.RuleName ?? $PolicyName

                # Check if policy and rule exist
                $ExistingPoliciesParam = @{
                    tenantid         = $Tenant
                    cmdlet           = 'Get-SafeLinksPolicy'
                    useSystemMailbox = $true
                }

                $ExistingPolicies = New-ExoRequest @ExistingPoliciesParam
                $PolicyExists = $ExistingPolicies | Where-Object { $_.Name -eq $PolicyName }

                $ExistingRulesParam = @{
                    tenantid         = $Tenant
                    cmdlet           = 'Get-SafeLinksRule'
                    useSystemMailbox = $true
                }

                $ExistingRules = New-ExoRequest @ExistingRulesParam
                $RuleExists = $ExistingRules | Where-Object { $_.Name -eq $RuleName }

                if (-not $PolicyExists -or -not $RuleExists) {
                    $AllTemplatesApplied = $false
                    $Status = "SafeLinks template '$($PolicyConfig.Name)' is not applied"

                    if (-not $PolicyExists) {
                        $Status += " - policy '$PolicyName' does not exist"
                    }

                    if (-not $RuleExists) {
                        $Status += " - rule '$RuleName' does not exist"
                    }

                    $AlertMessages += $Status
                }
            }
            catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                $AlertMessages += "Failed to check template with ID $($TemplateId): $ErrorMessage"
                $AllTemplatesApplied = $false
            }
        }

        if ($AllTemplatesApplied) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "All SafeLinks templates are correctly applied" -sev 'Info'
        }
        else {
            $AlertMessage = "One or more SafeLinks templates are not correctly applied: " + ($AlertMessages -join " | ")
            Write-StandardsAlert -message $AlertMessage -object @{
                Templates = $Settings.TemplateList
                Issues = $AlertMessages
            } -tenant $Tenant -standardName 'SafeLinksTemplatePolicy' -standardId $Settings.standardId

            Write-LogMessage -API 'Standards' -tenant $Tenant -message $AlertMessage -sev 'Info'
        }
    }

    # Handle report mode
    if ($Settings.report -eq $true) {
        # Normalize the template list property based on what's passed
        if ($Settings.'standards.SafeLinksTemplatePolicy.TemplateIds') {
            $Settings | Add-Member -NotePropertyName 'TemplateList' -NotePropertyValue $Settings.'standards.SafeLinksTemplatePolicy.TemplateIds' -Force
        } elseif ($Settings.TemplateIds) {
            $Settings | Add-Member -NotePropertyName 'TemplateList' -NotePropertyValue $Settings.TemplateIds -Force
        }

        if (-not $Settings.TemplateList) {
            Add-CIPPBPAField -FieldName 'SafeLinksTemplatePolicy' -FieldValue $false -StoreAs bool -Tenant $tenant
            Set-CIPPStandardsCompareField -FieldName 'standards.SafeLinksTemplatePolicy' -FieldValue "No templates selected" -Tenant $Tenant
            return
        }

        $AllTemplatesApplied = $true
        $ReportResults = @{}

        foreach ($Template in $Settings.TemplateList) {
            $TemplateId = $Template.value

            # Get the template
            $Table = Get-CippTable -tablename 'templates'
            $Filter = "PartitionKey eq 'SafeLinksTemplate' and RowKey eq '$TemplateId'"
            $Template = Get-CIPPAzDataTableEntity @Table -Filter $Filter

            if (-not $Template) {
                $ReportResults[$TemplateId] = @{
                    Success = $false
                    Message = "Template not found"
                }
                $AllTemplatesApplied = $false
                continue
            }

            try {
                $PolicyConfig = $Template.JSON | ConvertFrom-Json -ErrorAction Stop
                $PolicyName = $PolicyConfig.PolicyName ?? $PolicyConfig.Name
                $RuleName = $PolicyConfig.RuleName ?? $PolicyName

                # Check if policy and rule exist
                $ExistingPoliciesParam = @{
                    tenantid         = $Tenant
                    cmdlet           = 'Get-SafeLinksPolicy'
                    useSystemMailbox = $true
                }

                $ExistingPolicies = New-ExoRequest @ExistingPoliciesParam
                $PolicyExists = $ExistingPolicies | Where-Object { $_.Name -eq $PolicyName }

                $ExistingRulesParam = @{
                    tenantid         = $Tenant
                    cmdlet           = 'Get-SafeLinksRule'
                    useSystemMailbox = $true
                }

                $ExistingRules = New-ExoRequest @ExistingRulesParam
                $RuleExists = $ExistingRules | Where-Object { $_.Name -eq $RuleName }

                $ReportResults[$TemplateId] = @{
                    Success = ($PolicyExists -and $RuleExists)
                    TemplateName = $PolicyConfig.Name
                    PolicyName = $PolicyName
                    RuleName = $RuleName
                    PolicyExists = $PolicyExists
                    RuleExists = $RuleExists
                }

                if (-not $PolicyExists -or -not $RuleExists) {
                    $AllTemplatesApplied = $false
                }
            }
            catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                $ReportResults[$TemplateId] = @{
                    Success = $false
                    Message = $ErrorMessage
                }
                $AllTemplatesApplied = $false
            }
        }

        Add-CIPPBPAField -FieldName 'SafeLinksTemplatePolicy' -FieldValue $AllTemplatesApplied -StoreAs bool -Tenant $tenant

        if ($AllTemplatesApplied) {
            Set-CIPPStandardsCompareField -FieldName 'standards.SafeLinksTemplatePolicy' -FieldValue $true -Tenant $Tenant
        }
        else {
            Set-CIPPStandardsCompareField -FieldName 'standards.SafeLinksTemplatePolicy' -FieldValue @{
                TemplateResults = $ReportResults
                ProcessedTemplates = $Settings.TemplateList.Count
                SuccessfulTemplates = ($ReportResults.Values | Where-Object { $_.Success -eq $true }).Count
            } -Tenant $Tenant
        }
    }
}
