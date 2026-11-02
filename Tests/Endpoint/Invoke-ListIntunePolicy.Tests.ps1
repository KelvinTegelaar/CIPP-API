BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CIPPIntunePolicyReport { param($TenantFilter) }
    function New-GraphBulkRequest { param($Requests, $tenantid) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Test-IsGuid { param($String) $true }
    function Get-NormalizedError { param($Message) $Message }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntunePolicyListDefinitions.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPIntunePolicyListItem.ps1')
    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-ListIntunePolicy.ps1'
    $EndpointScript = [ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw))
    . $EndpointScript
}

Describe 'Invoke-ListIntunePolicy family parity' {
    BeforeEach {
        $script:EmptyFamily = $null
        Mock New-GraphBulkRequest {
            @($Requests | ForEach-Object {
                    $Value = if ($_.id -eq 'Groups') {
                        @([PSCustomObject]@{ id = 'group-1'; displayName = 'Group One' })
                    } elseif ($_.id -eq $script:EmptyFamily) {
                        $null
                    } else {
                        $Policy = [PSCustomObject]@{
                            id          = "$($_.id)-1"
                            displayName = "$($_.id) policy"
                            assignments = @(
                                [PSCustomObject]@{
                                    target = [PSCustomObject]@{
                                        '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                                        groupId       = 'group-1'
                                    }
                                }
                            )
                        }
                        if ($_.id -eq 'ManagedAppPolicies') {
                            $Policy | Add-Member -NotePropertyName '@odata.type' -NotePropertyValue '#microsoft.graph.androidManagedAppProtection'
                        }
                        @($Policy)
                    }

                    [PSCustomObject]@{
                        id     = $_.id
                        status = 200
                        body   = [PSCustomObject]@{ value = $Value }
                    }
                })
        }
    }

    It 'uses the canonical twelve families for live mode' {
        $Request = [PSCustomObject]@{
            Query = [PSCustomObject]@{
                TenantFilter = 'contoso.onmicrosoft.com'
            }
        }

        $Response = Invoke-ListIntunePolicy -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        $Response.Body | Should -HaveCount 12
        $Response.Body.URLName | Sort-Object | Should -Be ((Get-CIPPIntunePolicyListDefinitions).Id | Sort-Object)
        $Response.Body.PolicyAssignment | Select-Object -Unique | Should -Be 'Group One'
    }

    It 'continues when one successful family has no value collection' {
        $script:EmptyFamily = 'Intents'
        $Request = [PSCustomObject]@{
            Query = [PSCustomObject]@{
                TenantFilter = 'contoso.onmicrosoft.com'
            }
        }

        $Response = Invoke-ListIntunePolicy -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        $Response.Body | Should -HaveCount 11
        $Response.Body.URLName | Should -Not -Contain 'Intents'
        $Response.Body.URLName | Should -Contain 'ConfigurationPolicies'
    }

    It 'routes cached mode through the report reader without calling Graph' {
        Mock Get-CIPPIntunePolicyReport {
            @([PSCustomObject]@{ id = 'cached-1'; displayName = 'Cached policy' })
        }
        Mock New-GraphBulkRequest { throw 'Graph should not be called' }

        $Request = [PSCustomObject]@{
            Query = [PSCustomObject]@{
                TenantFilter = 'contoso.onmicrosoft.com'
                UseReportDB  = 'true'
            }
        }

        $Response = Invoke-ListIntunePolicy -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        $Response.Body.id | Should -Be 'cached-1'
        Should -Invoke Get-CIPPIntunePolicyReport -Times 1
        Should -Invoke New-GraphBulkRequest -Times 0
    }
}
