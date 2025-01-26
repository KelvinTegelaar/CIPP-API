function Invoke-CIPPStandardSPDisableLegacyWorkflows {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SPDisableLegacyWorkflows
    .SYNOPSIS
        (Label) Disable Legacy Workflows
    .DESCRIPTION
        (Helptext) Disables the creation of new SharePoint 2010 and 2013 classic workflows and removes the 'Return to classic SharePoint' link on modern SharePoint list and library pages.
        (DocsDescription) Disables the creation of new SharePoint 2010 and 2013 classic workflows and removes the 'Return to classic SharePoint' link on modern SharePoint list and library pages.
    .NOTES
        CAT
            SharePoint Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-SPOTenant -DisableWorkflow2010 \$true -DisableWorkflow2013 \$true -DisableBackToClassic \$true
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/sharepoint-standards#low-impact
    #>
    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'SPDisableLegacyWorkflows'

    $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant |
    Select-Object -Property *

    $StateIsCorrect = ($CurrentState.StopNew2010Workflows -eq $true) -and
                      ($CurrentState.StopNew2013Workflows -eq $true) -and
                      ($CurrentState.DisableBackToClassic -eq $true)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Legacy Workflows are already disabled.' -Sev Info
        } else {
            $Properties = @{
                StopNew2010Workflows = $true
                StopNew2013Workflows = $true
                DisableBackToClassic = $true
            }

            try {
                Get-CIPPSPOTenant -TenantFilter $Tenant | Set-CIPPSPOTenant -Properties $Properties
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully disabled Legacy Workflows' -Sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to disable Legacy Workflows. Error: $ErrorMessage" -Sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Legacy Workflows are disabled' -Sev Info
        } else {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Legacy Workflows are enabled' -Sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SPDisableLegacyWorkflows' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
