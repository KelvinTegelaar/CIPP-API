function Invoke-CIPPStandardAntiSpamSafeList {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AntiSpamSafeList
    .SYNOPSIS
        (Label) Set Anti-Spam Connection Filter Safe List
    .DESCRIPTION
        (Helptext) Sets the anti-spam connection filter policy option 'safe list' in Defender.
        (DocsDescription) Sets [Microsoft's built-in 'safe list'](https://learn.microsoft.com/en-us/powershell/module/exchange/set-hostedconnectionfilterpolicy?view=exchange-ps#-enablesafelist) in the anti-spam connection filter policy, rather than setting a custom safe/block list of IPs.
    .NOTES
        CAT
            Defender Standards
        TAG
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.AntiSpamSafeList.EnableSafeList","label":"Enable Safe List"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-02-15
        POWERSHELLEQUIVALENT
            Set-HostedConnectionFilterPolicy "Default" -EnableSafeList \$true
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/defender-standards#medium-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'AntiSpamSafeList'

    try {
        $State = [System.Convert]::ToBoolean($Settings.EnableSafeList)
    } catch {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'AntiSpamSafeList: Failed to convert the EnableSafeList parameter to a boolean' -sev Error
        Return
    }

    try {
        $CurrentState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-HostedConnectionFilterPolicy' -cmdParams @{Identity = 'Default' }).EnableSafeList
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to get the Anti-Spam Connection Filter Safe List. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Return
    }
    $WantedState = $State -eq $true ? $true : $false
    $StateIsCorrect = if ($CurrentState -eq $WantedState) { $true } else { $false }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.AntiSpamSafeList' -FieldValue $StateIsCorrect -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'AntiSpamSafeList' -FieldValue $CurrentState -StoreAs bool -Tenant $Tenant
    }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'
        if ($StateIsCorrect -eq $false) {
            try {
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-HostedConnectionFilterPolicy' -cmdParams @{
                    Identity       = 'Default'
                    EnableSafeList = $WantedState
                }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully set the Anti-Spam Connection Filter Safe List to $WantedState" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set the Anti-Spam Connection Filter Safe List to $WantedState. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "The Anti-Spam Connection Filter Safe List is already set correctly to $WantedState" -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "The Anti-Spam Connection Filter Safe List is set correctly to $WantedState" -sev Info
        } else {
            Write-StandardsAlert -message "The Anti-Spam Connection Filter Safe List is not set correctly to $WantedState" -object @{CurrentState = $CurrentState; WantedState = $WantedState } -tenant $Tenant -standardName 'AntiSpamSafeList' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "The Anti-Spam Connection Filter Safe List is not set correctly to $WantedState" -sev Info
        }
    }
}
