# Pester tests for Resolve-CIPPIntuneAdminTemplateBinding.
#
# An administrative template stores its settings as groupPolicyDefinitions('<id>') binds. Built-in
# definitions have one id everywhere, but a definition from an imported ADMX file is minted with a new
# id in every tenant (and on every re-import), so the bind captured in one tenant does not exist in
# another. The resolver finds the same setting in the target tenant by the identity the template
# recorded next to the bind (name, category path, class) and rewrites the binds before deployment.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # Stubs mirror the real signatures so signature drift fails loudly here.
    function New-GraphGETRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp, $ComplexFilter) }
    function New-GraphBulkRequest { [CmdletBinding()] param($tenantid, $NoAuthCheck, $scope, $asapp, $Requests, $NoPaginateIds, $Version, $Headers) }
    function Write-LogMessage { [CmdletBinding()] param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $Sev2, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Resolve-CIPPIntuneAdminTemplateBinding.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:BuiltInId = '81c07ba0-7512-402d-b1f6-00856975cfab'
    $script:SourceFirefoxId = 'f65370a6-bc40-40af-b0f3-b6f5481478c0'
    $script:SourcePresentationId = 'a73dada5-9cfc-44e7-b560-ebc1e1a1f1a9'
    $script:TargetFirefoxId = '11111111-2222-3333-4444-555555555555'
    $script:TargetPresentationId = '66666666-7777-8888-9999-000000000000'

    function New-Bind([string]$DefinitionId, [string]$PresentationId) {
        $Bind = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$DefinitionId')"
        if ($PresentationId) { $Bind += "/presentations('$PresentationId')" }
        $Bind
    }

    # A template as New-CIPPIntuneTemplate stores it: one built-in setting and one imported (Firefox)
    # setting with a list presentation, each carrying its identity next to the bind.
    function New-Template {
        param([switch]$WithoutIdentity, $PresentationIdentity)
        $Firefox = [ordered]@{
            'definition@odata.bind' = New-Bind $script:SourceFirefoxId
            enabled                 = $true
            presentationValues      = @(
                [ordered]@{
                    '@odata.type'             = '#microsoft.graph.groupPolicyPresentationValueList'
                    id                        = 'pv-1'
                    'presentation@odata.bind' = New-Bind $script:SourceFirefoxId $script:SourcePresentationId
                    values                    = @(@{ name = 'https://intranet.example' })
                }
            )
        }
        if (-not $WithoutIdentity) {
            $Firefox.definition = [ordered]@{ id = $script:SourceFirefoxId; displayName = 'SPNEGO'; categoryPath = '\Mozilla\Firefox\Authentication'; classType = 'machine'; policyType = 'admxIngested' }
            $Firefox.presentationValues[0].presentation = if ($PSBoundParameters.ContainsKey('PresentationIdentity')) { $PresentationIdentity } else {
                [ordered]@{ id = $script:SourcePresentationId; label = ''; '@odata.type' = '#microsoft.graph.groupPolicyPresentationListBox'; index = 0 }
            }
        }
        [ordered]@{
            added      = @(
                [ordered]@{ 'definition@odata.bind' = New-Bind $script:BuiltInId; enabled = $true; presentationValues = @(); definition = [ordered]@{ id = $script:BuiltInId; displayName = 'Silently sign in users'; categoryPath = '\OneDrive'; classType = 'machine'; policyType = 'admxIngested' } }
                $Firefox
            )
            updated    = @()
            deletedIds = @()
        } | ConvertTo-Json -Depth 10 -Compress
    }

    # The batch reply for the existence check: 200 for ids the tenant has, 404 for the rest.
    function New-ExistenceReply($Requests, [string[]]$Present) {
        foreach ($Request in $Requests) {
            $Id = [regex]::Match($Request.url, "groupPolicyDefinitions\('([0-9a-f-]{36})'\)").Groups[1].Value
            if ($Present -contains $Id) {
                [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ id = $Id } }
            } else {
                [pscustomobject]@{ id = $Request.id; status = 404; body = [pscustomobject]@{ error = @{ code = 'NotFound' } } }
            }
        }
    }
}

Describe 'Resolve-CIPPIntuneAdminTemplateBinding' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
    }

    Context 'every definition already exists in the target tenant' {
        BeforeEach {
            Mock -CommandName New-GraphBulkRequest -MockWith { New-ExistenceReply -Requests $Requests -Present @($script:BuiltInId, $script:SourceFirefoxId) }
            Mock -CommandName New-GraphGETRequest -MockWith { throw "unexpected GET $uri" }
        }

        It 'keeps the binds as they are and strips the identity metadata Graph does not accept' {
            $Result = Resolve-CIPPIntuneAdminTemplateBinding -RawJSON (New-Template) -TenantFilter $script:Tenant -DisplayName 'Firefox'
            $Policy = $Result | ConvertFrom-Json

            $Policy.added[1].'definition@odata.bind' | Should -Be (New-Bind $script:SourceFirefoxId)
            $Policy.added[1].presentationValues[0].'presentation@odata.bind' | Should -Be (New-Bind $script:SourceFirefoxId $script:SourcePresentationId)
            $Policy.added[1].presentationValues[0].values[0].name | Should -Be 'https://intranet.example'
            $Policy.added[1].PSObject.Properties.Name | Should -Not -Contain 'definition'
            $Policy.added[1].presentationValues[0].PSObject.Properties.Name | Should -Not -Contain 'presentation'
            $Policy.added[0].PSObject.Properties.Name | Should -Not -Contain 'definition'
            Should -Invoke New-GraphGETRequest -Times 0 -Exactly
        }
    }

    Context 'an imported definition is missing and the template recorded its identity' {
        BeforeEach {
            Mock -CommandName New-GraphBulkRequest -MockWith { New-ExistenceReply -Requests $Requests -Present @($script:BuiltInId) }
            Mock -CommandName New-GraphGETRequest -MockWith {
                if ($uri -match 'presentations$') {
                    @(
                        [pscustomobject]@{ id = $script:TargetPresentationId; label = ''; '@odata.type' = '#microsoft.graph.groupPolicyPresentationListBox' }
                    )
                } elseif ($uri -match '\$filter=') {
                    @(
                        [pscustomobject]@{ id = 'aaaaaaaa-0000-0000-0000-000000000001'; displayName = 'NTLM'; categoryPath = '\Mozilla\Firefox\Authentication'; classType = 'machine' }
                        [pscustomobject]@{ id = $script:TargetFirefoxId; displayName = 'SPNEGO'; categoryPath = '\Mozilla\Firefox\Authentication'; classType = 'machine' }
                    )
                } else { throw "unexpected GET $uri" }
            }
        }

        It 'rewrites the definition and presentation binds to the target tenant ids' {
            $Result = Resolve-CIPPIntuneAdminTemplateBinding -RawJSON (New-Template) -TenantFilter $script:Tenant -DisplayName 'Firefox'
            $Policy = $Result | ConvertFrom-Json

            $Policy.added[0].'definition@odata.bind' | Should -Be (New-Bind $script:BuiltInId)
            $Policy.added[1].'definition@odata.bind' | Should -Be (New-Bind $script:TargetFirefoxId)
            $Policy.added[1].presentationValues[0].'presentation@odata.bind' | Should -Be (New-Bind $script:TargetFirefoxId $script:TargetPresentationId)
            $Policy.added[1].presentationValues[0].'@odata.type' | Should -Be '#microsoft.graph.groupPolicyPresentationValueList'
            $Policy.added[1].presentationValues[0].values[0].name | Should -Be 'https://intranet.example'
            $Policy.added[1].enabled | Should -BeTrue
            $Policy.added[1].PSObject.Properties.Name | Should -Not -Contain 'definition'
            $Policy.added[1].presentationValues[0].PSObject.Properties.Name | Should -Not -Contain 'presentation'
        }

        It 'looks the setting up by class and category path' {
            $null = Resolve-CIPPIntuneAdminTemplateBinding -RawJSON (New-Template) -TenantFilter $script:Tenant -DisplayName 'Firefox'

            Should -Invoke New-GraphGETRequest -Times 1 -Exactly -ParameterFilter {
                $uri -like '*groupPolicyDefinitions?*' -and $uri -like "*classType eq 'machine'*" -and $uri -like "*categoryPath eq '\Mozilla\Firefox\Authentication'*" -and $tenantid -eq $script:Tenant
            }
        }
    }

    Context 'the target definition has several presentations' {
        BeforeEach {
            Mock -CommandName New-GraphBulkRequest -MockWith { New-ExistenceReply -Requests $Requests -Present @($script:BuiltInId) }
            Mock -CommandName New-GraphGETRequest -MockWith {
                if ($uri -match 'presentations$') {
                    @(
                        [pscustomobject]@{ id = 'p-text'; label = 'Realm'; '@odata.type' = '#microsoft.graph.groupPolicyPresentationTextBox' }
                        [pscustomobject]@{ id = 'p-list'; label = 'Servers'; '@odata.type' = '#microsoft.graph.groupPolicyPresentationListBox' }
                    )
                } else {
                    @([pscustomobject]@{ id = $script:TargetFirefoxId; displayName = 'SPNEGO'; categoryPath = '\Mozilla\Firefox\Authentication'; classType = 'machine' })
                }
            }
        }

        It 'prefers a label match over the recorded position' {
            $Identity = [ordered]@{ id = $script:SourcePresentationId; label = 'Servers'; '@odata.type' = '#microsoft.graph.groupPolicyPresentationListBox'; index = 0 }
            $Policy = Resolve-CIPPIntuneAdminTemplateBinding -RawJSON (New-Template -PresentationIdentity $Identity) -TenantFilter $script:Tenant -DisplayName 'Firefox' | ConvertFrom-Json

            $Policy.added[1].presentationValues[0].'presentation@odata.bind' | Should -Be (New-Bind $script:TargetFirefoxId 'p-list')
        }

        It 'falls back to the recorded position when the label is empty' {
            $Identity = [ordered]@{ id = $script:SourcePresentationId; label = ''; '@odata.type' = '#microsoft.graph.groupPolicyPresentationListBox'; index = 1 }
            $Policy = Resolve-CIPPIntuneAdminTemplateBinding -RawJSON (New-Template -PresentationIdentity $Identity) -TenantFilter $script:Tenant -DisplayName 'Firefox' | ConvertFrom-Json

            $Policy.added[1].presentationValues[0].'presentation@odata.bind' | Should -Be (New-Bind $script:TargetFirefoxId 'p-list')
        }

        It 'matches by type when the recorded position points at a field of another type' {
            $Identity = [ordered]@{ id = $script:SourcePresentationId; label = ''; '@odata.type' = '#microsoft.graph.groupPolicyPresentationListBox'; index = 0 }
            $Policy = Resolve-CIPPIntuneAdminTemplateBinding -RawJSON (New-Template -PresentationIdentity $Identity) -TenantFilter $script:Tenant -DisplayName 'Firefox' | ConvertFrom-Json

            $Policy.added[1].presentationValues[0].'presentation@odata.bind' | Should -Be (New-Bind $script:TargetFirefoxId 'p-list')
        }
    }

    Context 'the ADMX has not been imported into the target tenant' {
        BeforeEach {
            Mock -CommandName New-GraphBulkRequest -MockWith { New-ExistenceReply -Requests $Requests -Present @($script:BuiltInId) }
            Mock -CommandName New-GraphGETRequest -MockWith { @() }
        }

        It 'names the missing setting and says to import the ADMX into that tenant' {
            { Resolve-CIPPIntuneAdminTemplateBinding -RawJSON (New-Template) -TenantFilter $script:Tenant -DisplayName 'Firefox' } |
                Should -Throw -ExpectedMessage "*'SPNEGO'*\Mozilla\Firefox\Authentication*Import the same ADMX*$($script:Tenant)*"
        }
    }

    Context 'a template captured before the identity was recorded' {
        BeforeEach {
            Mock -CommandName New-GraphBulkRequest -MockWith { New-ExistenceReply -Requests $Requests -Present @($script:BuiltInId) }
            Mock -CommandName New-GraphGETRequest -MockWith { throw "unexpected GET $uri" }
        }

        It 'explains that the template must be re-created from the source tenant' {
            { Resolve-CIPPIntuneAdminTemplateBinding -RawJSON (New-Template -WithoutIdentity) -TenantFilter $script:Tenant -DisplayName 'Firefox' } |
                Should -Throw -ExpectedMessage "*$($script:SourceFirefoxId)*Re-create the template*"
        }
    }

    Context 'a template with no settings' {
        It 'returns the payload untouched without calling Graph' {
            Mock -CommandName New-GraphBulkRequest -MockWith { throw 'unexpected batch' }
            $RawJSON = '{"added":[],"updated":[],"deletedIds":[]}'

            @((Resolve-CIPPIntuneAdminTemplateBinding -RawJSON $RawJSON -TenantFilter $script:Tenant | ConvertFrom-Json).added).Count | Should -Be 0
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
        }
    }
}
