# Pester tests for Get-CIPPIntuneAdminTemplateDefinitionValue.
#
# The updateDefinitionValues payload an administrative template stores and deploys. With
# -IncludeIdentity each setting also carries its name, category path, class and the position of each
# presentation within its definition, which is what lets a template deploy to a tenant whose imported
# ADMX minted different definition ids.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # Stubs mirror the real signatures so signature drift fails loudly here.
    function New-GraphGETRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp, $ComplexFilter) }
    function New-GraphBulkRequest { [CmdletBinding()] param($tenantid, $NoAuthCheck, $scope, $asapp, $Requests, $NoPaginateIds, $Version, $Headers) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneAdminTemplateDefinitionValue.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:PolicyId = '236811d6-6d40-4972-aec3-43624535508e'
    $script:FirefoxId = 'f65370a6-bc40-40af-b0f3-b6f5481478c0'
    $script:OneDriveId = '81c07ba0-7512-402d-b1f6-00856975cfab'
    $script:ListPresentationId = 'a73dada5-9cfc-44e7-b560-ebc1e1a1f1a9'
}

Describe 'Get-CIPPIntuneAdminTemplateDefinitionValue' {
    BeforeEach {
        Mock -CommandName New-GraphGETRequest -MockWith {
            if ($uri -like "*definitionValues?`$expand=definition") {
                @(
                    [pscustomobject]@{ id = 'dv-firefox'; enabled = $true; definition = [pscustomobject]@{ id = $script:FirefoxId; displayName = 'SPNEGO'; classType = 'machine'; policyType = 'admxIngested' } }
                    [pscustomobject]@{ id = 'dv-onedrive'; enabled = $false; definition = [pscustomobject]@{ id = $script:OneDriveId; displayName = 'Silently sign in users'; classType = 'machine'; policyType = 'admxIngested' } }
                )
            } elseif ($uri -like "*definitionValues('dv-firefox')/presentationValues*") {
                @(
                    [pscustomobject]@{ id = 'pv-1'; '@odata.type' = '#microsoft.graph.groupPolicyPresentationValueList'; values = @(@{ name = 'https://intranet.example' }); presentation = [pscustomobject]@{ id = $script:ListPresentationId; label = ''; '@odata.type' = '#microsoft.graph.groupPolicyPresentationListBox' } }
                )
            } elseif ($uri -like "*definitionValues('dv-onedrive')/presentationValues*") {
                @()
            } else { throw "unexpected GET $uri" }
        }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            foreach ($Request in $Requests) {
                switch -Wildcard ($Request.id) {
                    "definition-$($script:FirefoxId)" { [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ id = $script:FirefoxId; displayName = 'SPNEGO'; categoryPath = '\Mozilla\Firefox\Authentication'; classType = 'machine'; policyType = 'admxIngested' } } }
                    "definition-$($script:OneDriveId)" { [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ id = $script:OneDriveId; displayName = 'Silently sign in users'; categoryPath = '\OneDrive'; classType = 'machine'; policyType = 'admxIngested' } } }
                    "presentations-$($script:FirefoxId)" {
                        [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = @(
                                    [pscustomobject]@{ id = 'p-check'; label = 'Enable'; '@odata.type' = '#microsoft.graph.groupPolicyPresentationCheckBox' }
                                    [pscustomobject]@{ id = $script:ListPresentationId; label = ''; '@odata.type' = '#microsoft.graph.groupPolicyPresentationListBox' }
                                ) }
                        }
                    }
                    "presentations-$($script:OneDriveId)" { [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = @() } } }
                }
            }
        }
    }

    Context 'the payload a live policy is compared with' {
        It 'binds each setting to its definition and keeps the values, with no identity metadata' {
            $Payload = Get-CIPPIntuneAdminTemplateDefinitionValue -PolicyId $script:PolicyId -TenantFilter $script:Tenant

            @($Payload.added).Count | Should -Be 2
            $Payload.added[0].'definition@odata.bind' | Should -Be "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$($script:FirefoxId)')"
            $Payload.added[0].enabled | Should -BeTrue
            $Payload.added[0].presentationValues[0].'presentation@odata.bind' | Should -Be "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$($script:FirefoxId)')/presentations('$($script:ListPresentationId)')"
            $Payload.added[0].presentationValues[0].values[0].name | Should -Be 'https://intranet.example'
            $Payload.added[0].PSObject.Properties.Name | Should -Not -Contain 'definition'
            $Payload.added[0].presentationValues[0].PSObject.Properties.Name | Should -Not -Contain 'presentation'
            $Payload.added[1].enabled | Should -BeFalse
            @($Payload.added[1].presentationValues).Count | Should -Be 0
            @($Payload.updated).Count | Should -Be 0
            @($Payload.deletedIds).Count | Should -Be 0
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
        }

        It 'uses definition values the caller already read instead of reading them again' {
            $Values = @([pscustomobject]@{ id = 'dv-onedrive'; enabled = $true; definition = [pscustomobject]@{ id = $script:OneDriveId } })
            $Payload = Get-CIPPIntuneAdminTemplateDefinitionValue -PolicyId $script:PolicyId -TenantFilter $script:Tenant -DefinitionValues $Values

            @($Payload.added).Count | Should -Be 1
            Should -Invoke New-GraphGETRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*expand=definition' }
        }
    }

    Context 'the payload a template stores (-IncludeIdentity)' {
        It 'records each setting''s name, category path and class next to its bind' {
            $Payload = Get-CIPPIntuneAdminTemplateDefinitionValue -PolicyId $script:PolicyId -TenantFilter $script:Tenant -IncludeIdentity

            $Payload.added[0].definition.id | Should -Be $script:FirefoxId
            $Payload.added[0].definition.displayName | Should -Be 'SPNEGO'
            $Payload.added[0].definition.categoryPath | Should -Be '\Mozilla\Firefox\Authentication'
            $Payload.added[0].definition.classType | Should -Be 'machine'
            $Payload.added[1].definition.categoryPath | Should -Be '\OneDrive'
        }

        It 'records each presentation''s label, type and position within its definition' {
            $Payload = Get-CIPPIntuneAdminTemplateDefinitionValue -PolicyId $script:PolicyId -TenantFilter $script:Tenant -IncludeIdentity

            $Presentation = $Payload.added[0].presentationValues[0].presentation
            $Presentation.id | Should -Be $script:ListPresentationId
            $Presentation.'@odata.type' | Should -Be '#microsoft.graph.groupPolicyPresentationListBox'
            $Presentation.index | Should -Be 1
        }

        It 'reads the definitions and their presentations in one batch' {
            $null = Get-CIPPIntuneAdminTemplateDefinitionValue -PolicyId $script:PolicyId -TenantFilter $script:Tenant -IncludeIdentity

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { @($Requests).Count -eq 4 -and $tenantid -eq $script:Tenant }
        }
    }
}
