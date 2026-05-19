function Invoke-CIPPStandardEmptyFilterIPAllowList {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EmptyFilterIPAllowList
    .SYNOPSIS
        (Label) Ensure connection filter IP allow list is empty
    .DESCRIPTION
        (Helptext) Ensures the connection filter IP allow list is not used. IPs on this list bypass spam, spoof, and authentication checks.
        (DocsDescription) IPs on the connection filter allow list bypass spam, spoof, and authentication checks. CIS recommends keeping this list empty to ensure all inbound email is properly scanned. This standard checks that the IPAllowList on the Default hosted connection filter policy is empty and can remediate by clearing it.
    .NOTES
        CAT
            Defender Standards
        TAG
            "CIS M365 6.0.1 (2.1.12)"
        EXECUTIVETEXT
            Ensures the Exchange Online connection filter IP allow list is empty, preventing any IP addresses from bypassing spam filtering, spoofing checks, and sender authentication. Keeping this list empty ensures all inbound email undergoes full security scanning, reducing the risk of phishing and malware delivery through trusted-but-compromised sources.
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-05-06
        POWERSHELLEQUIVALENT
            Set-HostedConnectionFilterPolicy -Identity Default -IPAllowList @()
        RECOMMENDEDBY
            "CIS"
        REQUIREDCAPABILITIES
            "EXCHANGE_S_STANDARD"
            "EXCHANGE_S_ENTERPRISE"
            "EXCHANGE_S_STANDARD_GOV"
            "EXCHANGE_S_ENTERPRISE_GOV"
            "EXCHANGE_LITE"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    $TestResult = Test-CIPPStandardLicense -StandardName 'EmptyFilterIPAllowList' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE')
    if ($TestResult -eq $false) { return $true }

    try {
        $CurrentState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-HostedConnectionFilterPolicy' -cmdParams @{ Identity = 'Default' })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "EmptyFilterIPAllowList: Failed to get connection filter policy. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    $IPAllowList = @($CurrentState.IPAllowList)
    $StateIsCorrect = ($IPAllowList.Count -eq 0)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Connection filter IP allow list is already empty.' -sev Info
        } else {
            try {
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-HostedConnectionFilterPolicy' -cmdParams @{
                    Identity    = 'Default'
                    IPAllowList = @()
                }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Cleared connection filter IP allow list. Removed: $($IPAllowList -join ', ')" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to clear connection filter IP allow list. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Connection filter IP allow list is empty.' -sev Info
        } else {
            Write-StandardsAlert -message "Connection filter IP allow list is not empty. Current entries: $($IPAllowList -join ', ')" -object @{ IPAllowList = $IPAllowList } -tenant $Tenant -standardName 'EmptyFilterIPAllowList' -standardId $Settings.standardId
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            IPAllowListEmpty = $StateIsCorrect
            IPAllowList      = ($IPAllowList -join ', ')
        }
        $ExpectedValue = [PSCustomObject]@{
            IPAllowListEmpty = $true
            IPAllowList      = ''
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.EmptyFilterIPAllowList' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'EmptyFilterIPAllowList' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
