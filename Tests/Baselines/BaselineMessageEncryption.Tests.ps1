# MessageEncryption is declarative: the ExoIRMConfiguration cache, an expected block and one
# Set-IRMConfiguration through the generic ExoRequest executor. These tests run the REAL
# definition through the REAL engine against a mocked cache row.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Set-CippBaselineRunContext { param($RunId) }
    function Update-CippQueueEntry { param($RowKey, $Status, $Name) }
    function Get-CippTable { param($tablename) @{} }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Add-CIPPBaselineHistoryEvent { param($TenantFilter, $Standard, $Mode, $TriggeredBy, $Outcome, $Detail, $RunId, $Remediated) }
    function Set-CIPPBaselineResult { param($Result, $Prior, $RunId) }
    function Send-CIPPBaselineAlert { param($Result) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Wait-CIPPBaselineCacheReady { param($TenantFilter, $Definition, $RunId) $false }
    function Set-CIPPDBCacheExoIRMConfiguration { param($TenantFilter) }
    function Invoke-CIPPBaselineExoRequest { param($Remediate, $TenantFilter, $Current) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Get-CIPPBaselineCommand.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Invoke-CIPPBaselineStandard.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Definition = Get-Content (Join-Path $script:RepoRoot 'Config/BaselineStandards/Exchange Standards/MessageEncryption.json') -Raw | ConvertFrom-Json

    function New-EngineItem {
        param($Variables)
        @{
            TenantFilter = $script:Tenant; Standard = 'MessageEncryption'; BaseName = 'MessageEncryption'
            Variables = $Variables; Tiers = @(); AlertEnabled = $false; RemediateEnabled = $true
        }
    }
    # Get-IRMConfiguration round-trips through the CIPPDb as JSON (verified live: TransportDecryptionSetting is the plain string).
    function New-CachedIrm {
        param([bool]$Licensing = $true, [bool]$ClientAccess = $true, [bool]$Pdf = $false, [string]$Transport = 'Optional')
        [PSCustomObject]@{
            AzureRMSLicensingEnabled                   = $Licensing
            SimplifiedClientAccessEnabled              = $ClientAccess
            EnablePdfEncryption                        = $Pdf
            DecryptAttachmentForEncryptOnly            = $false
            SimplifiedClientAccessDoNotForwardDisabled = $false
            SimplifiedClientAccessEncryptOnlyDisabled  = $false
            TransportDecryptionSetting                 = $Transport
            LicensingLocation                          = @('https://abc.rms.na.aadrm.com/_wmcs/licensing')
        } | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    }
}

Describe 'MessageEncryption definition' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition { $script:Definition }
        Mock Get-CIPPAzDataTableEntity { @() }
        Mock Set-CIPPBaselineResult { }
        Mock Add-CIPPBaselineHistoryEvent { }
        Mock Send-CIPPBaselineAlert { }
        Mock Write-LogMessage { }
        Mock Invoke-CIPPBaselineExoRequest { }
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ EXCHANGE_S_ENTERPRISE = $true } }
    }

    It 'keeps the classic variable names so V2 templates migrate' {
        $script:Definition.variables.PSObject.Properties.Name | Sort-Object | Should -Be @('DecryptAttachmentForEncryptOnly', 'EnablePdfEncryption', 'SimplifiedClientAccessDoNotForwardDisabled', 'SimplifiedClientAccessEncryptOnlyDisabled', 'TransportDecryptionSetting')
    }

    It 'offers real booleans on the switch-like pickers - a string "true" never equals the cached boolean' {
        foreach ($Name in 'EnablePdfEncryption', 'DecryptAttachmentForEncryptOnly', 'SimplifiedClientAccessDoNotForwardDisabled', 'SimplifiedClientAccessEncryptOnlyDisabled') {
            foreach ($Option in @($script:Definition.variables.$Name.options).Where({ "$($_.value)" })) { $Option.value | Should -BeOfType [bool] }
        }
    }

    Context 'grading' {
        It 'with every option left on Do not change, grades only licensing and the Encrypt button' {
            Mock New-CIPPDbRequest { New-CachedIrm -Pdf $true -Transport 'Mandatory' }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ EnablePdfEncryption = ''; TransportDecryptionSetting = '' })) -Mode 'compare'
            $Result.Compliant | Should -BeTrue
            $Result.ExpectedValue.PSObject.Properties.Name | Sort-Object | Should -Be @('AzureRMSLicensingEnabled', 'SimplifiedClientAccessEnabled')
        }

        It 'drifts when the Encrypt button (simplified client access) is off' {
            Mock New-CIPPDbRequest { New-CachedIrm -ClientAccess $false }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{})) -Mode 'compare'
            $Result.Compliant | Should -BeFalse
            @($Result.Diff).Property | Should -Contain 'SimplifiedClientAccessEnabled'
        }

        It 'drifts when Azure RMS licensing is off' {
            Mock New-CIPPDbRequest { New-CachedIrm -Licensing $false }
            (Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{})) -Mode 'compare').Compliant | Should -BeFalse
        }

        It 'grades a picked boolean as a boolean and a picked transport setting as its string' {
            Mock New-CIPPDbRequest { New-CachedIrm -Pdf $false -Transport 'Optional' }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ EnablePdfEncryption = [PSCustomObject]@{ label = 'Enable'; value = $true }; TransportDecryptionSetting = 'Optional' })) -Mode 'compare'
            $Result.ExpectedValue.EnablePdfEncryption | Should -BeExactly $true
            @($Result.Diff).Property | Should -Be @('EnablePdfEncryption')
        }

        It 'grades a picked Disable (false) as compliant against a cached false' {
            Mock New-CIPPDbRequest { New-CachedIrm -Pdf $false }
            (Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ EnablePdfEncryption = $false })) -Mode 'compare').Compliant | Should -BeTrue
        }

        It 'reports No Data rather than drift when the IRM cache is empty' {
            Mock New-CIPPDbRequest { @() }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{})) -Mode 'compare'
            $Result.Compliant | Should -BeFalse
            $Result.Outcome | Should -Not -Be 'Drift'
        }
    }

    Context 'remediation' {
        It 'hands ExoRequest one Set-IRMConfiguration with the required pair plus only the picked options' {
            Mock New-CIPPDbRequest { New-CachedIrm -ClientAccess $false }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ EnablePdfEncryption = $true; DecryptAttachmentForEncryptOnly = ''; TransportDecryptionSetting = 'Mandatory' })) -Mode 'oneoff'
            $Result.Remediated | Should -BeTrue
            Should -Invoke Invoke-CIPPBaselineExoRequest -Times 1 -Exactly -ParameterFilter {
                $Step = @($Remediate.cmdlets)
                $Params = $Step[0].params
                $Step.Count -eq 1 -and $Step[0].cmdlet -eq 'Set-IRMConfiguration' -and
                $Params.AzureRMSLicensingEnabled -eq $true -and $Params.SimplifiedClientAccessEnabled -eq $true -and
                $Params.EnablePdfEncryption -is [bool] -and $Params.EnablePdfEncryption -eq $true -and
                $Params.TransportDecryptionSetting -eq 'Mandatory' -and
                -not $Params.PSObject.Properties['DecryptAttachmentForEncryptOnly'] -and
                -not $Params.PSObject.Properties['SimplifiedClientAccessDoNotForwardDisabled'] -and
                (ConvertTo-Json -Compress -Depth 10 -InputObject $Remediate) -notmatch '%'
            }
        }

        It 'does not write when the tenant already complies' {
            Mock New-CIPPDbRequest { New-CachedIrm }
            $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{})) -Mode 'run'
            Should -Invoke Invoke-CIPPBaselineExoRequest -Times 0 -Exactly
        }
    }
}
