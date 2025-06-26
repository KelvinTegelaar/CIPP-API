function Invoke-CIPPStandardSPDisallowInfectedFiles {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SPDisallowInfectedFiles
    .SYNOPSIS
        (Label) Disallow downloading infected files from SharePoint
    .DESCRIPTION
        (Helptext) Ensure Office 365 SharePoint infected files are disallowed for download
        (DocsDescription) Ensure Office 365 SharePoint infected files are disallowed for download
    .NOTES
        CAT
            SharePoint Standards
        TAG
            "CIS"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2024-07-09
        POWERSHELLEQUIVALENT
            Set-SPOTenant -DisallowInfectedFileDownload \$true
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant |
        Select-Object -Property _ObjectIdentity_, TenantFilter, DisallowInfectedFileDownload

    $StateIsCorrect = ($CurrentState.DisallowInfectedFileDownload -eq $true)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -Message 'Downloading SharePoint infected files are already disallowed.' -Sev Info
        } else {
            $Properties = @{
                DisallowInfectedFileDownload = $true
            }

            try {
                $CurrentState | Set-CIPPSPOTenant -Properties $Properties
                Write-LogMessage -API 'Standards' -tenant $tenant -Message 'Successfully disallowed downloading SharePoint infected files.' -Sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -Message "Failed to disallow downloading SharePoint infected files. Error: $ErrorMessage" -Sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -Message 'Downloading SharePoint infected files are disallowed.' -Sev Info
        } else {
            $Message = 'Downloading SharePoint infected files is not set to the desired value.'
            Write-StandardsAlert -message $Message -object $CurrentState -tenant $Tenant -standardName 'SPDisallowInfectedFiles' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -Message $Message -Sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SPDisallowInfectedFiles' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant

        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.SPDisallowInfectedFiles' -FieldValue $FieldValue -Tenant $Tenant
    }
}
