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
    $Table = Get-CippTable -tablename 'templates'

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.
    $AllCAPolicies = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies?$top=999' -tenantid $Tenant

    if ($Settings.remediate -eq $true) {
        foreach ($Setting in $Settings) {
            try {
                $Filter = "PartitionKey eq 'CATemplate' and RowKey eq '$($Setting.TemplateList.value)'"
                $JSONObj = (Get-CippAzDataTableEntity @Table -Filter $Filter).JSON
                $null = New-CIPPCAPolicy -replacePattern 'displayName' -TenantFilter $tenant -state $Setting.state -RawJSON $JSONObj -Overwrite $true -APIName $APIName -Headers $Request.Headers -DisableSD $Setting.DisableSD
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update conditional access rule $($JSONObj.displayName). Error: $ErrorMessage" -sev 'Error'
            }
        }
    }
    if ($Settings.report -eq $true -or $Settings.remediate -eq $true) {
        Write-Host 'REPORT: Checking if all policies are present in the tenant.'
        Write-Host "REPORT: Templates in policy: $($Settings.TemplateList.label)"
        $Filter = "PartitionKey eq 'CATemplate'"
        $Policies = (Get-CippAzDataTableEntity @Table -Filter $Filter | Where-Object RowKey -In $Settings.TemplateList.value).JSON | ConvertFrom-Json -Depth 10
        Write-Host "REPORT: Found $($Policies.Count) policies in the template."
        #check if all groups.displayName are in the existingGroups, if not $fieldvalue should contain all missing groups, else it should be true.
        $MissingPolicies = foreach ($Setting in $Settings.TemplateList) {
            Write-Host "REPORT: Checking if policy $($Setting.displayname) exists in the tenant."
            $policy = $Policies | Where-Object { $_.displayName -eq $Setting.label }
            Write-Host "REPORT: Policy data is: $($policy | ConvertTo-Json -Depth 10)"
            $CheckExististing = $AllCAPolicies | Where-Object -Property displayName -EQ $Setting.displayname
            if (!$CheckExististing) {
                Write-Host "REPORT: Policy $($Setting.value) with does not exist in the tenant."
                Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($Setting.value)" -FieldValue "Policy $($Setting.label) is missing from this tenant." -Tenant $Tenant
            } else {
                $Compare = Compare-CIPPIntuneObject -ReferenceObject $policy -compareObject $CheckExististing
            }
        }
        Write-Host "REPORT: Found $($MissingPolicies.Count) policies that are missing in the tenant."

        Write-Host "REPORT: The following policies are missing: $fieldValue"
        Write-Host "REPORT: Setting field value to $fieldValue"
    }
}
