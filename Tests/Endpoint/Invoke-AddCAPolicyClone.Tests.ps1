# Pester tests for Invoke-AddCAPolicyClone, the Conditional Access "Duplicate Policy" action.
#
# The endpoint reads the tenant's policy list once, copies the source policy as-is under a new name and
# POSTs it. It deliberately skips the template deploy path (New-CIPPCAPolicy): that path drops app ids
# without a service principal and re-resolves auth strengths by name, so the copy would not be faithful.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Conditional/Invoke-AddCAPolicyClone.ps1'
    $FormatPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Format-CIPPCAPolicy.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Invoke-AddCAPolicyClone.ps1 at $FunctionPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphGetRequest { param($uri, $tenantid, $asApp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body, $asApp) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    # Mandatory like the real helper, which throws on an empty string instead of returning false.
    function Test-IsGuid { param([Parameter(Mandatory)][string]$String) [guid]::TryParse($String, [ref][guid]::Empty) }

    # The real canonicalizer, so the POSTed body is the shape Graph would actually receive.
    . $FormatPath
    . $FunctionPath

    $script:SourceId = '11111111-1111-1111-1111-111111111111'

    function New-CloneRequest {
        param([hashtable]$Body = @{}, [hashtable]$Query = @{})
        $RequestBody = [pscustomobject]@{
            tenantFilter   = 'contoso.com'
            ID             = $script:SourceId
            newDisplayName = 'Require MFA - Copy'
        }
        foreach ($Key in $Body.Keys) {
            $RequestBody | Add-Member -NotePropertyName $Key -NotePropertyValue $Body[$Key] -Force
        }
        [pscustomobject]@{
            Body    = $RequestBody
            Query   = [pscustomobject]$Query
            Headers = @{}
            Params  = @{ CIPPEndpoint = 'AddCAPolicyClone' }
        }
    }
}

Describe 'Invoke-AddCAPolicyClone' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        $script:PostedBody = $null
        Mock -CommandName New-GraphPOSTRequest -MockWith { $script:PostedBody = $body | ConvertFrom-Json; [pscustomobject]@{ id = 'new-guid' } }
        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{
                    id               = $script:SourceId
                    templateId       = $null
                    displayName      = 'Require MFA'
                    createdDateTime  = '2026-01-01T00:00:00Z'
                    modifiedDateTime = '2026-02-01T00:00:00Z'
                    state            = 'enabled'
                    conditions       = [pscustomobject]@{
                        clientAppTypes = @('all')
                        users          = [pscustomobject]@{ includeUsers = @('All'); excludeGroups = @('group-guid') }
                        applications   = [pscustomobject]@{
                            includeApplications = @('All')
                            # Intune Enrollment, often without a service principal - must survive the copy.
                            excludeApplications = @('d4ebce55-015a-49b5-a083-c84d1797ae8c')
                        }
                    }
                    grantControls    = [pscustomobject]@{
                        operator                                = 'OR'
                        builtInControls                         = @()
                        'authenticationStrength@odata.context'  = 'https://graph.microsoft.com/beta/$metadata#...'
                        authenticationStrength                  = [pscustomobject]@{ id = 'strength-guid'; displayName = 'Phishing-resistant'; allowedCombinations = @('fido2') }
                    }
                    sessionControls  = $null
                }
                [pscustomobject]@{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Block legacy auth'; state = 'enabled' }
            )
        }
    }

    Context 'input validation' {
        It 'returns 400 for <Case> without calling Graph' -ForEach @(
            @{ Case = 'a missing tenantFilter'; Body = @{ tenantFilter = '' } }
            @{ Case = 'AllTenants'; Body = @{ tenantFilter = 'AllTenants' } }
            @{ Case = 'a missing ID'; Body = @{ ID = '' } }
            @{ Case = 'a non-GUID ID'; Body = @{ ID = '../namedLocations/x' } }
            @{ Case = 'a blank name'; Body = @{ newDisplayName = '   ' } }
            @{ Case = 'an unsupported state'; Body = @{ state = 'donotchange' } }
        ) {
            $Response = Invoke-AddCAPolicyClone -Request (New-CloneRequest -Body $Body)

            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            Should -Invoke New-GraphGetRequest -Times 0 -Exactly
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }

        It 'returns 400 for <Case>' -ForEach @(
            @{ Case = 'the source name'; Name = 'Require MFA' }
            @{ Case = 'the source name with surrounding whitespace'; Name = '  Require MFA ' }
            @{ Case = 'another policy name in a different case'; Name = 'BLOCK LEGACY AUTH' }
        ) {
            $Response = Invoke-AddCAPolicyClone -Request (New-CloneRequest -Body @{ newDisplayName = $Name })

            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -Match 'already exists'
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }

        It 'returns 404 when the policy is not in the tenant' {
            $Response = Invoke-AddCAPolicyClone -Request (New-CloneRequest -Body @{ ID = '33333333-3333-3333-3333-333333333333' })

            $Response.StatusCode | Should -Be ([HttpStatusCode]::NotFound)
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }
    }

    Context 'copy' {
        It 'reads the policy list of the requested tenant' {
            $null = Invoke-AddCAPolicyClone -Request (New-CloneRequest)

            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter {
                $uri -like 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies*' -and $tenantid -eq 'contoso.com'
            }
        }

        # Test-CIPPAccess checks Query.tenantFilter before the body. Acting on the body tenant instead would
        # let a caller pass RBAC with an allowed tenant in the query and clone in a forbidden one.
        It 'acts on the tenant RBAC checked when query and body disagree' {
            $null = Invoke-AddCAPolicyClone -Request (New-CloneRequest -Query @{ tenantFilter = 'allowed.com' } -Body @{ tenantFilter = 'forbidden.com' })

            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'allowed.com' }
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'allowed.com' }
        }

        It 'accepts a tenant selector object in the body' {
            $null = Invoke-AddCAPolicyClone -Request (New-CloneRequest -Body @{ tenantFilter = [pscustomobject]@{ value = 'contoso.com'; label = 'Contoso' } })

            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'contoso.com' }
        }

        It 'creates the copy in the same tenant under the trimmed new name' {
            $Response = Invoke-AddCAPolicyClone -Request (New-CloneRequest -Body @{ newDisplayName = ' Require MFA - Copy ' })

            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            $Response.Body.Results | Should -Be "Successfully duplicated CA policy 'Require MFA' to 'Require MFA - Copy'"
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $uri -eq 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' -and $type -eq 'POST' -and $tenantid -eq 'contoso.com'
            }
            $script:PostedBody.displayName | Should -Be 'Require MFA - Copy'
        }

        It 'keeps every assignment, including app ids without a service principal' {
            $null = Invoke-AddCAPolicyClone -Request (New-CloneRequest)

            $script:PostedBody.conditions.users.excludeGroups | Should -Be @('group-guid')
            $script:PostedBody.conditions.applications.excludeApplications | Should -Be @('d4ebce55-015a-49b5-a083-c84d1797ae8c')
        }

        It 'links the source auth strength by id only' {
            $null = Invoke-AddCAPolicyClone -Request (New-CloneRequest)

            $Strength = $script:PostedBody.grantControls.authenticationStrength
            $Strength.id | Should -Be 'strength-guid'
            @($Strength.PSObject.Properties.Name) | Should -Be @('id')
            $script:PostedBody.grantControls.PSObject.Properties.Name | Should -Not -Contain 'authenticationStrength@odata.context'
        }

        It 'strips read-only properties' {
            $null = Invoke-AddCAPolicyClone -Request (New-CloneRequest)

            foreach ($Name in 'id', 'templateId', 'createdDateTime', 'modifiedDateTime') {
                $script:PostedBody.PSObject.Properties.Name | Should -Not -Contain $Name
            }
        }

        It 'sets state <Expected> for <Sent>' -ForEach @(
            @{ Sent = 'nothing'; State = $null; Expected = 'disabled' }
            @{ Sent = 'an autoComplete object'; State = [pscustomobject]@{ label = 'Report-only'; value = 'enabledForReportingButNotEnforced' }; Expected = 'enabledForReportingButNotEnforced' }
            @{ Sent = 'sameAsSource'; State = 'sameAsSource'; Expected = 'enabled' }
        ) {
            $Body = if ($null -ne $State) { @{ state = $State } } else { @{} }
            $null = Invoke-AddCAPolicyClone -Request (New-CloneRequest -Body $Body)

            $script:PostedBody.state | Should -Be $Expected
        }

        It 'logs once and returns 500 when the create fails' {
            Mock -CommandName New-GraphPOSTRequest -MockWith { throw 'Graph said no' }

            $Response = Invoke-AddCAPolicyClone -Request (New-CloneRequest)

            $Response.StatusCode | Should -Be ([HttpStatusCode]::InternalServerError)
            $Response.Body.Results | Should -Match "Require MFA.*Graph said no"
            Should -Invoke Write-LogMessage -Times 1 -Exactly
        }
    }
}
