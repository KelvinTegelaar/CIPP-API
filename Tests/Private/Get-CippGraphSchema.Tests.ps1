# Pester tests for the Graph schema lookup.
#
# These run against the real vendored CSDL rather than a fixture: the whole point of the
# lookup is to be right about Microsoft's actual metadata, and a hand-built fixture would
# only prove the parser agrees with itself.
#
# The namespace test is the one that matters. The beta document declares several different
# types called 'user' - the directory user, and a handful of usage-report users - so an
# index keyed on the short name lets a report type overwrite microsoft.graph.user, and
# 'users' then resolves to a 10-property object with no id on it. That is a wrong answer
# delivered confidently, which is worse than an error.

# Evaluated during discovery, not in BeforeAll: -Skip on a Describe is resolved before any
# BeforeAll runs, so a flag set there is always null and every test silently skips.
$MetadataMissing = -not (Test-Path (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'Config/graph-metadata/beta.xml'))

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CippGraphSchema.ps1')

    # the resolver reads Config/graph-metadata relative to $env:CIPPRootPath
    $script:PreviousRoot = $env:CIPPRootPath
    $env:CIPPRootPath = $BackendRoot
}

AfterAll { $env:CIPPRootPath = $script:PreviousRoot }

Describe 'Get-CippGraphSchema' -Skip:$MetadataMissing {

    Context 'entity set resolution' {
        It 'resolves users to the directory user, not a same-named report type' {
            $Schema = Get-CippGraphSchema -Endpoint 'users' -Version beta
            $Schema.entityType | Should -Be 'microsoft.graph.user'
            # the directory user has ~89 properties; the report types have ~10
            @($Schema.properties.Keys).Count | Should -BeGreaterThan 50
        }

        It 'includes properties inherited from the base type' {
            # id and deletedDateTime come from directoryObject, not from user
            $Schema = Get-CippGraphSchema -Endpoint 'users' -Version beta
            $Schema.properties.Keys | Should -Contain 'id'
            $Schema.properties.Keys | Should -Contain 'deletedDateTime'
        }

        It 'reports EDM types as JSON types' {
            $Schema = Get-CippGraphSchema -Endpoint 'users' -Version beta
            $Schema.properties['accountEnabled'] | Should -Be 'boolean'
            $Schema.properties['displayName'] | Should -Be 'string'
            $Schema.properties['assignedLicenses'] | Should -Match '\[\]$'   # a collection
        }

        It 'matches an entity set case-insensitively' {
            # CIPP writes 'serviceprincipals' where Graph declares 'servicePrincipals'
            (Get-CippGraphSchema -Endpoint 'serviceprincipals' -Version v1.0).entityType |
                Should -Be 'microsoft.graph.servicePrincipal'
        }

        It 'serves both API versions' {
            (Get-CippGraphSchema -Endpoint 'users' -Version 'v1.0').entityType | Should -Be 'microsoft.graph.user'
        }
    }

    Context 'path handling' {
        It 'follows a navigation property to its own type' {
            (Get-CippGraphSchema -Endpoint 'groups/{id}/members' -Version beta).entityType |
                Should -Be 'microsoft.graph.directoryObject'
        }

        It 'ignores key predicates, template placeholders and literal ids' {
            $Template = Get-CippGraphSchema -Endpoint 'users/{id}' -Version beta
            $Literal = Get-CippGraphSchema -Endpoint 'users/48d31887-5fad-4d73-a9f5-3c356e68a038' -Version beta
            $Template.entityType | Should -Be 'microsoft.graph.user'
            $Literal.entityType | Should -Be 'microsoft.graph.user'
        }

        It 'accepts a full Graph URL and strips the query string' {
            (Get-CippGraphSchema -Endpoint 'https://graph.microsoft.com/beta/users?$select=id' -Version beta).entityType |
                Should -Be 'microsoft.graph.user'
        }
    }

    Context 'errors are actionable' {
        It 'names the problem for an unknown entity set' {
            { Get-CippGraphSchema -Endpoint 'notathing' -Version beta } | Should -Throw '*not a known Graph entity set*'
        }

        It 'lists the alternatives for an unknown navigation property' {
            { Get-CippGraphSchema -Endpoint 'users/{id}/notareal' -Version beta } | Should -Throw '*Available*'
        }
    }
}
