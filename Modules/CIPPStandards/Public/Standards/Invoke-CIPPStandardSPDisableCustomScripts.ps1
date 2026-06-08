function Invoke-CIPPStandardSPDisableCustomScripts {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SPDisableCustomScripts
    .SYNOPSIS
        (Label) Disable custom scripts on SharePoint sites
    .DESCRIPTION
        (Helptext) Prevents users from running custom scripts on SharePoint and OneDrive sites. Custom scripts can modify site behaviors and bypass governance controls.
        (DocsDescription) Disables the ability to add and run custom scripts on SharePoint and OneDrive sites at the tenant level. When custom scripts are allowed, governance cannot be enforced, and the capabilities of inserted code cannot be scoped or blocked. Microsoft recommends using the SharePoint Framework instead of custom scripts.
    .NOTES
        CAT
            SharePoint Standards
        TAG
        EXECUTIVETEXT
            Blocks custom scripts from being added to SharePoint and OneDrive sites, enforcing governance controls and preventing unscoped code execution. This aligns with Microsoft's Baseline Security Mode recommendation to permanently remove the ability to add new custom scripts, directing organizations to use the SharePoint Framework instead.
        ADDEDCOMPONENT
        IMPACT
            High Impact
        ADDEDDATE
            2026-04-28
        POWERSHELLEQUIVALENT
            Set-SPOTenant -CustomScriptsRestrictMode $true
        RECOMMENDEDBY
            "CIPP"
        REQUIREDCAPABILITIES
            "SHAREPOINTWAC"
            "SHAREPOINTSTANDARD"
            "SHAREPOINTENTERPRISE"
            "SHAREPOINTENTERPRISE_EDU"
            "SHAREPOINTENTERPRISE_GOV"
            "ONEDRIVE_BASIC"
            "ONEDRIVE_ENTERPRISE"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'SPDisableCustomScripts' -TenantFilter $Tenant -Preset SharePoint

    if ($TestResult -eq $false) {
        return $true
    }

    try {
        $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the SPDisableCustomScripts state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($null -eq $CurrentState._ObjectIdentity_) {
        $ErrorDetail = $CurrentState.ErrorInfo ?? 'No tenant data returned from CSOM query'
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the SPDisableCustomScripts state for $Tenant. Error: $ErrorDetail" -Sev Error
        return
    }

    # CSOM property is CustomScriptsRestrictMode (true = scripts blocked)
    # NoScriptSite is only a PnP/SPO PowerShell parameter name, not a CSOM property
    $StateIsCorrect = ($CurrentState.CustomScriptsRestrictMode -eq $true)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Custom scripts are already disabled on SharePoint sites.' -Sev Info
        } else {
            try {
                $CurrentState | Set-CIPPSPOTenant -Properties @{ CustomScriptsRestrictMode = $true }
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully disabled custom scripts on SharePoint sites.' -Sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to disable custom scripts on SharePoint sites. Error: $ErrorMessage" -Sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Custom scripts are disabled on SharePoint sites.' -Sev Info
        } else {
            Write-StandardsAlert -message 'Custom scripts are enabled on SharePoint sites.' -object $CurrentState -tenant $Tenant -standardName 'SPDisableCustomScripts' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Custom scripts are enabled on SharePoint sites.' -Sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            SPDisableCustomScripts = $StateIsCorrect
        }
        $ExpectedValue = [PSCustomObject]@{
            SPDisableCustomScripts = $true
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.SPDisableCustomScripts' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'SPDisableCustomScripts' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
