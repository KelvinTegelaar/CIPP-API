function Invoke-CIPPStandardAppDeploy {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    AppDeploy
    .CAT
    Entra Standards
    .TAG
    "lowimpact"
    "CIS"
    .HELPTEXT
    Disables the ability for external users to share files they don't own. Sharing links can only be made for People with existing access
    .DOCSDESCRIPTION
    Disables the ability for external users to share files they don't own. Sharing links can only be made for People with existing access. This is a tenant wide setting and overrules any settings set on the site level
    .ADDEDCOMPONENT
    .LABEL
    Disable Resharing by External Users
    .IMPACT
    High Impact
    .POWERSHELLEQUIVALENT
    Update-MgBetaAdminSharepointSetting
    .RECOMMENDEDBY
    "CIS"
    .DOCSDESCRIPTION
    Disables the ability for external users to share files they don't own. Sharing links can only be made for People with existing access
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>

    param($Tenant, $Settings)

    If ($Settings.remediate -eq $true) {
        $AppsToAdd = $Settings.appids -split ','
        foreach ($App In $AppsToAdd) {
            try {
                New-CIPPApplicationCopy -App $App -Tenant $Tenant
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Added $App to $Tenant and update it's permissions" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to add app $App" -sev Error
            }
        }
    }
}





