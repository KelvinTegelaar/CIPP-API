function Invoke-CIPPStandardintuneDeviceReg {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) intuneDeviceReg
    .SYNOPSIS
        (Label) Set Maximum Number of Devices per user
    .DESCRIPTION
        (Helptext) Sets the maximum number of devices that can be registered by a user. A value of 0 disables device registration by users
        (DocsDescription) Sets the maximum number of devices that can be registered by a user. A value of 0 disables device registration by users
    .NOTES
        CAT
            Intune Standards
        TAG
        ADDEDCOMPONENT
            {"type":"number","name":"standards.intuneDeviceReg.max","label":"Maximum devices (Enter 2147483647 for unlimited.)","required":true}
        IMPACT
            Medium Impact
        ADDEDDATE
            2023-03-27
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyDeviceRegistrationPolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/intune-standards#medium-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'intuneDeviceReg'

    $PreviousSetting = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -tenantid $Tenant
    $StateIsCorrect = if ($PreviousSetting.userDeviceQuota -eq $Settings.max) { $true } else { $false }

    If ($Settings.remediate -eq $true) {

        if ($PreviousSetting.userDeviceQuota -eq $Settings.max) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "User device quota is already set to $($Settings.max)" -sev Info
        } else {
            try {
                $PreviousSetting.userDeviceQuota = $Settings.max
                $Newbody = ConvertTo-Json -Compress -InputObject $PreviousSetting -Depth 5
                $null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -Type PUT -Body $NewBody -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Set user device quota to $($Settings.max)" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set user device quota to $($Settings.max) : $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "User device quota is set to $($Settings.max)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "User device quota is not set to $($Settings.max)" -sev Alert
        }
    }

    if ($Settings.report -eq $true) {

        Add-CIPPBPAField -FieldName 'intuneDeviceReg' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
