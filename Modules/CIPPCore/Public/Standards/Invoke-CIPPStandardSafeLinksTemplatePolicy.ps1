function Invoke-CIPPStandardSafeLinksTemplatePolicy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SafeLinksTemplatePolicy
    .SYNOPSIS
        (Label) SafeLinks Policy Template
    .DESCRIPTION
        (Helptext) Deploy and manage SafeLinks policy templates to protect against malicious URLs in emails and Office documents.
        (DocsDescription) Deploy and manage SafeLinks policy templates to protect against malicious URLs in emails and Office documents.
    .NOTES
        CAT
            Templates
        MULTIPLE
            False
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-04-29
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"creatable":false,"name":"standards.SafeLinksTemplatePolicy.TemplateIds","label":"Select SafeLinks Policy Templates","api":{"url":"/api/ListSafeLinksPolicyTemplates","labelField":"TemplateName","valueField":"GUID","queryKey":"ListSafeLinksPolicyTemplates"}}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'SafeLinksTemplatePolicy' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Processing SafeLinks template with settings: $($Settings | ConvertTo-Json -Compress)" -sev Debug

    # Verify tenant has necessary license
    if (-not (Test-MDOLicense -Tenant $Tenant -Settings $Settings)) {
        return
    }

    # Normalize template list property
    $TemplateList = Get-NormalizedTemplateList -Settings $Settings
    if (-not $TemplateList) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "No templates selected for SafeLinks policy deployment" -sev Error
        return
    }

    # Handle different modes
    switch ($true) {
        ($Settings.remediate -eq $true) {
            Invoke-SafeLinksRemediation -Tenant $Tenant -TemplateList $TemplateList -Settings $Settings
        }
        ($Settings.alert -eq $true) {
            Invoke-SafeLinksAlert -Tenant $Tenant -TemplateList $TemplateList -Settings $Settings
        }
        ($Settings.report -eq $true) {
            Invoke-SafeLinksReport -Tenant $Tenant -TemplateList $TemplateList -Settings $Settings
        }
    }
}

function Test-MDOLicense {
    param($Tenant, $Settings)

    $ServicePlans = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus?$select=servicePlans' -tenantid $Tenant
    $ServicePlans = $ServicePlans.servicePlans.servicePlanName
    $MDOLicensed = $ServicePlans -contains 'ATP_ENTERPRISE'

    if (-not $MDOLicensed) {
        $Message = 'Tenant does not have Microsoft Defender for Office 365 license'

        if ($Settings.remediate -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to apply SafeLinks templates: $Message" -sev Error
        }

        if ($Settings.alert -eq $true) {
            Write-StandardsAlert -message "SafeLinks templates could not be applied: $Message" -object $MDOLicensed -tenant $Tenant -standardName 'SafeLinksTemplatePolicy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "SafeLinks templates could not be applied: $Message" -sev Info
        }

        if ($Settings.report -eq $true) {
            Add-CIPPBPAField -FieldName 'SafeLinksTemplatePolicy' -FieldValue $false -StoreAs bool -Tenant $Tenant
            Set-CIPPStandardsCompareField -FieldName 'standards.SafeLinksTemplatePolicy' -FieldValue $false -Tenant $Tenant
        }

        return $false
    }

    return $true
}

function Get-NormalizedTemplateList {
    param($Settings)

    if ($Settings.'standards.SafeLinksTemplatePolicy.TemplateIds') {
        return $Settings.'standards.SafeLinksTemplatePolicy.TemplateIds'
    }
    elseif ($Settings.TemplateIds) {
        return $Settings.TemplateIds
    }

    return $null
}

function Get-SafeLinksTemplateFromStorage {
    param($TemplateId)

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'SafeLinksTemplate' and RowKey eq '$TemplateId'"
    $Template = Get-CIPPAzDataTableEntity @Table -Filter $Filter

    if (-not $Template) {
        throw "Template with ID $TemplateId not found"
    }

    return $Template.JSON | ConvertFrom-Json -ErrorAction Stop
}

function ConvertTo-SafeArray {
    param($Field)

    if ($null -eq $Field) { return @() }

    $ResultList = [System.Collections.Generic.List[string]]::new()

    if ($Field -is [array]) {
        foreach ($item in $Field) {
            if ($item -is [string]) {
                $ResultList.Add($item)
            }
            elseif ($item.value) {
                $ResultList.Add($item.value)
            }
            elseif ($item.userPrincipalName) {
                $ResultList.Add($item.userPrincipalName)
            }
            elseif ($item.id) {
                $ResultList.Add($item.id)
            }
            else {
                $ResultList.Add($item.ToString())
            }
        }
        return $ResultList.ToArray()
    }

    if ($Field -is [hashtable] -or $Field -is [PSCustomObject]) {
        if ($Field.value) {
            $ResultList.Add($Field.value)
            return $ResultList.ToArray()
        }
        if ($Field.userPrincipalName) {
            $ResultList.Add($Field.userPrincipalName)
            return $ResultList.ToArray()
        }
        if ($Field.id) {
            $ResultList.Add($Field.id)
            return $ResultList.ToArray()
        }
    }

    if ($Field -is [string]) {
        $ResultList.Add($Field)
        return $ResultList.ToArray()
    }

    $ResultList.Add($Field.ToString())
    return $ResultList.ToArray()
}

function Get-ExistingSafeLinksObjects {
    param($Tenant, $PolicyName, $RuleName)

    $PolicyExists = $null
    $RuleExists = $null

    try {
        $ExistingPolicies = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeLinksPolicy' -useSystemMailbox $true
        $PolicyExists = $ExistingPolicies | Where-Object { $_.Name -eq $PolicyName }
    }
    catch {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to retrieve existing policies: $($_.Exception.Message)" -sev Warning
    }

    try {
        $ExistingRules = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-SafeLinksRule' -useSystemMailbox $true
        $RuleExists = $ExistingRules | Where-Object { $_.Name -eq $RuleName }
    }
    catch {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to retrieve existing rules: $($_.Exception.Message)" -sev Warning
    }

    return @{
        PolicyExists = $PolicyExists
        RuleExists = $RuleExists
    }
}

function New-SafeLinksPolicyParameters {
    param($Template)

    $PolicyMappings = @{
        'EnableSafeLinksForEmail' = 'EnableSafeLinksForEmail'
        'EnableSafeLinksForTeams' = 'EnableSafeLinksForTeams'
        'EnableSafeLinksForOffice' = 'EnableSafeLinksForOffice'
        'TrackClicks' = 'TrackClicks'
        'AllowClickThrough' = 'AllowClickThrough'
        'ScanUrls' = 'ScanUrls'
        'EnableForInternalSenders' = 'EnableForInternalSenders'
        'DeliverMessageAfterScan' = 'DeliverMessageAfterScan'
        'DisableUrlRewrite' = 'DisableUrlRewrite'
        'AdminDisplayName' = 'AdminDisplayName'
        'CustomNotificationText' = 'CustomNotificationText'
        'EnableOrganizationBranding' = 'EnableOrganizationBranding'
    }

    $PolicyParams = @{}

    foreach ($templateKey in $PolicyMappings.Keys) {
        if ($null -ne $Template.$templateKey) {
            $PolicyParams[$PolicyMappings[$templateKey]] = $Template.$templateKey
        }
    }

    $DoNotRewriteUrls = ConvertTo-SafeArray -Field $Template.DoNotRewriteUrls
    if ($DoNotRewriteUrls.Count -gt 0) {
        $PolicyParams['DoNotRewriteUrls'] = $DoNotRewriteUrls
    }

    return $PolicyParams
}

function New-SafeLinksRuleParameters {
    param($Template)

    $RuleParams = @{}

    # Basic rule parameters
    if ($null -ne $Template.Priority) { $RuleParams['Priority'] = $Template.Priority }
    if ($null -ne $Template.Description) { $RuleParams['Comments'] = $Template.Description }
    if ($null -ne $Template.TemplateDescription) { $RuleParams['Comments'] = $Template.TemplateDescription }

    # Array-based rule parameters
    $ArrayMappings = @{
        'SentTo' = ConvertTo-SafeArray -Field $Template.SentTo
        'SentToMemberOf' = ConvertTo-SafeArray -Field $Template.SentToMemberOf
        'RecipientDomainIs' = ConvertTo-SafeArray -Field $Template.RecipientDomainIs
        'ExceptIfSentTo' = ConvertTo-SafeArray -Field $Template.ExceptIfSentTo
        'ExceptIfSentToMemberOf' = ConvertTo-SafeArray -Field $Template.ExceptIfSentToMemberOf
        'ExceptIfRecipientDomainIs' = ConvertTo-SafeArray -Field $Template.ExceptIfRecipientDomainIs
    }

    foreach ($paramName in $ArrayMappings.Keys) {
        if ($ArrayMappings[$paramName].Count -gt 0) {
            $RuleParams[$paramName] = $ArrayMappings[$paramName]
        }
    }

    return $RuleParams
}

function Set-SafeLinksRuleState {
    param($Tenant, $RuleName, $State)

    if ($null -eq $State) { return }

    $IsEnabled = switch ($State) {
        "Enabled" { $true }
        "Disabled" { $false }
        $true { $true }
        $false { $false }
        default { $null }
    }

    if ($null -ne $IsEnabled) {
        $Cmdlet = $IsEnabled ? 'Enable-SafeLinksRule' : 'Disable-SafeLinksRule'
        $null = New-ExoRequest -tenantid $Tenant -cmdlet $Cmdlet -cmdParams @{ Identity = $RuleName } -useSystemMailbox $true
        return $IsEnabled ? "enabled" : "disabled"
    }

    return $null
}

function Invoke-SafeLinksRemediation {
    param($Tenant, $TemplateList, $Settings)

    $OverallSuccess = $true
    $TemplateResults = @{}

    foreach ($TemplateItem in $TemplateList) {
        $TemplateId = $TemplateItem.value

        try {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Processing SafeLinks template with ID: $TemplateId" -sev Info

            # Get template from storage
            $Template = Get-SafeLinksTemplateFromStorage -TemplateId $TemplateId

            $PolicyName = $Template.PolicyName ?? $Template.Name
            $RuleName = $Template.RuleName ?? "$($PolicyName)_Rule"

            # Check existing objects
            $ExistingObjects = Get-ExistingSafeLinksObjects -Tenant $Tenant -PolicyName $PolicyName -RuleName $RuleName

            $ActionsTaken = [System.Collections.Generic.List[string]]::new()

            # Process Policy
            $PolicyParams = New-SafeLinksPolicyParameters -Template $Template

            if ($ExistingObjects.PolicyExists) {
                # Update existing policy to keep it in line
                $PolicyParams['Identity'] = $PolicyName
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SafeLinksPolicy' -cmdParams $PolicyParams -useSystemMailbox $true
                $ActionsTaken.Add("Updated SafeLinks policy '$PolicyName'")
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated SafeLinks policy '$PolicyName'" -sev Info
            }
            else {
                # Create new policy
                $PolicyParams['Name'] = $PolicyName
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'New-SafeLinksPolicy' -cmdParams $PolicyParams -useSystemMailbox $true
                $ActionsTaken.Add("Created new SafeLinks policy '$PolicyName'")
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created new SafeLinks policy '$PolicyName'" -sev Info
            }

            # Process Rule
            $RuleParams = New-SafeLinksRuleParameters -Template $Template

            if ($ExistingObjects.RuleExists) {
                # Update existing rule to keep it in line
                $RuleParams['Identity'] = $RuleName
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-SafeLinksRule' -cmdParams $RuleParams -useSystemMailbox $true
                $ActionsTaken.Add("Updated SafeLinks rule '$RuleName'")
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated SafeLinks rule '$RuleName'" -sev Info
            }
            else {
                # Create new rule
                $RuleParams['Name'] = $RuleName
                $RuleParams['SafeLinksPolicy'] = $PolicyName
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'New-SafeLinksRule' -cmdParams $RuleParams -useSystemMailbox $true
                $ActionsTaken.Add("Created new SafeLinks rule '$RuleName'")
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created new SafeLinks rule '$RuleName'" -sev Info
            }

            # Set rule state
            $StateResult = Set-SafeLinksRuleState -Tenant $Tenant -RuleName $RuleName -State $Template.State
            if ($StateResult) {
                $ActionsTaken.Add("Rule $StateResult")
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "SafeLinks rule '$RuleName' $StateResult" -sev Info
            }

            $TemplateResults[$TemplateId] = @{
                Success = $true
                ActionsTaken = $ActionsTaken.ToArray()
                TemplateName = $Template.TemplateName ?? $Template.Name
                PolicyName = $PolicyName
                RuleName = $RuleName
            }

            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully applied SafeLinks template '$($Template.TemplateName ?? $Template.Name)'" -sev Info
        }
        catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            $TemplateResults[$TemplateId] = @{
                Success = $false
                Message = $ErrorMessage
                TemplateName = $Template.TemplateName ?? $Template.Name ?? "Unknown"
            }
            $OverallSuccess = $false

            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to apply SafeLinks template ID $TemplateId : $ErrorMessage" -sev Error
        }
    }

    # Report overall results
    if ($OverallSuccess) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully applied all SafeLinks templates" -sev Info
    }
    else {
        $SuccessCount = ($TemplateResults.Values | Where-Object { $_.Success -eq $true }).Count
        $TotalCount = $TemplateList.Count
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Applied $SuccessCount out of $TotalCount SafeLinks templates" -sev Info
    }
}

function Invoke-SafeLinksAlert {
    param($Tenant, $TemplateList, $Settings)

    $AllTemplatesApplied = $true
    $AlertMessages = [System.Collections.Generic.List[string]]::new()

    foreach ($TemplateItem in $TemplateList) {
        $TemplateId = $TemplateItem.value

        try {
            $Template = Get-SafeLinksTemplateFromStorage -TemplateId $TemplateId
            $PolicyName = $Template.PolicyName ?? $Template.Name
            $RuleName = $Template.RuleName ?? "$($PolicyName)_Rule"

            $ExistingObjects = Get-ExistingSafeLinksObjects -Tenant $Tenant -PolicyName $PolicyName -RuleName $RuleName

            if (-not $ExistingObjects.PolicyExists -or -not $ExistingObjects.RuleExists) {
                $AllTemplatesApplied = $false
                $Status = "SafeLinks template '$($Template.TemplateName ?? $Template.Name)' is not applied"

                if (-not $ExistingObjects.PolicyExists) {
                    $Status = "$Status - policy '$PolicyName' does not exist"
                }

                if (-not $ExistingObjects.RuleExists) {
                    $Status = "$Status - rule '$RuleName' does not exist"
                }

                $AlertMessages.Add($Status)
            }
        }
        catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            $AlertMessages.Add("Failed to check template with ID $TemplateId : $ErrorMessage")
            $AllTemplatesApplied = $false
        }
    }

    if ($AllTemplatesApplied) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "All SafeLinks templates are correctly applied" -sev Info
    }
    else {
        $AlertMessage = "One or more SafeLinks templates are not correctly applied: " + ($AlertMessages.ToArray() -join " | ")
        Write-StandardsAlert -message $AlertMessage -object @{
            Templates = $TemplateList
            Issues = $AlertMessages.ToArray()
        } -tenant $Tenant -standardName 'SafeLinksTemplatePolicy' -standardId $Settings.standardId

        Write-LogMessage -API 'Standards' -tenant $Tenant -message $AlertMessage -sev Info
    }
}

function Invoke-SafeLinksReport {
    param($Tenant, $TemplateList, $Settings)

    $AllTemplatesApplied = $true
    $ReportResults = @{}

    foreach ($TemplateItem in $TemplateList) {
        $TemplateId = $TemplateItem.value

        try {
            $Template = Get-SafeLinksTemplateFromStorage -TemplateId $TemplateId
            $PolicyName = $Template.PolicyName ?? $Template.Name
            $RuleName = $Template.RuleName ?? "$($PolicyName)_Rule"

            $ExistingObjects = Get-ExistingSafeLinksObjects -Tenant $Tenant -PolicyName $PolicyName -RuleName $RuleName

            $ReportResults[$TemplateId] = @{
                Success = ($ExistingObjects.PolicyExists -and $ExistingObjects.RuleExists)
                TemplateName = $Template.TemplateName ?? $Template.Name
                PolicyName = $PolicyName
                RuleName = $RuleName
                PolicyExists = [bool]$ExistingObjects.PolicyExists
                RuleExists = [bool]$ExistingObjects.RuleExists
            }

            if (-not $ExistingObjects.PolicyExists -or -not $ExistingObjects.RuleExists) {
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

    Add-CIPPBPAField -FieldName 'SafeLinksTemplatePolicy' -FieldValue $AllTemplatesApplied -StoreAs bool -Tenant $Tenant

    if ($AllTemplatesApplied) {
        Set-CIPPStandardsCompareField -FieldName 'standards.SafeLinksTemplatePolicy' -FieldValue $true -Tenant $Tenant
    }
    else {
        Set-CIPPStandardsCompareField -FieldName 'standards.SafeLinksTemplatePolicy' -FieldValue @{
            TemplateResults = $ReportResults
            ProcessedTemplates = $TemplateList.Count
            SuccessfulTemplates = ($ReportResults.Values | Where-Object { $_.Success -eq $true }).Count
        } -Tenant $Tenant
    }
}
