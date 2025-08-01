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
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.TeamsEmailIntegration.AllowEmailIntoChannel","label":"Allow channel emails"}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-07-30
        POWERSHELLEQUIVALENT
            Set-CsTeamsClientConfiguration -AllowEmailIntoChannel \$false
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'TeamsEmailIntegration' -TenantFilter $Tenant -RequiredCapabilities @('MCOSTANDARD', 'MCOEV', 'MCOIMP', 'TEAMS1','Teams_Room_Standard')
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'TeamsEmailIntegration'

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    try {
        $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsClientConfiguration' -CmdParams @{Identity = 'Global' } |
        Select-Object AllowEmailIntoChannel
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the TeamsEmailIntegration state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $AllowEmailIntoChannel = $Settings.AllowEmailIntoChannel ?? $false

    $StateIsCorrect = ($CurrentState.AllowEmailIntoChannel -eq $AllowEmailIntoChannel)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Email Integration settings already set.' -sev Info
        } else {
            $cmdParams = @{
                Identity              = 'Global'
                AllowEmailIntoChannel = $AllowEmailIntoChannel
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTeamsClientConfiguration' -CmdParams $cmdParams
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
            Write-StandardsAlert -message 'Teams Email Integration settings is not set correctly.' -object $CurrentState -tenant $Tenant -standardName 'TeamsEmailIntegration' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams Email Integration settings is not set correctly.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {

        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsEmailIntegration' -FieldValue $FieldValue -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'TeamsEmailIntoChannel' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant

    }
}
