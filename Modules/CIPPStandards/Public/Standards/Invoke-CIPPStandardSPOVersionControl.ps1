function Invoke-CIPPStandardSPOVersionControl {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SPOVersionControl
    .SYNOPSIS
        (Label) Set SharePoint File Version Limits
    .DESCRIPTION
        (Helptext) Configures SharePoint Online file versioning to either use automatic version trimming managed by Microsoft, or enforce a fixed major version limit with optional version expiration.
        (DocsDescription) Configures the SharePoint Online tenant-level file versioning policy. When automatic version trimming is enabled, Microsoft intelligently manages version cleanup. When disabled, you can set a fixed maximum number of major versions to retain and optionally expire versions after a specified number of days. This helps manage storage consumption while preserving version history as needed.
    .NOTES
        CAT
            SharePoint Standards
        TAG
        EXECUTIVETEXT
            Controls how SharePoint Online manages file version history at the tenant level. Automatic trimming lets Microsoft optimize storage by cleaning up old versions intelligently. Manual limits give administrators precise control over the maximum number of versions retained and their expiration, ensuring predictable storage usage and compliance with data retention policies.
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.SPOVersionControl.EnableAutoTrim","label":"Enable Automatic Version Trimming (Microsoft managed)"}
            {"type":"number","name":"standards.SPOVersionControl.MajorVersionLimit","label":"Maximum Major Versions (when auto trim is off)","default":50}
            {"type":"number","name":"standards.SPOVersionControl.ExpireVersionsAfterDays","label":"Expire Versions After Days (0 = never, when auto trim is off)","default":0}
            {"type":"switch","name":"standards.SPOVersionControl.ApplyToExistingSites","label":"Apply to all existing sites and document libraries"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-05-27
        POWERSHELLEQUIVALENT
            Set-SPOTenant -EnableAutoExpirationVersionTrim $true or Set-SPOTenant -EnableAutoExpirationVersionTrim $false -MajorVersionLimit 50 -ExpireVersionsAfterDays 365
        RECOMMENDEDBY
            "CIPP"
        REQUIREDCAPABILITIES
            "SHAREPOINTWAC"
            "SHAREPOINTSTANDARD"
            "SHAREPOINTENTERPRISE"
            "SHAREPOINTENTERPRISE_EDU"
            "SHAREPOINTENTERPRISE_GOV"
            "ONEDRIVE_BASIC"
            "ONEDRIVE_ENTERPRISE"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'SPOVersionControl' -TenantFilter $Tenant -Preset SharePoint

    if ($TestResult -eq $false) {
        return $true
    }

    $DesiredAutoTrim = [bool]$Settings.EnableAutoTrim
    $DesiredMajorVersionLimit = [int]($Settings.MajorVersionLimit ?? 50)
    $DesiredExpireVersionsAfterDays = [int]($Settings.ExpireVersionsAfterDays ?? 0)

    try {
        $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant | Select-Object -Property _ObjectIdentity_, TenantFilter, EnableAutoExpirationVersionTrim, MajorVersionLimit, ExpireVersionsAfterDays
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -message "Could not get the SPOVersionControl state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    if ($DesiredAutoTrim) {
        $StateIsCorrect = $CurrentState.EnableAutoExpirationVersionTrim -eq $true
    } else {
        $StateIsCorrect = ($CurrentState.EnableAutoExpirationVersionTrim -eq $false) -and
        ($CurrentState.MajorVersionLimit -eq $DesiredMajorVersionLimit) -and
        ($CurrentState.ExpireVersionsAfterDays -eq $DesiredExpireVersionsAfterDays)
    }

    $CurrentValue = [PSCustomObject]@{
        EnableAutoExpirationVersionTrim = $CurrentState.EnableAutoExpirationVersionTrim
        MajorVersionLimit               = $CurrentState.MajorVersionLimit
        ExpireVersionsAfterDays         = $CurrentState.ExpireVersionsAfterDays
    }
    $ExpectedValue = [PSCustomObject]@{
        EnableAutoExpirationVersionTrim = $DesiredAutoTrim
        MajorVersionLimit               = if ($DesiredAutoTrim) { $null } else { $DesiredMajorVersionLimit }
        ExpireVersionsAfterDays         = if ($DesiredAutoTrim) { $null } else { $DesiredExpireVersionsAfterDays }
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SharePoint version control settings are already configured correctly' -sev Info
        } else {
            try {
                # SetFileVersionPolicy method: params are (Boolean isAutoTrimEnabled, Int32 majorVersionLimit, Int32 expireVersionsAfterDays)
                # When auto trim is on, pass -1 for the version/expiry params
                if ($DesiredAutoTrim) {
                    $MethodParams = @(
                        @{ Type = 'Boolean'; Value = $true }
                        @{ Type = 'Int32'; Value = -1 }
                        @{ Type = 'Int32'; Value = -1 }
                    )
                } else {
                    $MethodParams = @(
                        @{ Type = 'Boolean'; Value = $false }
                        @{ Type = 'Int32'; Value = $DesiredMajorVersionLimit }
                        @{ Type = 'Int32'; Value = $DesiredExpireVersionsAfterDays }
                    )
                }
                $CurrentState | Set-CIPPSPOTenant -MethodName 'SetFileVersionPolicy' -MethodParameters $MethodParams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully configured SharePoint version control (AutoTrim: $DesiredAutoTrim, MajorVersionLimit: $DesiredMajorVersionLimit, ExpireVersionsAfterDays: $DesiredExpireVersionsAfterDays)" -sev Info

                # Apply to all existing sites and their document libraries
                if ($Settings.ApplyToExistingSites -eq $true) {
                    $Sites = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/getAllSites?`$select=webUrl&`$top=999" -tenantid $Tenant -AsApp $true)
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Applying version policy to $($Sites.Count) existing sites" -sev Info

                    $SiteProperties = @{
                        InheritVersionPolicyFromTenant   = $true
                        EnableAutoExpirationVersionTrim  = $DesiredAutoTrim
                        ApplyToNewDocumentLibraries      = $true
                        ApplyToExistingDocumentLibraries = $true
                    }
                    if (-not $DesiredAutoTrim) {
                        $SiteProperties.MajorVersionLimit = $DesiredMajorVersionLimit
                        $SiteProperties.ExpireVersionsAfterDays = $DesiredExpireVersionsAfterDays
                    }

                    foreach ($Site in $Sites) {
                        try {
                            Set-CIPPSPOSite -TenantFilter $Tenant -SiteUrl $Site.webUrl -Properties $SiteProperties
                        } catch {
                            $SiteError = Get-CippException -Exception $_
                            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set version policy for site $($Site.webUrl): $($SiteError.NormalizedError)" -sev Error -LogData $SiteError
                        }
                    }
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Finished applying version policy to existing sites' -sev Info
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set SharePoint version control settings. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SharePoint version control settings are configured correctly' -sev Info
        } else {
            $Message = "SharePoint version control is not configured correctly. Current: AutoTrim=$($CurrentState.EnableAutoExpirationVersionTrim), MajorVersionLimit=$($CurrentState.MajorVersionLimit), ExpireVersionsAfterDays=$($CurrentState.ExpireVersionsAfterDays). Expected: AutoTrim=$DesiredAutoTrim, MajorVersionLimit=$DesiredMajorVersionLimit, ExpireVersionsAfterDays=$DesiredExpireVersionsAfterDays"
            Write-StandardsAlert -message $Message -object $CurrentState -tenant $Tenant -standardName 'SPOVersionControl' -standardId $Settings.standardId
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.SPOVersionControl' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'SPOVersionControl' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
