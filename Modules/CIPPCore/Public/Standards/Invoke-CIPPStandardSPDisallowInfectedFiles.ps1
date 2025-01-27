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
            "lowimpact"
            "CIS"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-SPOTenant -DisallowInfectedFileDownload \$true
        RECOMMENDEDBY
            "CIS 3.0"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/sharepoint-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'SPDisallowInfectedFiles'

    $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant |
    Select-Object -Property DisallowInfectedFileDownload

    $StateIsCorrect = ($CurrentState.DisallowInfectedFileDownload -eq $true)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -Message 'Downloading Sharepoint infected files are already disallowed.' -Sev Info
        } else {
            $Properties = @{
                DisallowInfectedFileDownload = $true
            }

            try {
                Get-CIPPSPOTenant -TenantFilter $Tenant | Set-CIPPSPOTenant -Properties $Properties
                Write-LogMessage -API 'Standards' -tenant $tenant -Message 'Successfully disallowed downloading SharePoint infected files.' -Sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -Message "Failed to disallow downloading Sharepoint infected files. Error: $ErrorMessage" -Sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -Message 'Downloading Sharepoint infected files are disallowed.' -Sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -Message 'Downloading Sharepoint infected files are allowed.' -Sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SPDisallowInfectedFiles' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
