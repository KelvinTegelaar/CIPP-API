# The one function that talks to the Managed Baselines service. It sends the key and turns a
# refusal into a typed error.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-ExtensionAPIKey { param($Extension) }
    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    $script:EnabledConfig = [PSCustomObject]@{ config = '{"CyberDrainManagedBaselines":{"Enabled":true}}' }

    . (Join-Path $script:RepoRoot 'Modules/CippExtensions/Public/ManagedBaselines/Invoke-ManagedBaselinesRequest.ps1')

    function New-HttpError([int]$Status) {
        $Response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Status)
        [Microsoft.PowerShell.Commands.HttpResponseException]::new("Response status code does not indicate success: $Status", $Response)
    }

    $script:SavedRoot = $env:CIPPRootPath
    $env:CIPPRootPath = $script:RepoRoot
}

AfterAll {
    $env:CIPPRootPath = $script:SavedRoot
    $env:CIPP_MANAGED_BASELINES_URL = $null
}

Describe 'Invoke-ManagedBaselinesRequest against the service' {
    BeforeEach {
        $env:CIPP_MANAGED_BASELINES_URL = $null
        Mock Get-ExtensionAPIKey { 'pester-key' }
        Mock Invoke-RestMethod { [PSCustomObject]@{ ok = $true } }
        Mock Get-CIPPAzDataTableEntity { $script:EnabledConfig }
    }

    It 'has no built-in answers: an old mock switch changes nothing' {
        $env:CIPP_MANAGED_BASELINES_MOCK = 'true'
        try {
            Invoke-ManagedBaselinesRequest -Path 'recommendations' | Out-Null
        } finally {
            $env:CIPP_MANAGED_BASELINES_MOCK = $null
        }

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { "$Uri" -eq 'https://managedbaselines.cipp.app/api/recommendations' }
    }

    It 'never calls out while the integration is not enabled' {
        Mock Get-CIPPAzDataTableEntity { }

        { Invoke-ManagedBaselinesRequest -Path 'templates' } | Should -Throw -ExceptionType ([System.ArgumentException])
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'sends the key and a JSON body to the service' {
        Invoke-ManagedBaselinesRequest -Path '/requests' -Method POST -Body @{ requestId = 'abc-123' } | Out-Null

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            "$Uri" -eq 'https://managedbaselines.cipp.app/api/requests' -and $Method -eq 'POST' -and
            $Headers['x-api-key'] -eq 'pester-key' -and $ContentType -eq 'application/json' -and
            ($Body | ConvertFrom-Json).requestId -eq 'abc-123'
        }
    }

    It 'uses the override address when one is set' {
        $env:CIPP_MANAGED_BASELINES_URL = 'https://staging.example/'

        Invoke-ManagedBaselinesRequest -Path 'templates' | Out-Null

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { "$Uri" -eq 'https://staging.example/api/templates' }
    }

    It 'refuses to call out without a key' {
        Mock Get-ExtensionAPIKey { '' }

        { Invoke-ManagedBaselinesRequest -Path 'account' } | Should -Throw -ExceptionType ([System.ArgumentException])
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'turns status <Status> into <Type>' -ForEach @(
        @{ Status = 401; Type = [System.UnauthorizedAccessException] }
        @{ Status = 402; Type = [System.UnauthorizedAccessException] }
        @{ Status = 403; Type = [System.UnauthorizedAccessException] }
        @{ Status = 404; Type = [System.Management.Automation.ItemNotFoundException] }
    ) {
        Mock Invoke-RestMethod { throw (New-HttpError $Status) }

        { Invoke-ManagedBaselinesRequest -Path 'account' } | Should -Throw -ExceptionType $Type
    }

    It 'says the service could not be reached for any other failure' {
        Mock Invoke-RestMethod { throw (New-HttpError 500) }

        { Invoke-ManagedBaselinesRequest -Path 'account' } | Should -Throw -ExpectedMessage '*could not be reached*'
    }
}
