function Invoke-CIPPStandardConditionalAccessTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) ConditionalAccessTemplate
    .SYNOPSIS
        (Label) Conditional Access Template
    .DESCRIPTION
        (Helptext) Manage conditional access policies for better security.
        (DocsDescription) Manage conditional access policies for better security.
    .NOTES
        CAT
            Templates
        MULTIPLE
            True
        DISABLEDFEATURES
            {"report":true,"warn":true,"remediate":false}
        IMPACT
            High Impact
        ADDEDDATE
            2023-12-30
        ADDEDCOMPONENT
            {"type":"autoComplete","name":"TemplateList","multiple":false,"label":"Select Conditional Access Template","api":{"url":"/api/ListCATemplates","labelField":"displayName","valueField":"GUID","queryKey":"ListCATemplates"}}
            {"name":"state","label":"What state should we deploy this template in?","type":"radio","options":[{"value":"donotchange","label":"Do not change state"},{"value":"Enabled","label":"Set to enabled"},{"value":"Disabled","label":"Set to disabled"},{"value":"enabledForReportingButNotEnforced","label":"Set to report only"}]}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'ConditionalAccess'
    $TestResult = Test-CIPPStandardLicense -StandardName 'ConditionalAccessTemplate' -TenantFilter $Tenant -RequiredCapabilities @('AAD_PREMIUM', 'AAD_PREMIUM_P2')

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    if ($Settings.remediate -eq $true) {
        $AllCAPolicies = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies?$top=999' -tenantid $Tenant
        foreach ($Setting in $Settings) {
            try {
                $Table = Get-CippTable -tablename 'templates'
                $Filter = "PartitionKey eq 'CATemplate' and RowKey eq '$($Setting.TemplateList.value)'"
                $JSONObj = (Get-CippAzDataTableEntity @Table -Filter $Filter).JSON
                $null = New-CIPPCAPolicy -replacePattern 'displayName' -TenantFilter $tenant -state $Setting.state -RawJSON $JSONObj -Overwrite $true -APIName $APIName -Headers $Request.Headers -DisableSD $Setting.DisableSD
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update conditional access rule $($JSONObj.displayName). Error: $ErrorMessage" -sev 'Error'
            }
        }
    }
    if ($Settings.report -eq $true) {
        $Policies = $Settings.TemplateList.JSON | ConvertFrom-Json -Depth 10
        #check if all groups.displayName are in the existingGroups, if not $fieldvalue should contain all missing groups, else it should be true.
        $MissingPolicies = foreach ($policy in $Policies) {
            $CheckExististing = $AllCAPolicies | Where-Object -Property displayName -EQ $policy.displayname
            if (!$CheckExististing) {
                $policy.displayname
            }
        }
        if ($MissingPolicies.Count -eq 0) {
            $fieldValue = $true
        } else {
            $fieldValue = $MissingPolicies -join ', '
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.ConditionalAccessTemplate' -FieldValue $fieldValue -Tenant $Tenant
    }
}
