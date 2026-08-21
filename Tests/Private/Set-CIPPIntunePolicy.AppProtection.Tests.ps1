# Pester tests for the App Protection branch of Set-CIPPIntunePolicy.
#
# App Protection is one CIPP template type spanning several Graph collections, so the deploy URL is
# derived from the payload. Templates captured through a concrete collection carry no @odata.type -
# Graph omits it there - and deployment used to reject them before it reached Graph at all.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # Stubs mirror the real signatures so signature drift fails loudly here.
    function New-GraphGETRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp, $ComplexFilter) }
    function New-GraphPOSTRequest { [CmdletBinding()] param($uri, $tenantid, $type, $body, $AddedHeaders) }
    function Write-LogMessage { [CmdletBinding()] param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $Sev2, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) }
    function Get-CIPPTextReplacement { [CmdletBinding()] param([string]$TenantFilter, $Text, [switch]$EscapeForJson) }
    function Set-CIPPAssignedPolicy { [CmdletBinding()] param($GroupName, $PolicyId, $PlatformType, $Type, $TenantFilter, $ExcludeGroup, $AssignmentMode, $AssignmentFilterName, $AssignmentFilterType) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPAppProtectionPolicyUrl.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Find-CIPPFuzzyPolicyMatch.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPIntunePolicy.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'

    # The shape a template captured from iosManagedAppProtections has: no @odata.type, the type
    # recorded in @odata.context, and the read-only properties Graph echoed back on the capture.
    $script:IosTemplate = [ordered]@{
        '@odata.context'    = 'https://graph.microsoft.com/beta/$metadata#deviceAppManagement/iosManagedAppProtections/$entity'
        id                  = 'T_b3ed3c06-8c16-441d-976f-537352285d50'
        version             = '"871c2313-0000-0d00-0000-69dcdd6d0000"'
        createdDateTime     = '2026-04-10T12:15:06.8880574Z'
        lastModifiedDateTime = '2026-04-13T12:11:25Z'
        isAssigned          = $true
        deployedAppCount    = 11
        displayName         = 'App Protection - iOS'
        pinRequired         = $true
        faceIdBlocked       = $false
    } | ConvertTo-Json -Depth 10
}

Describe 'Set-CIPPIntunePolicy -TemplateType AppProtection' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPTextReplacement -MockWith { $Text }
        # Mirrors the real helper: a plain throw normalises to its own message, which is how the
        # reason reaches the standards run.
        Mock -CommandName Get-CippException -MockWith { [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }
        Mock -CommandName New-GraphGETRequest -MockWith { @() }
        Mock -CommandName New-GraphPOSTRequest -MockWith { [PSCustomObject]@{ id = 'new-policy-id' } }
        Mock -CommandName Set-CIPPAssignedPolicy -MockWith { }
    }

    Context 'a template that records its type only in @odata.context' {
        It 'deploys to the collection named in the context instead of throwing' {
            $Result = Set-CIPPIntunePolicy -TemplateType 'AppProtection' -DisplayName 'App Protection - iOS' `
                -Description 'desc' -RawJSON $script:IosTemplate -TenantFilter $script:Tenant

            $Result | Should -BeLike '*Successfully added policy*'
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $uri -eq 'https://graph.microsoft.com/beta/deviceAppManagement/iosManagedAppProtections' -and $type -eq 'POST'
            }
        }

        It 'looks for an existing policy in the same collection' {
            $null = Set-CIPPIntunePolicy -TemplateType 'AppProtection' -DisplayName 'App Protection - iOS' `
                -Description 'desc' -RawJSON $script:IosTemplate -TenantFilter $script:Tenant

            Should -Invoke New-GraphGETRequest -Times 1 -Exactly -ParameterFilter {
                $uri -eq 'https://graph.microsoft.com/beta/deviceAppManagement/iosManagedAppProtections'
            }
        }

        It 'strips the read-only properties Graph will not accept back' {
            $null = Set-CIPPIntunePolicy -TemplateType 'AppProtection' -DisplayName 'App Protection - iOS' `
                -Description 'desc' -RawJSON $script:IosTemplate -TenantFilter $script:Tenant

            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $Sent = $body | ConvertFrom-Json
                $Names = @($Sent.PSObject.Properties.Name)
                $Names -notcontains 'id' -and
                $Names -notcontains 'version' -and
                $Names -notcontains 'createdDateTime' -and
                $Names -notcontains 'lastModifiedDateTime' -and
                $Names -notcontains 'isAssigned' -and
                $Names -notcontains 'deployedAppCount' -and
                $Names -notcontains '@odata.context' -and
                $Sent.pinRequired -eq $true -and
                $Sent.displayName -eq 'App Protection - iOS'
            }
        }
    }

    Context 'a template that does carry @odata.type' {
        It 'still uses it, and uses it in preference to the context' {
            $RawJSON = [ordered]@{
                '@odata.type'    = '#microsoft.graph.androidManagedAppProtection'
                '@odata.context' = 'https://graph.microsoft.com/beta/$metadata#deviceAppManagement/managedAppPolicies/$entity'
                displayName      = 'App Protection - Android'
                pinRequired      = $true
            } | ConvertTo-Json -Depth 10

            $null = Set-CIPPIntunePolicy -TemplateType 'AppProtection' -DisplayName 'App Protection - Android' `
                -Description 'desc' -RawJSON $RawJSON -TenantFilter $script:Tenant

            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $uri -eq 'https://graph.microsoft.com/beta/deviceAppManagement/androidManagedAppProtections'
            }
        }
    }

    Context 'a template that identifies no platform' {
        It 'throws without calling Graph' {
            $RawJSON = '{"displayName":"Nameless","pinRequired":true}'

            { Set-CIPPIntunePolicy -TemplateType 'AppProtection' -DisplayName 'Nameless' `
                    -Description 'desc' -RawJSON $RawJSON -TenantFilter $script:Tenant } |
                Should -Throw -ExpectedMessage '*identifies no platform*'

            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }
    }
}
