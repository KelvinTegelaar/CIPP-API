# Pester tests for New-CIPPTaskDeltaQuery
# Pins the mapping from a scheduled task's trigger to delta query parameters, since task creation,
# the rebuild in Get-DeltaQueryUrl and the offline repair script all depend on it producing the same
# key and filter. Includes the $select regression: 'ForEach-Object { } -join' binds -join as a
# ForEach-Object parameter and yields null, which silently dropped WatchedAttributes.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'New-CIPPTaskDeltaQuery.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate New-CIPPTaskDeltaQuery.ps1 under Modules/' }

    function New-GraphDeltaQuery { param($TenantFilter, $Resource, $Parameters, $PartitionKey, $DeltaUrl) }

    . $FunctionPath
}

Describe 'New-CIPPTaskDeltaQuery' {
    BeforeEach {
        Mock -CommandName New-GraphDeltaQuery -MockWith {
            @{ '@odata.deltaLink' = 'https://graph.microsoft.com/beta/users/delta?$deltatoken=abc' }
        }
    }

    Context 'Clear Immutable ID trigger' {
        It 'keys the delta query by the task RowKey and filters to the watched user' {
            $Trigger = [pscustomobject]@{
                Type               = 'DeltaQuery'
                DeltaResource      = 'users'
                ResourceFilter     = @('11111111-2222-3333-4444-555555555555')
                EventType          = 'deleted'
                ExecutePerResource = $true
                ExecutionMode      = 'once'
            }

            $null = New-CIPPTaskDeltaQuery -Trigger $Trigger -TenantFilter 'contoso.com' -PartitionKey 'task-row-key'

            Should -Invoke New-GraphDeltaQuery -Times 1 -Exactly -ParameterFilter {
                $Resource -eq 'users' -and
                $TenantFilter -eq 'contoso.com' -and
                $PartitionKey -eq 'task-row-key' -and
                $Parameters.'$filter' -eq "id eq '11111111-2222-3333-4444-555555555555'"
            }
        }

        It 'returns the delta link from New-GraphDeltaQuery' {
            $Trigger = [pscustomobject]@{ DeltaResource = 'users'; ResourceFilter = @('user-1') }
            $Result = New-CIPPTaskDeltaQuery -Trigger $Trigger -TenantFilter 'contoso.com' -PartitionKey 'pk'
            $Result.'@odata.deltaLink' | Should -Be 'https://graph.microsoft.com/beta/users/delta?$deltatoken=abc'
        }
    }

    Context 'Trigger stored as JSON on the task row' {
        It 'parses the JSON and unwraps .value-shaped fields' {
            $Trigger = '{"Type":{"value":"DeltaQuery"},"DeltaResource":{"value":"groups"},"ResourceFilter":[{"value":"a"},{"value":"b"}]}'

            $null = New-CIPPTaskDeltaQuery -Trigger $Trigger -TenantFilter 'contoso.com' -PartitionKey 'pk'

            Should -Invoke New-GraphDeltaQuery -Times 1 -Exactly -ParameterFilter {
                $Resource -eq 'groups' -and $Parameters.'$filter' -eq "id eq 'a' or id eq 'b'"
            }
        }
    }

    Context 'Watched attributes' {
        It 'sends WatchedAttributes as a comma joined $select' {
            $Trigger = [pscustomobject]@{
                DeltaResource     = 'users'
                WatchedAttributes = @(
                    [pscustomobject]@{ value = 'displayName' }
                    [pscustomobject]@{ value = 'mail' }
                )
            }

            $null = New-CIPPTaskDeltaQuery -Trigger $Trigger -TenantFilter 'contoso.com' -PartitionKey 'pk'

            Should -Invoke New-GraphDeltaQuery -Times 1 -Exactly -ParameterFilter {
                $Parameters.'$select' -eq 'displayName,mail'
            }
        }

        It 'accepts plain strings as well as .value objects' {
            $Trigger = [pscustomobject]@{ DeltaResource = 'users'; WatchedAttributes = @('displayName', 'mail') }

            $null = New-CIPPTaskDeltaQuery -Trigger $Trigger -TenantFilter 'contoso.com' -PartitionKey 'pk'

            Should -Invoke New-GraphDeltaQuery -Times 1 -Exactly -ParameterFilter {
                $Parameters.'$select' -eq 'displayName,mail'
            }
        }

        It 'omits $select when no attributes are watched' {
            $Trigger = [pscustomobject]@{ DeltaResource = 'users'; ResourceFilter = @('user-1') }

            $null = New-CIPPTaskDeltaQuery -Trigger $Trigger -TenantFilter 'contoso.com' -PartitionKey 'pk'

            Should -Invoke New-GraphDeltaQuery -Times 1 -Exactly -ParameterFilter {
                -not $Parameters.ContainsKey('$select')
            }
        }
    }

    Context 'Unusable trigger' {
        It 'throws when the trigger has no DeltaResource' {
            $Trigger = [pscustomobject]@{ Type = 'DeltaQuery'; EventType = 'deleted' }

            { New-CIPPTaskDeltaQuery -Trigger $Trigger -TenantFilter 'contoso.com' -PartitionKey 'pk' } |
                Should -Throw -ExpectedMessage '*has no DeltaResource*'
            Should -Invoke New-GraphDeltaQuery -Times 0 -Exactly
        }
    }
}
