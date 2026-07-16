# Pester tests for Invoke-NinjaOneTenantSync
#
# Scope (per "solid coverage" agreement): happy-path end-to-end plus key
# error/edge branches per major section. Deep internals of the optional
# UserDocuments/LicenseDocuments related-items linking flows are exercised
# only at the "does it run without throwing / batch call happens" level —
# not every one of the 17 Invoke-WebRequest call sites is asserted
# individually, since that would require disproportionate fixture effort
# relative to this file's actual bug surface (CVE scan-group auto-create,
# GH issue #6349).
#
# Strategy: Get-CIPPTable is stubbed (not Mocked) to tag its returned
# Context with the requested table name, so downstream
# Get-CIPPAzDataTableEntity / Add-CIPPAzDataTableEntity mocks can
# distinguish table + filter combinations via -ParameterFilter.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CippExtensions/Public/NinjaOne/Invoke-NinjaOneTenantSync.ps1'

    # Minimal stubs so Mock has commands to replace during tests.
    function Get-CIPPTable { param($tablename) @{ Context = $tablename } }
    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Remove-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-Tenants { param([switch]$IncludeErrors) }
    function Write-LogMessage { param($tenant, $API, $message, $Sev, $LogData) }
    function Get-NinjaOneToken { param($configuration) }
    function Invoke-WebRequest { param($Uri, $Method, $Headers, $ContentType, $Body) }
    function Invoke-RestMethod { param($Uri, $Method, $Headers, $ContentType, $Body) }
    function Get-CippExtensionReportingData { param($TenantFilter, [switch]$IncludeMailboxes) }
    function Get-NinjaOneLinks { param($Data, $Title, $SmallCols, $MedCols, $LargeCols, $XLCols) }
    function Get-NinjaOneInfoCard { param($Title, $Data, $Icon) }
    function Get-NinjaOneCard { param($Title, $Body, $Icon, $TitleLink) }
    function Get-NinjaOneWidgetCard { param($Title, $Data, $Icon) }
    function Get-NinjaInLineBarGraph { param($Title, $Data, [switch]$KeyInLine) }
    function Get-SharePointAdminLink { param($TenantFilter) }
    function Get-CIPPStandards { param($TenantFilter) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }
    function Get-NormalizedError { param($Message) $Message }
    function New-CIPPGraphSubscription { param($TenantFilter, $Type) }
    function New-VulnCsvBytes { param($Rows, $Headers) }
    function Invoke-NinjaOneDocumentTemplate { param($TenantFilter, $TemplateName) }
    function Invoke-NinjaOneVulnCsvUpload { param($Uri, $PollUri, $CsvBytes, $Headers) }
    function Get-CIPPDbItem { param($TenantFilter, $Type) }
    function Resolve-NinjaOneCveScanGroup { param($Configuration, $TenantFilter, $ScanGroupName, $NinjaBaseUrl, $Token) }
    function convert-skuname { param($skuname) $skuname }

    . $FunctionPath

    function New-DefaultConfiguration {
        [pscustomobject]@{
            Instance                = 'app.ninjarmm.com'
            UserDocumentsEnabled    = $false
            LicenseDocumentsEnabled = $false
            LicensedOnly            = $false
            CveSyncEnabled          = $true
            CveSyncPrefix           = 'CIPP-'
            CveSyncDeviceIdHeader   = 'deviceName'
            CveSyncCveIdHeader      = 'cveId'
        }
    }

    function New-DefaultQueueItem {
        [pscustomobject]@{
            MappedTenant = [pscustomobject]@{
                RowKey        = 'contoso-tenant-id'
                IntegrationId = '918273'
            }
        }
    }
}

Describe 'Invoke-NinjaOneTenantSync' {

    BeforeEach {
        # --- Common baseline mocks used by (almost) every test ---
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-NinjaOneToken -MockWith { [pscustomobject]@{ access_token = 'fake-token' } }

        Mock -CommandName Get-Tenants -MockWith {
            @([pscustomobject]@{
                    customerId         = 'contoso-tenant-id'
                    defaultDomainName  = 'contoso.onmicrosoft.com'
                    displayName        = 'Contoso Ltd'
                    initialDomainName  = 'contoso.onmicrosoft.com'
                })
        }

        # CippMapping table: two different partitions are read via the same
        # table/context — the sync-lock lookup (NinjaOneMapping) and the
        # field-mapping lookup (NinjaOneFieldMapping). Default: no active
        # lock, no field mappings (keeps the HTML/summary-card machinery
        # entirely skipped for the core happy path).
        Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter {
            $Context -eq 'CippMapping' -and $Filter -eq "PartitionKey eq 'NinjaOneMapping'"
        } -MockWith {
            @([pscustomobject]@{
                    RowKey        = 'contoso-tenant-id'
                    lastStartTime = $null
                    lastEndTime   = $null
                })
        }

        Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter {
            $Context -eq 'CippMapping' -and $Filter -eq "PartitionKey eq 'NinjaOneFieldMapping'"
        } -MockWith { @() }

        Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter { $Context -eq 'Config' } -MockWith { @() }

        Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter { $Context -eq 'Extensionsconfig' } -MockWith {
            [pscustomobject]@{ config = (@{ NinjaOne = (New-DefaultConfiguration) } | ConvertTo-Json -Depth 10) }
        }

        Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter { $Context -eq 'CacheNinjaOneParsedDevices' } -MockWith { @() }
        Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter { $Context -eq 'NinjaOneDeviceMap' } -MockWith { @() }
        Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter { $Context -eq 'CacheNinjaOneParsedUsers' } -MockWith { @() }
        Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter { $Context -eq 'CacheNinjaOneUsersUpdate' } -MockWith { @() }
        Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter { $Context -eq 'NinjaOneUserMap' } -MockWith { @() }
        Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter { $Context -eq 'CveExceptions' } -MockWith { @() }

        # $CurrentItem is a single mutable object that the function under test
        # mutates in place (via Add-Member -Force) and re-passes to
        # Add-CIPPAzDataTableEntity multiple times (Running, then
        # Completed/Failed). Pester's Should -Invoke -ParameterFilter
        # re-evaluates filters against the *current* state of each recorded
        # call's arguments, not a snapshot taken at call time - so once the
        # shared object is mutated to 'Completed', every historical call
        # appears to match. Capture an immutable clone of $Entity on every
        # call so assertions can check actual per-call state.
        $script:RecordedEntities = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            if ($null -ne $Entity) {
                $script:RecordedEntities.Add(($Entity | ConvertTo-Json -Depth 10 | ConvertFrom-Json))
            }
        }
        Mock -CommandName Remove-AzDataTableEntity -MockWith { }

        # Empty extension-cache data by default — this keeps the device/user
        # processing loops, tenant-summary cards, and doc-toggle blocks from
        # ever executing their bodies (empty collections => no iterations).
        Mock -CommandName Get-CippExtensionReportingData -MockWith {
            [pscustomobject]@{
                Users                     = @()
                AllRoles                  = @()
                Devices                   = @()
                DeviceCompliancePolicies  = @()
                OneDriveUsage             = @()
                CASMailbox                = @()
                Mailboxes                 = @()
                MailboxUsage              = @()
                MailboxPermissions        = @()
                SecureScore               = @()
                SecureScoreControlProfiles = @()
                Organization              = [pscustomobject]@{ createdDateTime = '2020-01-01T00:00:00Z' }
                Domains                   = @()
                Groups                    = @()
                Licenses                  = @()
                ConditionalAccess         = @()
            }
        }

        # Device fetch — one page, below PageSize, so the pagination loop
        # terminates after a single call.
        Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri -like '*devices-detailed*' } -MockWith {
            [pscustomobject]@{ content = (@() | ConvertTo-Json -Depth 10) }
        }

        # Final org-level custom-fields PATCH — succeeds by default.
        Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri -like '*/organization/*/custom-fields' } -MockWith {
            [pscustomobject]@{ content = (@{ success = $true } | ConvertTo-Json) }
        }

        # CVE sync — scan group resolves, no vulnerability data by default.
        Mock -CommandName Resolve-NinjaOneCveScanGroup -MockWith {
            [pscustomobject]@{ id = 'scan-group-1'; deviceIdHeader = 'deviceName'; cveIdHeader = 'cveId' }
        }
        Mock -CommandName Get-CIPPDbItem -MockWith { @() }
        Mock -CommandName New-VulnCsvBytes -MockWith { @() }
    }

    Context 'Happy path (docs disabled, CVE sync enabled)' {
        It 'completes successfully and records lastStatus Completed' {
            $Result = Invoke-NinjaOneTenantSync -QueueItem (New-DefaultQueueItem)

            $Result | Should -Be $true
            @($script:RecordedEntities | Where-Object { $_.lastStatus -eq 'Completed' }).Count | Should -Be 1
            @($script:RecordedEntities | Where-Object { $_.lastStatus -eq 'Running' }).Count | Should -Be 1
        }

        It 'fetches devices and posts the final org custom-fields update' {
            Invoke-NinjaOneTenantSync -QueueItem (New-DefaultQueueItem) | Out-Null

            Should -Invoke Invoke-WebRequest -ParameterFilter { $Uri -like '*devices-detailed*' } -Times 1 -Exactly
            Should -Invoke Invoke-WebRequest -ParameterFilter { $Method -eq 'PATCH' -and $Uri -like '*/organization/*/custom-fields' } -Times 1 -Exactly
        }

        It 'does not call UserDocuments or LicenseDocuments endpoints when both toggles are disabled' {
            Invoke-NinjaOneTenantSync -QueueItem (New-DefaultQueueItem) | Out-Null

            Should -Invoke Invoke-WebRequest -ParameterFilter { $Uri -like '*organization/documents*' } -Times 0 -Exactly
        }
    }

    Context 'Concurrency guard' {
        It 'throws and does not process when a sync is already running for the tenant' {
            # NOTE: the source parses `lastStartTime` with `Get-Date($string)`,
            # which returns a Kind=Local DateTime, then compares it directly
            # against `(Get-Date).ToUniversalTime()` (Kind=Utc). .NET's
            # comparison operators ignore Kind and compare raw ticks, so this
            # comparison is off by the host's UTC offset (tracked upstream as
            # KelvinTegelaar/CIPP#6351 - not fixed here, out of scope for #6349).
            # To keep this test deterministic across hosts in any timezone,
            # build the mock timestamp the same way the guard will actually
            # read it back: pick a UTC instant that, once shifted by the
            # local offset (as the buggy parse does), reads as "now" - i.e.
            # comfortably within the "still running" window on this host.
            $LocalOffset = [System.TimeZoneInfo]::Local.GetUtcOffset((Get-Date))
            $MockStartTime = ((Get-Date).ToUniversalTime() - $LocalOffset).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

            Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter {
                $Context -eq 'CippMapping' -and $Filter -eq "PartitionKey eq 'NinjaOneMapping'"
            } -MockWith {
                @([pscustomobject]@{
                        RowKey        = 'contoso-tenant-id'
                        lastStartTime = $MockStartTime
                        lastEndTime   = $null
                    })
            }

            $Result = Invoke-NinjaOneTenantSync -QueueItem (New-DefaultQueueItem)

            # The function's try/catch always returns $true — failure is
            # observable only via the logged 'Failed' status and the fact
            # that no device fetch happened.
            $Result | Should -Be $true
            Should -Invoke Invoke-WebRequest -ParameterFilter { $Uri -like '*devices-detailed*' } -Times 0 -Exactly
            Should -Invoke Write-LogMessage -ParameterFilter { $Sev -eq 'Error' -and $message -like '*still running*' } -Times 1 -Exactly
        }
    }

    Context 'Tenant match validation' {
        It 'fails when the tenant cannot be uniquely matched' {
            Mock -CommandName Get-Tenants -MockWith { @() }

            $Result = Invoke-NinjaOneTenantSync -QueueItem (New-DefaultQueueItem)

            $Result | Should -Be $true
            Should -Invoke Invoke-WebRequest -ParameterFilter { $Uri -like '*devices-detailed*' } -Times 0 -Exactly
            Should -Invoke Write-LogMessage -ParameterFilter { $Sev -eq 'Error' -and $message -like '*Failed NinjaOne Processing*' } -Times 1 -Exactly
        }
    }

    Context 'Hostname validation' {
        It 'fails when the configured NinjaOne instance is not an allow-listed hostname' {
            Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter { $Context -eq 'Extensionsconfig' } -MockWith {
                $BadConfig = New-DefaultConfiguration
                $BadConfig.Instance = 'evil.example.com'
                [pscustomobject]@{ config = (@{ NinjaOne = $BadConfig } | ConvertTo-Json -Depth 10) }
            }

            $Result = Invoke-NinjaOneTenantSync -QueueItem (New-DefaultQueueItem)

            $Result | Should -Be $true
            Should -Invoke Invoke-WebRequest -ParameterFilter { $Uri -like '*devices-detailed*' } -Times 0 -Exactly
            Should -Invoke Write-LogMessage -ParameterFilter { $Sev -eq 'Error' -and $message -like '*NinjaOne URL is invalid*' } -Times 1 -Exactly
        }
    }

    Context 'CVE sync' {
        It 'uploads CVE rows built from vulnerability data when vulnerabilities exist' {
            Mock -CommandName Get-CIPPDbItem -MockWith {
                @([pscustomobject]@{
                        RowKey = 'CVE-2024-0001'
                        Data   = (@{ cveId = 'CVE-2024-0001'; deviceDetailsJson = (@(@{ deviceName = 'PC01' }) | ConvertTo-Json) } | ConvertTo-Json)
                    })
            }
            Mock -CommandName New-VulnCsvBytes -MockWith { [byte[]](1, 2, 3) }
            Mock -CommandName Invoke-NinjaOneVulnCsvUpload -MockWith {
                [pscustomobject]@{ status = 'COMPLETE'; recordsProcessed = 1 }
            }

            Invoke-NinjaOneTenantSync -QueueItem (New-DefaultQueueItem) | Out-Null

            Should -Invoke Resolve-NinjaOneCveScanGroup -Times 1 -Exactly
            Should -Invoke Invoke-NinjaOneVulnCsvUpload -Times 1 -Exactly
            Should -Invoke Write-LogMessage -ParameterFilter { $Sev -eq 'Info' -and $message -like '*CVE sync complete*' } -Times 1 -Exactly
        }

        It 'logs a warning and uploads a placeholder row when no vulnerability data is returned' {
            Mock -CommandName Get-CIPPDbItem -MockWith { @() }
            Mock -CommandName New-VulnCsvBytes -MockWith { [byte[]](1) }
            Mock -CommandName Invoke-NinjaOneVulnCsvUpload -MockWith { [pscustomobject]@{ status = 'COMPLETE'; recordsProcessed = 0 } }

            Invoke-NinjaOneTenantSync -QueueItem (New-DefaultQueueItem) | Out-Null

            Should -Invoke Write-LogMessage -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*no vulnerability data returned*' } -Times 1 -Exactly
        }

        It 'excludes CVEs covered by a tenant or ALL exception before uploading' {
            Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter { $Context -eq 'CveExceptions' } -MockWith {
                @([pscustomobject]@{ RowKey = 'ALL'; cveId = 'CVE-2024-0001' })
            }
            Mock -CommandName Get-CIPPDbItem -MockWith {
                @([pscustomobject]@{
                        RowKey = 'CVE-2024-0001'
                        Data   = (@{ cveId = 'CVE-2024-0001'; deviceDetailsJson = (@(@{ deviceName = 'PC01' }) | ConvertTo-Json) } | ConvertTo-Json)
                    })
            }
            Mock -CommandName New-VulnCsvBytes -MockWith { [byte[]](1) }
            Mock -CommandName Invoke-NinjaOneVulnCsvUpload -MockWith { [pscustomobject]@{ status = 'COMPLETE'; recordsProcessed = 0 } }

            Invoke-NinjaOneTenantSync -QueueItem (New-DefaultQueueItem) | Out-Null

            Should -Invoke Write-LogMessage -ParameterFilter { $message -like '*filtered 1 excepted CVEs, 0 remaining*' } -Times 1 -Exactly
        }

        It 'isolates a CVE sync failure so the overall tenant sync still completes' {
            Mock -CommandName Resolve-NinjaOneCveScanGroup -MockWith { throw 'NinjaOne API unavailable' }

            $Result = Invoke-NinjaOneTenantSync -QueueItem (New-DefaultQueueItem)

            $Result | Should -Be $true
            Should -Invoke Write-LogMessage -ParameterFilter { $Sev -eq 'Error' -and $message -like '*CVE sync failed*' } -Times 1 -Exactly
            @($script:RecordedEntities | Where-Object { $_.lastStatus -eq 'Completed' }).Count | Should -Be 1
        }

        It 'does not attempt CVE sync when CveSyncEnabled is disabled' {
            Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter { $Context -eq 'Extensionsconfig' } -MockWith {
                $NoConfig = New-DefaultConfiguration
                $NoConfig.CveSyncEnabled = $false
                [pscustomobject]@{ config = (@{ NinjaOne = $NoConfig } | ConvertTo-Json -Depth 10) }
            }

            Invoke-NinjaOneTenantSync -QueueItem (New-DefaultQueueItem) | Out-Null

            Should -Invoke Resolve-NinjaOneCveScanGroup -Times 0 -Exactly
        }
    }

    Context 'Final org custom-fields PATCH failure' {
        It 'propagates the failure to the outer catch and records lastStatus Failed' {
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri -like '*/organization/*/custom-fields' } -MockWith {
                throw 'NinjaOne API returned 500'
            }

            $Result = Invoke-NinjaOneTenantSync -QueueItem (New-DefaultQueueItem)

            $Result | Should -Be $true
            @($script:RecordedEntities | Where-Object { $_.lastStatus -eq 'Failed' }).Count | Should -Be 1
            Should -Invoke Write-LogMessage -ParameterFilter { $Sev -eq 'Error' -and $message -like '*Failed NinjaOne Processing*' } -Times 1 -Exactly
            # CVE sync runs after the final PATCH in the source, so a PATCH
            # failure should prevent CVE sync from ever being attempted.
            Should -Invoke Resolve-NinjaOneCveScanGroup -Times 0 -Exactly
        }
    }

    Context 'UserDocuments enabled' {
        BeforeEach {
            Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter { $Context -eq 'Extensionsconfig' } -MockWith {
                $Cfg = New-DefaultConfiguration
                $Cfg.UserDocumentsEnabled = $true
                [pscustomobject]@{ config = (@{ NinjaOne = $Cfg } | ConvertTo-Json -Depth 10) }
            }
            Mock -CommandName Get-CippExtensionReportingData -MockWith {
                [pscustomobject]@{
                    Users                      = @([pscustomobject]@{ id = 'u1'; userPrincipalName = 'user1@contoso.onmicrosoft.com'; displayName = 'User One'; accountEnabled = $true; assignedLicenses = @() })
                    AllRoles                   = @()
                    Devices                    = @()
                    DeviceCompliancePolicies   = @()
                    OneDriveUsage              = @()
                    CASMailbox                 = @()
                    Mailboxes                  = @()
                    MailboxUsage               = @()
                    MailboxPermissions         = @()
                    SecureScore                = @()
                    SecureScoreControlProfiles = @()
                    Organization               = [pscustomobject]@{ createdDateTime = '2020-01-01T00:00:00Z' }
                    Domains                    = @()
                    Groups                     = @()
                    Licenses                   = @()
                    ConditionalAccess          = @()
                }
            }
            Mock -CommandName Invoke-NinjaOneDocumentTemplate -MockWith { [pscustomobject]@{ id = '4001' } }
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri -like '*organization/documents*' -and $Method -eq 'GET' } -MockWith {
                [pscustomobject]@{ content = (@() | ConvertTo-Json) }
            }
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri -like '*organization/documents*' -and $Method -eq 'POST' } -MockWith {
                [pscustomobject]@{ content = (@(@{ id = 'doc-1' }) | ConvertTo-Json) }
            }
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri -like '*organization/documents*' -and $Method -eq 'PATCH' } -MockWith {
                [pscustomobject]@{ content = (@(@{ id = 'doc-1' }) | ConvertTo-Json) }
            }
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri -like '*related-items*' } -MockWith {
                [pscustomobject]@{ content = (@() | ConvertTo-Json) }
            }
        }

        It 'completes successfully when creating user documents for new users' {
            $Result = Invoke-NinjaOneTenantSync -QueueItem (New-DefaultQueueItem)

            $Result | Should -Be $true
            @($script:RecordedEntities | Where-Object { $_.lastStatus -eq 'Completed' }).Count | Should -Be 1
        }

        It 'does not rethrow when the user-document batch create call fails' {
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri -like '*organization/documents*' -and $Method -eq 'POST' } -MockWith {
                throw 'NinjaOne document API error'
            }

            $Result = Invoke-NinjaOneTenantSync -QueueItem (New-DefaultQueueItem)

            $Result | Should -Be $true
            @($script:RecordedEntities | Where-Object { $_.lastStatus -eq 'Completed' }).Count | Should -Be 1
        }
    }

    Context 'LicenseDocuments enabled' {
        BeforeEach {
            Mock -CommandName Get-CIPPAzDataTableEntity -ParameterFilter { $Context -eq 'Extensionsconfig' } -MockWith {
                $Cfg = New-DefaultConfiguration
                $Cfg.LicenseDocumentsEnabled = $true
                [pscustomobject]@{ config = (@{ NinjaOne = $Cfg } | ConvertTo-Json -Depth 10) }
            }
            Mock -CommandName Get-CippExtensionReportingData -MockWith {
                [pscustomobject]@{
                    Users                      = @()
                    AllRoles                   = @()
                    Devices                    = @()
                    DeviceCompliancePolicies   = @()
                    OneDriveUsage              = @()
                    CASMailbox                 = @()
                    Mailboxes                  = @()
                    MailboxUsage               = @()
                    MailboxPermissions         = @()
                    SecureScore                = @()
                    SecureScoreControlProfiles = @()
                    Organization               = [pscustomobject]@{ createdDateTime = '2020-01-01T00:00:00Z' }
                    Domains                    = @()
                    Groups                     = @()
                    Licenses                   = @([pscustomobject]@{ skuId = 'sku-1'; skuPartNumber = 'ENTERPRISEPACK'; prepaidUnits = @{ enabled = 10 }; consumedUnits = 5 })
                    ConditionalAccess          = @()
                }
            }
            Mock -CommandName Invoke-NinjaOneDocumentTemplate -MockWith { [pscustomobject]@{ id = '4002' } }
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri -like '*organization/documents*' -and $Method -eq 'GET' } -MockWith {
                [pscustomobject]@{ content = (@() | ConvertTo-Json) }
            }
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri -like '*organization/documents*' -and $Method -eq 'POST' } -MockWith {
                [pscustomobject]@{ content = (@(@{ id = 'lic-doc-1' }) | ConvertTo-Json) }
            }
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri -like '*organization/documents*' -and $Method -eq 'PATCH' } -MockWith {
                [pscustomobject]@{ content = (@(@{ id = 'lic-doc-1' }) | ConvertTo-Json) }
            }
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri -like '*related-items*' } -MockWith {
                [pscustomobject]@{ content = (@() | ConvertTo-Json) }
            }
        }

        It 'completes successfully when creating license documents, using convert-skuname for friendly names' {
            $Result = Invoke-NinjaOneTenantSync -QueueItem (New-DefaultQueueItem)

            $Result | Should -Be $true
            @($script:RecordedEntities | Where-Object { $_.lastStatus -eq 'Completed' }).Count | Should -Be 1
        }

        It 'does not rethrow when the license-document batch create call fails' {
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri -like '*organization/documents*' -and $Method -eq 'POST' } -MockWith {
                throw 'NinjaOne document API error'
            }

            $Result = Invoke-NinjaOneTenantSync -QueueItem (New-DefaultQueueItem)

            $Result | Should -Be $true
            @($script:RecordedEntities | Where-Object { $_.lastStatus -eq 'Completed' }).Count | Should -Be 1
        }
    }
}
