# Backlog batch 4: the SharePoint/misc cluster. Tests pin the decisions that fail silently -
# extension normalization and replace semantics, side-selective domain grading, the SPO
# version-policy validation gate and -1 sentinels, only-configured contact grading, the
# two-surface photo policy, and secure score's newest-update-wins effective state.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines'

    function New-CIPPDbRequest { param($TenantFilter, $Type) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $useSystemMailbox) }
    function New-GraphPostRequest { param($tenantid, $uri, $type, $body, $AsApp, $ContentType) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphBulkRequest { param($tenantid, $Requests) }
    function Get-CIPPSPOTenant { param($TenantFilter) }
    function Set-CIPPSPOTenant { [CmdletBinding()] param([Parameter(ValueFromPipeline = $true)]$InputObject, $Properties, $MethodName, $MethodParameters) process { } }
    function Set-CIPPSPOSite { param($TenantFilter, $SiteUrl, $Properties) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) $Text }
    function Get-NormalizedError { param($Message) "$Message" }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $Baselines 'Get-CIPPBaselineCacheRows.ps1')
    . (Join-Path $Baselines 'Test-CIPPBaselineCacheCollected.ps1')
    foreach ($Name in @('ExcludedfileExt', 'sharingDomainRestriction', 'SPDirectSharing', 'SPOVersionControl',
            'MailContacts', 'ProfilePhotos', 'SecureScoreRemediation')) {
        . (Join-Path $Baselines "Get-CIPPBaseline${Name}State.ps1")
        . (Join-Path $Baselines "Invoke-CIPPBaseline${Name}.ps1")
    }

    $script:Tenant = 'contoso.onmicrosoft.com'
    function ConvertTo-Cached { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 20 | ConvertFrom-Json } }
    function Get-Verdict {
        param($Expected, $Current)
        $Projected = [PSCustomObject]@{}
        foreach ($Key in $Expected.PSObject.Properties.Name) { $Projected | Add-Member -NotePropertyName $Key -NotePropertyValue $Current.$Key }
        @(Compare-CIPPIntuneObject -ReferenceObject $Expected -DifferenceObject $Projected | Where-Object { $_ })
    }
    Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'X-Count'; DataCount = 1 } }
}

Describe 'Get-CIPPBaselineExcludedfileExtState' {
    It 'normalizes bare extensions to the *. prefix and grades the set order-insensitively' {
        Mock New-CIPPDbRequest { @(@{ excludedFileExtensionsForSyncApp = @('*.bat', '*.exe') } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ ext = 'exe, bat' } }
        $Prepared = Get-CIPPBaselineExcludedfileExtState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'grades a tenant extension OUTSIDE the baseline as drift - replace semantics, not subset' {
        # The classic rewrote the whole list; an extension the operator removed from the
        # baseline must come off the tenant, so extra tenant entries are drift.
        Mock New-CIPPDbRequest { @(@{ excludedFileExtensionsForSyncApp = @('*.bat', '*.exe', '*.js') } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ ext = 'exe,bat' } }
        $Prepared = Get-CIPPBaselineExcludedfileExtState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'writes the FULL normalized list app-only in one PATCH' {
        Mock New-GraphPostRequest { }
        Invoke-CIPPBaselineExcludedfileExt -Remediate ([PSCustomObject]@{ ext = 'exe, bat' }) -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'PATCH' -and $AsApp -eq $true -and $uri -like '*admin/sharepoint/settings' -and
            (@(($body | ConvertFrom-Json).excludedFileExtensionsForSyncApp) -join ',') -eq '*.bat,*.exe'
        }
    }
}

Describe 'Get-CIPPBaselinesharingDomainRestrictionState' {
    It 'mode none grades the mode alone and flags a tenant restriction as drift' {
        Mock New-CIPPDbRequest { @(@{ sharingDomainRestrictionMode = 'allowList'; sharingAllowedDomainList = @('a.com') } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ Mode = [PSCustomObject]@{ value = 'none' } } }
        $Prepared = Get-CIPPBaselinesharingDomainRestrictionState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Expected.PSObject.Properties.Name | Should -Not -Contain 'restrictedDomains'
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'grades the allow list order-insensitively and never grades the off-side block list' {
        Mock New-CIPPDbRequest { @(@{ sharingDomainRestrictionMode = 'allowList'; sharingAllowedDomainList = @('a.com', 'b.com'); sharingBlockedDomainList = @('evil.com') } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ Mode = [PSCustomObject]@{ value = 'allowList' }; Domains = 'b.com, a.com' } }
        $Prepared = Get-CIPPBaselinesharingDomainRestrictionState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'writes the mode plus ONLY the matching side''s list - for BOTH list modes' {
        Mock New-GraphPostRequest { }
        Invoke-CIPPBaselinesharingDomainRestriction -Remediate ([PSCustomObject]@{ mode = 'blockList'; domains = 'evil.com' }) -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $Parsed = $body | ConvertFrom-Json
            $AsApp -eq $true -and $Parsed.sharingDomainRestrictionMode -eq 'blockList' -and
            $Parsed.sharingBlockedDomainList -contains 'evil.com' -and -not $Parsed.PSObject.Properties['sharingAllowedDomainList']
        }
        Invoke-CIPPBaselinesharingDomainRestriction -Remediate ([PSCustomObject]@{ mode = 'allowList'; domains = 'partner.com' }) -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $Parsed = $body | ConvertFrom-Json
            $Parsed.sharingDomainRestrictionMode -eq 'allowList' -and
            $Parsed.sharingAllowedDomainList -contains 'partner.com' -and -not $Parsed.PSObject.Properties['sharingBlockedDomainList']
        }
    }

    It 'refuses a list mode with no domains rather than writing an empty restriction' {
        Mock New-GraphPostRequest { }
        Invoke-CIPPBaselinesharingDomainRestriction -Remediate ([PSCustomObject]@{ mode = 'allowList'; domains = '' }) -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
    }
}

Describe 'Get-CIPPBaselineSPDirectSharingState' {
    It 'accepts the numeric API vintage: DefaultSharingLinkType 1 is Direct' {
        Mock New-CIPPDbRequest { @(@{ DefaultSharingLinkType = 1 } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineSPDirectSharingState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'reads the SPO tenant LIVE for a fresh CSOM identity before the write' {
        # The cached identity goes stale and the SOAP endpoint rejects it - the write must
        # never lean on the cache row.
        Mock Get-CIPPSPOTenant { [PSCustomObject]@{ _ObjectIdentity_ = 'fresh'; TenantFilter = $script:Tenant; DefaultSharingLinkType = 2 } }
        Mock Set-CIPPSPOTenant { }
        Invoke-CIPPBaselineSPDirectSharing -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $null
        Should -Invoke Get-CIPPSPOTenant -Times 1 -Exactly
        Should -Invoke Set-CIPPSPOTenant -Times 1 -Exactly -ParameterFilter { $Properties.DefaultSharingLinkType -eq 1 }
    }
}

Describe 'Get-CIPPBaselineSPOVersionControlState' {
    It 'auto-trim on grades the trim flag ALONE - SharePoint manages the limits itself' {
        Mock New-CIPPDbRequest { @(@{ EnableAutoExpirationVersionTrim = $true; MajorVersionLimit = 500; ExpireVersionsAfterDays = 0 } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ EnableAutoTrim = $true; MajorVersionLimit = 50; ExpireVersionsAfterDays = 0 } }
        $Prepared = Get-CIPPBaselineSPOVersionControlState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Expected.PSObject.Properties.Name | Should -Not -Contain 'majorVersionLimit'
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'returns No Data for an expiry in the 1-29 gap SharePoint would refuse to store' {
        Mock New-CIPPDbRequest { @(@{ EnableAutoExpirationVersionTrim = $false; MajorVersionLimit = 50; ExpireVersionsAfterDays = 0 } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ EnableAutoTrim = $false; MajorVersionLimit = 50; ExpireVersionsAfterDays = 14 } }
        (Get-CIPPBaselineSPOVersionControlState -Item $Item -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }

    It 'manual mode grades the flag, the limit and the expiry together' {
        Mock New-CIPPDbRequest { @(@{ EnableAutoExpirationVersionTrim = $false; MajorVersionLimit = 100; ExpireVersionsAfterDays = 0 } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ EnableAutoTrim = $false; MajorVersionLimit = 50; ExpireVersionsAfterDays = 0 } }
        $Prepared = Get-CIPPBaselineSPOVersionControlState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'auto-trim writes the -1 sentinels through SetFileVersionPolicy' {
        Mock Get-CIPPSPOTenant { [PSCustomObject]@{ _ObjectIdentity_ = 'fresh'; TenantFilter = $script:Tenant } }
        Mock Set-CIPPSPOTenant { }
        Invoke-CIPPBaselineSPOVersionControl -Remediate ([PSCustomObject]@{ enableAutoTrim = $true }) -TenantFilter $script:Tenant -Current $null
        Should -Invoke Set-CIPPSPOTenant -Times 1 -Exactly -ParameterFilter {
            $MethodName -eq 'SetFileVersionPolicy' -and @($MethodParameters)[1].Value -eq -1 -and @($MethodParameters)[2].Value -eq -1
        }
    }

    It 'the existing-sites fan-out continues past a failing site' {
        Mock Get-CIPPSPOTenant { [PSCustomObject]@{ _ObjectIdentity_ = 'fresh'; TenantFilter = $script:Tenant } }
        Mock Set-CIPPSPOTenant { }
        Mock New-GraphGetRequest { @([PSCustomObject]@{ webUrl = 'https://c.sharepoint.com/sites/bad' }, [PSCustomObject]@{ webUrl = 'https://c.sharepoint.com/sites/good' }) }
        Mock Set-CIPPSPOSite { if ($SiteUrl -like '*bad') { throw 'site locked' } }
        Invoke-CIPPBaselineSPOVersionControl -Remediate ([PSCustomObject]@{ enableAutoTrim = $true; applyToExistingSites = $true }) -TenantFilter $script:Tenant -Current $null
        Should -Invoke Set-CIPPSPOSite -Times 2 -Exactly
        Should -Invoke Set-CIPPSPOSite -Times 1 -Exactly -ParameterFilter { $SiteUrl -like '*good' -and $Properties.InheritVersionPolicyFromTenant -eq $true }
    }
}

Describe 'Get-CIPPBaselineMailContactsState' {
    BeforeAll {
        $script:Org = @{ id = 'org-1'; marketingNotificationEmails = @('news@vendor.com', 'marketing@contoso.com')
            technicalNotificationMails = @('security@contoso.com', 'tech@contoso.com'); privacyProfile = @{ contactEmail = 'privacy@contoso.com' } }
    }

    It 'grades only the configured contacts - empty fields express no opinion' {
        Mock New-CIPPDbRequest { @($script:Org | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ MarketingContact = 'marketing@contoso.com' } }
        $Prepared = Get-CIPPBaselineMailContactsState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Expected.PSObject.Properties.Name | Should -Be @('marketingContactPresent')
        # Marketing is CONTAINS: the vendor address on the tenant list is fine.
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'grades security+technical as a sorted set against the technical notification list' {
        Mock New-CIPPDbRequest { @($script:Org | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ TechContact = 'tech@contoso.com'; SecurityContact = 'security@contoso.com'; GeneralContact = 'privacy@contoso.com' } }
        $Prepared = Get-CIPPBaselineMailContactsState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'writes only the configured members and dedups a shared security/tech address' {
        Mock New-GraphPostRequest { }
        $Remediate = [PSCustomObject]@{ securityContact = 'it@contoso.com'; techContact = 'it@contoso.com' }
        Invoke-CIPPBaselineMailContacts -Remediate $Remediate -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ organizationId = 'org-1' })
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $Parsed = $body | ConvertFrom-Json
            $AsApp -eq $true -and $uri -like '*organization/org-1' -and @($Parsed.technicalNotificationMails).Count -eq 1 -and
            -not $Parsed.PSObject.Properties['privacyProfile'] -and -not $Parsed.PSObject.Properties['marketingNotificationEmails']
        }
    }
}

Describe 'Get-CIPPBaselineProfilePhotosState' {
    It 'disabled demands BOTH admin role ids - one alone leaves the policy incorrect' {
        Mock New-CIPPDbRequest {
            if ($Type -eq 'PhotoUpdateSettings') { @(@{ source = 'cloud'; allowedRoles = @('62e90394-69f5-4237-9190-012177145e10') } | ConvertTo-Cached) }
            else { @(@{ Identity = 'OwaMailboxPolicy-Default'; SetPhotoEnabled = $false } | ConvertTo-Cached) }
        }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ state = [PSCustomObject]@{ value = 'disabled' } } }
        $Prepared = Get-CIPPBaselineProfilePhotosState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.photoUpdatePolicyCorrect | Should -BeFalse
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'enabled grades BOTH surfaces: empty Graph roles AND the default OWA policy flag' {
        Mock New-CIPPDbRequest {
            if ($Type -eq 'PhotoUpdateSettings') { @(@{ source = 'cloud'; allowedRoles = @() } | ConvertTo-Cached) }
            else { @(@{ Identity = 'OwaMailboxPolicy-Default'; SetPhotoEnabled = $true } | ConvertTo-Cached) }
        }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ state = [PSCustomObject]@{ value = 'enabled' } } }
        $Prepared = Get-CIPPBaselineProfilePhotosState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'enable DELETEs the photo policy back to default; disable PATCHes the admin roles - both app-only' {
        Mock New-ExoRequest { }
        Mock New-GraphPostRequest { }
        $Current = [PSCustomObject]@{ owaPolicyIdentity = 'OwaMailboxPolicy-Default' }
        Invoke-CIPPBaselineProfilePhotos -Remediate ([PSCustomObject]@{ state = 'enabled' }) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'DELETE' -and $AsApp -eq $true }
        Invoke-CIPPBaselineProfilePhotos -Remediate ([PSCustomObject]@{ state = 'disabled' }) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'PATCH' -and $AsApp -eq $true -and ($body | ConvertFrom-Json).allowedRoles.Count -eq 2
        }
        Should -Invoke New-ExoRequest -Times 2 -Exactly -ParameterFilter { $cmdlet -eq 'Set-OwaMailboxPolicy' -and $cmdParams.Identity -eq 'OwaMailboxPolicy-Default' }
    }
}

Describe 'Get-CIPPBaselineSecureScoreRemediationState' {
    It 'the effective state is the NEWEST controlStateUpdates entry, not the first' {
        Mock New-CIPPDbRequest { @(@{ id = 'AdminMFAV2'; controlStateUpdates = @(
                        @{ state = 'ignored'; updatedDateTime = '2024-01-01T00:00:00Z' }
                        @{ state = 'default'; updatedDateTime = '2025-06-01T00:00:00Z' }
                    ) } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ Default = @([PSCustomObject]@{ value = 'AdminMFAV2' }) } }
        $Prepared = Get-CIPPBaselineSecureScoreRemediationState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'no state updates means default - an ignored-list control with none is drift' {
        Mock New-CIPPDbRequest { @(@{ id = 'AdminMFAV2'; controlStateUpdates = @() } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ Ignored = @('AdminMFAV2') } }
        $Prepared = Get-CIPPBaselineSecureScoreRemediationState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
        $Prepared.Current.driftedControls[0].State | Should -Be 'ignored'
    }

    It 'never grades controls outside the configured lists' {
        Mock New-CIPPDbRequest { @(@{ id = 'SomeOtherControl'; controlStateUpdates = @(@{ state = 'thirdParty'; updatedDateTime = '2025-01-01T00:00:00Z' }) } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ Ignored = @('AdminMFAV2') } }
        $Prepared = Get-CIPPBaselineSecureScoreRemediationState -Item $Item -TenantFilter $script:Tenant
        @($Prepared.Current.controlsOutOfState) | Should -Not -Contain 'SomeOtherControl'
    }

    It 'skips Defender scid_ controls and bulk-patches the rest with the SecureScore vendor block' {
        Mock New-GraphBulkRequest { @([PSCustomObject]@{ id = '1'; status = 200 }) }
        $Current = [PSCustomObject]@{ driftedControls = @(
                [PSCustomObject]@{ Control = 'scid_2060'; State = 'ignored'; Reason = 'Ignored' }
                [PSCustomObject]@{ Control = 'AdminMFAV2'; State = 'ignored'; Reason = 'Ignored' }
            ) }
        Invoke-CIPPBaselineSecureScoreRemediation -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
            @($Requests).Count -eq 1 -and @($Requests)[0].url -like '*AdminMFAV2' -and @($Requests)[0].body.vendorInformation.provider -eq 'SecureScore'
        }
    }

    It 'throws only when EVERY control write fails - partial success is success' {
        Mock New-GraphBulkRequest { @([PSCustomObject]@{ id = '1'; status = 400; body = @{ error = @{ message = 'nope' } } }) }
        $Current = [PSCustomObject]@{ driftedControls = @([PSCustomObject]@{ Control = 'AdminMFAV2'; State = 'ignored'; Reason = 'Ignored' }) }
        { Invoke-CIPPBaselineSecureScoreRemediation -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $Current } | Should -Throw
    }
}
