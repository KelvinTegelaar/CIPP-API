function Invoke-CIPPStandardTenantDefaultTimezone {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TenantDefaultTimezone
    .SYNOPSIS
        (Label) Set Default Timezone for Tenant
    .DESCRIPTION
        (Helptext) Sets the default timezone for the tenant. This will be used for all new users and sites.
        (DocsDescription) Sets the default timezone for the tenant. This will be used for all new users and sites.
    .NOTES
        CAT
            SharePoint Standards
        TAG
        ADDEDCOMPONENT
            {"type":"TimezoneSelect","name":"standards.TenantDefaultTimezone.Timezone","label":"Timezone"}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-04-20
        POWERSHELLEQUIVALENT
            Update-MgBetaAdminSharePointSetting
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/sharepoint-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'TenantDefaultTimezone'

    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true
    $ExpectedTimezone = $Settings.Timezone.value
    $StateIsCorrect = $CurrentState.tenantDefaultTimezone -eq $ExpectedTimezone

    # Input validation
    if (([string]::IsNullOrWhiteSpace($Settings.Timezone) -or $Settings.Timezone -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'TenantDefaultTimezone: Invalid Timezone parameter set' -sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Tenant Default Timezone is already set to $ExpectedTimezone" -sev Info
        } else {
            try {
                New-GraphPostRequest -tenantid $Tenant -uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type PATCH -Body "{`"tenantDefaultTimezone`": `"$ExpectedTimezone`"}" -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully updated Tenant Default Timezone to $ExpectedTimezone" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Tenant Default Timezone. Error: $ErrorMessage" -sev Error
            }
        }

    }
    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Tenant Default Timezone is set to $ExpectedTimezone." -sev Info
        } else {
            Write-StandardsAlert -message 'Tenant Default Timezone is not set to the desired value.' -object $CurrentState -tenant $Tenant -standardName 'TenantDefaultTimezone' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Tenant Default Timezone is not set to the desired value.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TenantDefaultTimezone' -FieldValue $CurrentState.tenantDefaultTimezone -StoreAs string -Tenant $Tenant
        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState | Select-Object tenantDefaultTimezone
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TenantDefaultTimezone' -FieldValue $FieldValue -Tenant $Tenant
    }
}
