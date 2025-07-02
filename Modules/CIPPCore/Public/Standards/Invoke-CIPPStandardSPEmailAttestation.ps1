function Invoke-CIPPStandardSPEmailAttestation {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SPEmailAttestation
    .SYNOPSIS
        (Label) Require re-authentication with verification code
    .DESCRIPTION
        (Helptext) Ensure re-authentication with verification code is restricted
        (DocsDescription) Ensure re-authentication with verification code is restricted
    .NOTES
        CAT
            SharePoint Standards
        TAG
            "CIS"
        ADDEDCOMPONENT
            {"type":"number","name":"standards.SPEmailAttestation.Days","label":"Require re-authentication every X Days (Default 15)"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2024-07-09
        POWERSHELLEQUIVALENT
            Set-SPOTenant -EmailAttestationRequired \$true -EmailAttestationReAuthDays 15
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant | Select-Object -Property _ObjectIdentity_, TenantFilter, EmailAttestationReAuthDays, EmailAttestationRequired

    $StateIsCorrect = ($CurrentState.EmailAttestationReAuthDays -eq [int]$Settings.Days) -and
    ($CurrentState.EmailAttestationRequired -eq $true)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SharePoint re-authentication with verification code is already restricted.' -Sev Info
        } else {
            $Properties = @{
                EmailAttestationReAuthDays = [int]$Settings.Days
                EmailAttestationRequired   = $true
            }

            try {
                $Response = $CurrentState | Set-CIPPSPOTenant -Properties $Properties
                if ($Response.ErrorInfo.ErrorMessage) {
                    $ErrorMessage = Get-NormalizedError -Message $Response.ErrorInfo.ErrorMessage
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set re-authentication with verification code restriction. Error: $ErrorMessage" -Sev Error
                } else {
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully set re-authentication with verification code restriction.' -Sev Info
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set re-authentication with verification code restriction. Error: $ErrorMessage" -Sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Re-authentication with verification code is restricted.' -Sev Info
        } else {
            $Message = 'Re-authentication with verification code is not set to the desired value.'
            Write-StandardsAlert -message $Message -object $CurrentState -tenant $Tenant -standardName 'SPEmailAttestation' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message $Message -Sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SPEmailAttestation' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.SPEmailAttestation' -FieldValue $FieldValue -TenantFilter $Tenant
    }
}
