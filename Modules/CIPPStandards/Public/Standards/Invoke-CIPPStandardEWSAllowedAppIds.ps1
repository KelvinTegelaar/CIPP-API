function Invoke-CIPPStandardEWSAllowedAppIds {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EWSAllowedAppIds
    .SYNOPSIS
        (Label) Configure EWS allowed applications
    .DESCRIPTION
        (Helptext) Adds the selected applications to the Exchange Online EWS app allow list (EwsAllowedAppIDs) and sets EwsEnabled to true. Apps already on the list are kept, and known-malicious apps are never added. Do not use together with the "Disable Exchange Web Services" standard on the same tenant: they set EwsEnabled to opposite values. Once CIPP writes the list, Microsoft stops auto-populating it for that tenant, so include every app the tenant needs (check the EWS usage report in the Microsoft 365 admin center). Changes can take up to 24 hours to apply. Keep "Include the dedicated Exchange hybrid app" on for hybrid organisations so Free/Busy and MailTips keep working.
        (DocsDescription) When EWS is enabled, Exchange Online only allows EWS access from the application IDs on the organization's EwsAllowedAppIDs list, and an empty list blocks all EWS. Microsoft populates that list from recent usage only while the admin has never set it, so the list CIPP writes must be complete. This standard reads the current list and adds the selected presets, the custom application IDs (tenant variables are supported, invalid IDs are skipped with a warning) and, optionally, every app that holds the Exchange Online full_access_as_app application permission or a delegated EWS permission, plus the dedicated Exchange hybrid app (ExchangeServerApp-*) that hybrid Free/Busy, MailTips, profile photos and archive moves depend on. IDs already on the list are never removed; the only exception is known-malicious apps (CIPP's curated list), which are removed only when that option is enabled and are reported as drift otherwise. Known-malicious apps are never added. This conflicts with the "Disable Exchange Web Services" standard. Changes can take up to 24 hours to take effect. See Microsoft's guidance on the deprecation of EWS in Exchange Online: https://learn.microsoft.com/en-us/exchange/clients-and-mobile-in-exchange-online/deprecation-of-ews-exchange-online
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Keeps the business applications that still rely on Exchange Web Services working as Microsoft retires unrestricted EWS access, by maintaining the approved-application list for each tenant. Existing approvals are preserved and applications known to be used in attacks are never approved.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":true,"creatable":false,"required":false,"name":"standards.EWSAllowedAppIds.presets","label":"Known applications to allow (empty = Microsoft Office, Power Query for Excel, Power BI Data Refresh, Apple Mail/Calendar)","options":[{"label":"Microsoft Office","value":"MicrosoftOffice"},{"label":"Microsoft Power Query for Excel","value":"PowerQuery"},{"label":"Power BI Data Refresh","value":"PowerBIDataRefresh"},{"label":"Apple Mail/Calendar (macOS)","value":"AppleMail"},{"label":"AvePoint Cloud Backup / Fly / Cloud Governance (hosted)","value":"AvePointCloud"},{"label":"AvePoint Fly Server","value":"AvePointFlyServer"}]}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"name":"standards.EWSAllowedAppIds.customAppIds","label":"Additional application (client) IDs, tenant variables such as %veeam_ews_appid% are supported"}
            {"type":"switch","name":"standards.EWSAllowedAppIds.includeEwsPermissionApps","label":"Include apps holding EWS permissions (full_access_as_app, EWS.AccessAsUser.All, full_access_as_user)"}
            {"type":"switch","name":"standards.EWSAllowedAppIds.includeHybridApp","label":"Include the dedicated Exchange hybrid app (ExchangeServerApp-*)","defaultValue":true}
            {"type":"switch","name":"standards.EWSAllowedAppIds.removeMaliciousApps","label":"Remove known-malicious apps from the list"}
        IMPACT
            High Impact
        ADDEDDATE
            2026-09-28
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -EwsEnabled $true -EwsAllowedAppIDs
        RECOMMENDEDBY
        REQUIREDCAPABILITIES
            "EXCHANGE_S_STANDARD"
            "EXCHANGE_S_ENTERPRISE"
            "EXCHANGE_S_STANDARD_GOV"
            "EXCHANGE_S_ENTERPRISE_GOV"
            "EXCHANGE_LITE"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
        https://learn.microsoft.com/en-us/exchange/clients-and-mobile-in-exchange-online/deprecation-of-ews-exchange-online
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'EWSAllowedAppIds' -TenantFilter $Tenant -Preset Exchange

    if ($TestResult -eq $false) {
        return $true
    }

    $StateParams = @{
        TenantFilter             = $Tenant
        Presets                  = $Settings.presets
        CustomAppIds             = $Settings.customAppIds
        IncludeEwsPermissionApps = [bool]$Settings.includeEwsPermissionApps
        IncludeHybridApp         = $Settings.includeHybridApp -ne $false
        RemoveMaliciousApps      = [bool]$Settings.removeMaliciousApps
    }
    try {
        $State = Get-CIPPEwsAllowedAppIdState @StateParams
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the EWS allowed applications for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        if (-not $State.NeedsWrite) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'EWS allowed applications are already configured.' -Sev Info
        } else {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ EwsEnabled = $true; EwsAllowedAppIDs = ($State.DesiredAppIds -join ',') } -UseSystemMailbox $true
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Enabled EWS and set the EWS allowed applications. Added: $(if ($State.MissingAppIds.Count -gt 0) { $State.MissingAppIds -join ', ' } else { 'none' })." -Sev Info
                $RemovedMalicious = @($State.MaliciousAppIdsPresent | Where-Object { $State.DesiredAppIds -notcontains $_ })
                $State.EwsEnabled = $true
                $State.MissingAppIds = @()
                $State.MaliciousAppIdsPresent = @($State.MaliciousAppIdsPresent | Where-Object { $RemovedMalicious -notcontains $_ })
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set the EWS allowed applications. Error: $ErrorMessage" -Sev Error
            }
        }
    }

    $Compliant = $State.EwsEnabled -eq $true -and $State.MissingAppIds.Count -eq 0 -and $State.MaliciousAppIdsPresent.Count -eq 0

    if ($Settings.alert -eq $true) {
        if ($Compliant) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'EWS is enabled and all required applications are on the EWS allow list.' -Sev Info
        } else {
            $Problems = [System.Collections.Generic.List[string]]::new()
            if ($State.EwsEnabled -ne $true) { $Problems.Add('EWS is not enabled') }
            if ($State.MissingAppIds.Count -gt 0) { $Problems.Add("missing app IDs: $($State.MissingAppIds -join ', ')") }
            if ($State.MaliciousAppIdsPresent.Count -gt 0) { $Problems.Add("known-malicious app IDs on the list: $($State.MaliciousAppIdsPresent -join ', ')") }
            $Message = "EWS allowed applications are not compliant: $($Problems -join '; ')."
            Write-StandardsAlert -message $Message -object $State -tenant $Tenant -standardName 'EWSAllowedAppIds' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message $Message -Sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            EwsEnabled             = $State.EwsEnabled -eq $true
            MissingAppIds          = @($State.MissingAppIds)
            MaliciousAppIdsPresent = @($State.MaliciousAppIdsPresent)
        }
        $ExpectedValue = [PSCustomObject]@{
            EwsEnabled             = $true
            MissingAppIds          = @()
            MaliciousAppIdsPresent = @()
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.EWSAllowedAppIds' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
    }
}
