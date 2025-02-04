function Invoke-CIPPStandardAppDeploy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AppDeploy
    .SYNOPSIS
        (Label) Deploy Application
    .DESCRIPTION
        (Helptext) Deploys selected applications to the tenant. Use a comma separated list of application IDs to deploy multiple applications. Permissions will be copied from the source application.
        (DocsDescription) Uses the CIPP functionality that deploys applications across an entire tenant base as a standard.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.AppDeploy.appids","label":"Application IDs, comma separated"}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Portal or Graph API
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#low-impact
    #>

    param($Tenant, $Settings)

    If ($Settings.remediate -eq $true) {
        ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'AppDeploy'
        if ($Rerun -eq $true) {
            exit 0
        }
        $AppsToAdd = $Settings.appids -split ','
        foreach ($App In $AppsToAdd) {
            try {
                New-CIPPApplicationCopy -App $App -Tenant $Tenant
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Added $App to $Tenant and update it's permissions" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to add app $App. Error: $ErrorMessage" -sev Error
            }
        }
    }
}
