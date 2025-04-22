function Invoke-CIPPStandardEnablePronouns {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EnablePronouns
    .SYNOPSIS
        (Label) Enable Pronouns
    .DESCRIPTION
        (Helptext) Enables the Pronouns feature for the tenant. This allows users to set their pronouns in their profile.
        (DocsDescription) Enables the Pronouns feature for the tenant. This allows users to set their pronouns in their profile.
    .NOTES
        CAT
            Global Standards
        TAG
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2024-06-05
        POWERSHELLEQUIVALENT
            Update-MgBetaAdminPeoplePronoun -IsEnabledInOrganization:\$true
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/global-standards#low-impact
    #>

    param ($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'EnablePronouns'

    $Uri = 'https://graph.microsoft.com/v1.0/admin/people/pronouns'
    try {
        $CurrentState = New-GraphGetRequest -Uri $Uri -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not get CurrentState for Pronouns. Error: $($ErrorMessage.NormalizedError)" -sev Error
        Return
    }
    Write-Host $CurrentState

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($CurrentState.isEnabledInOrganization -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Pronouns are already enabled.' -sev Info
        } else {
            $CurrentState.isEnabledInOrganization = $true
            try {
                $Body = ConvertTo-Json -InputObject $CurrentState -Depth 10 -Compress
                New-GraphPostRequest -Uri $Uri -tenantid $Tenant -Body $Body -type PATCH
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled pronouns.' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable pronouns. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CurrentState.isEnabledInOrganization -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Pronouns are enabled.' -sev Info
        } else {
            Write-StandardsAlert -message 'Pronouns are not enabled' -object $CurrentState -tenant $tenant -standardName 'EnablePronouns' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Pronouns are not enabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.EnablePronouns' -FieldValue $CurrentState.isEnabledInOrganization -Tenant $tenant
        Add-CIPPBPAField -FieldName 'PronounsEnabled' -FieldValue $CurrentState.isEnabledInOrganization -StoreAs bool -Tenant $tenant
    }
}
