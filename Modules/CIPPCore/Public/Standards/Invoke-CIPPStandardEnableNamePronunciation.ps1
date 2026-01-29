function Invoke-CIPPStandardEnableNamePronunciation {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EnableNamePronunciation
    .SYNOPSIS
        (Label) Enable Name Pronunciation
    .DESCRIPTION
        (Helptext) Enables the Name Pronunciation feature for the tenant. This allows users to set their name pronunciation in their profile.
        (DocsDescription) Enables the Name Pronunciation feature for the tenant. This allows users to set their name pronunciation in their profile.
    .NOTES
        CAT
            Global Standards
        TAG
        EXECUTIVETEXT
            Enables employees to add pronunciation guides for their names in Microsoft 365 profiles, improving communication and respect in diverse workplaces. This feature helps colleagues pronounce names correctly, enhancing professional relationships and inclusive culture.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2025-06-06
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param ($Tenant, $Settings)

    $Uri = 'https://graph.microsoft.com/beta/admin/people/namePronunciation'
    try {
        $CurrentState = New-GraphGetRequest -Uri $Uri -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not get CurrentState for Name Pronunciation. Error: $($ErrorMessage.NormalizedError)" -sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        if ($CurrentState.isEnabledInOrganization -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Name Pronunciation is already enabled.' -sev Info
        } else {
            $CurrentState.isEnabledInOrganization = $true
            try {
                $Body = ConvertTo-Json -InputObject $CurrentState -Depth 10 -Compress
                $null = New-GraphPostRequest -Uri $Uri -tenantid $Tenant -Body $Body -type PATCH -AsApp $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled name pronunciation.' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable name pronunciation. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CurrentState.isEnabledInOrganization -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Name Pronunciation is enabled.' -sev Info
        } else {
            Write-StandardsAlert -message 'Name Pronunciation is not enabled' -object $CurrentState -tenant $tenant -standardName 'EnableNamePronunciation' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Name Pronunciation is not enabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            EnableNamePronunciation = $CurrentState.isEnabledInOrganization
        }
        $ExpectedValue = [PSCustomObject]@{
            EnableNamePronunciation = $true
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.EnableNamePronunciation' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $tenant
        Add-CIPPBPAField -FieldName 'NamePronunciationEnabled' -FieldValue $CurrentState.isEnabledInOrganization -StoreAs bool -Tenant $tenant
    }
}
