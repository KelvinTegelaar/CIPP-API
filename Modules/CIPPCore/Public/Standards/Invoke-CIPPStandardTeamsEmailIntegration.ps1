Function Invoke-CIPPStandardTeamsEmailIntegration {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsEmailIntegration
    .SYNOPSIS
        (Label) Disallow emails to be sent to channel email addresses
    .DESCRIPTION
        (Helptext) Should users be allowed to send emails directly to a channel email addresses?
        (DocsDescription) Teams channel email addresses are an optional feature that allows users to email the Teams channel directly.
    .NOTES
        CAT
            Teams Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
            {"type":"boolean","name":"standards.TeamsEmailIntegration.AllowEmailIntoChannel","label":"Allow channel emails"}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-CsTeamsClientConfiguration -AllowEmailIntoChannel \$false
        RECOMMENDEDBY
            "CIS 3.0"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsClientConfiguration' -CmdParams @{Identity = 'Global'}
                | Select-Object AllowEmailIntoChannel

    if ($null -eq $Settings.AllowEmailIntoChannel)   { $Settings.AllowEmailIntoChannel = $false }

    $StateIsCorrect = ($CurrentState.AllowEmailIntoChannel -eq $Settings.AllowEmailIntoChannel)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Email Integration settings already set.' -sev Info
        } else {
            $cmdparams = @{
                Identity                = 'Global'
                AllowEmailIntoChannel   = $Settings.AllowEmailIntoChannel
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTeamsClientConfiguration' -CmdParams $cmdparams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated Teams Email Integration settings' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Teams Email Integration settings. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Email Integration settings is set correctly.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Email Integration settings is not set correctly.' -sev Alert
        }
    }

    if ($Setings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TeamsEmailIntoChannel' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
