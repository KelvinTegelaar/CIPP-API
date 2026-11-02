function Invoke-CIPPBaselineDlpCompliancePolicyTemplate {
    <#
    .SYNOPSIS
        DlpCompliancePolicyTemplate executor: deploys the instance's DLP policy template.
    .DESCRIPTION
        The classic's write: Set-CIPPDlpCompliancePolicy creates the policy and its rules,
        or updates them in place by name. Only remediable states reach here - the hook
        withholds a PendingDeletion policy's template because the deploy would just fail.
        The helper reports failures as strings ('Could not deploy...'/'Failed...'), which
        become an honest thrown error.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Templates = @($Current.remediableTemplates)
    if ($Templates.Count -eq 0) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'No remediable DLP policy template on this instance (a PendingDeletion policy cannot be modified) - nothing written.' -Sev 'Info'
        return
    }
    foreach ($Template in $Templates) {
        $DeployResult = Set-CIPPDlpCompliancePolicy -TenantFilter $TenantFilter -Template $Template -APIName 'Baselines'
        if ("$DeployResult" -match '^(Could not deploy|Failed)') {
            throw "$DeployResult"
        }
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Deployed the DLP policy '$($Template.Name ?? $Template.name)': $DeployResult" -Sev 'Info'
    }
}
