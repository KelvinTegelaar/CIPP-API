function Invoke-CIPPStandardEnableNamePronounciation {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EnableNamePronounciation
    .SYNOPSIS
        (Label) Enable Name Pronounciation
    .DESCRIPTION
        (Helptext) Enables the Name Pronounciation feature for the tenant. This allows users to set their name pronounciation in their profile.
        (DocsDescription) Enables the Name Pronounciation feature for the tenant. This allows users to set their name pronounciation in their profile.
    .NOTES
        CAT
            Global Standards
        TAG
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2025-06-06
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param ($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'EnablePronouns'

    $Uri = 'https://graph.microsoft.com/v1.0/admin/people/namePronunciation'
    try {
        $CurrentState = New-GraphGetRequest -Uri $Uri -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not get CurrentState for Name Pronounciation. Error: $($ErrorMessage.NormalizedError)" -sev Error
        Return
    }
    Write-Host $CurrentState

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($CurrentState.isEnabledInOrganization -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Name Pronounciation is already enabled.' -sev Info
        } else {
            $CurrentState.isEnabledInOrganization = $true
            try {
                $Body = ConvertTo-Json -InputObject $CurrentState -Depth 10 -Compress
                New-GraphPostRequest -Uri $Uri -tenantid $Tenant -Body $Body -type PATCH
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled name pronounciation.' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable name pronounciation. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CurrentState.isEnabledInOrganization -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Name Pronounciation is enabled.' -sev Info
        } else {
            Write-StandardsAlert -message 'Name Pronounciation is not enabled' -object $CurrentState -tenant $tenant -standardName 'EnableNamePronounciation' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Name Pronounciation is not enabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.EnableNamePronounciation' -FieldValue $CurrentState.isEnabledInOrganization -Tenant $tenant
        Add-CIPPBPAField -FieldName 'NamePronounciationEnabled' -FieldValue $CurrentState.isEnabledInOrganization -StoreAs bool -Tenant $tenant
    }
}
