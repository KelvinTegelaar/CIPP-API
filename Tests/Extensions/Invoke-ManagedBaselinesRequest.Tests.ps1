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
            Invoke-ManagedBaselinesRequest -Path 'PartnerRecommendations' | Out-Null
        } finally {
            $env:CIPP_MANAGED_BASELINES_MOCK = $null
        }

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { "$Uri" -eq 'https://managedbaselines.cipp.app/api/PartnerRecommendations' }
    }

    It 'never calls out while the integration is not enabled' {
        Mock Get-CIPPAzDataTableEntity { }

        { Invoke-ManagedBaselinesRequest -Path 'PartnerTemplates' } | Should -Throw -ExceptionType ([System.ArgumentException])
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'sends the key and a JSON body to the service' {
        Invoke-ManagedBaselinesRequest -Path '/PartnerRequest' -Method POST -Body @{ requestId = 'abc-123' } | Out-Null

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            "$Uri" -eq 'https://managedbaselines.cipp.app/api/PartnerRequest' -and $Method -eq 'POST' -and
            $Headers['x-api-key'] -eq 'pester-key' -and $ContentType -eq 'application/json' -and
            ($Body | ConvertFrom-Json).requestId -eq 'abc-123'
        }
    }

    It 'sends an id as an escaped query parameter and keeps it out of the path' {
        Invoke-ManagedBaselinesRequest -Path 'PartnerRequest' -Method DELETE -Query @{ requestId = 'abc 123&x=1' } | Out-Null

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri.AbsoluteUri -eq 'https://managedbaselines.cipp.app/api/PartnerRequest?requestId=abc%20123%26x%3D1' -and $Method -eq 'DELETE'
        }
        { Invoke-ManagedBaselinesRequest -Path 'PartnerRequest?requestId=abc' } | Should -Throw -ExceptionType ([System.ArgumentException])
    }

    It 'points at the subscription when the key is refused' {
        Mock Invoke-RestMethod { throw (New-HttpError 401) }

        { Invoke-ManagedBaselinesRequest -Path 'PartnerAccount' } | Should -Throw -ExpectedMessage '*subscription has ended*'
    }

    It 'uses the override address when one is set' {
        $env:CIPP_MANAGED_BASELINES_URL = 'https://staging.example/'

        Invoke-ManagedBaselinesRequest -Path 'PartnerTemplates' | Out-Null

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { "$Uri" -eq 'https://staging.example/api/PartnerTemplates' }
    }

    It 'refuses to call out without a key' {
        Mock Get-ExtensionAPIKey { '' }

        { Invoke-ManagedBaselinesRequest -Path 'PartnerAccount' } | Should -Throw -ExceptionType ([System.ArgumentException])
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'turns status <Status> into <Type>' -ForEach @(
        @{ Status = 401; Type = [System.UnauthorizedAccessException] }
        @{ Status = 402; Type = [System.UnauthorizedAccessException] }
        @{ Status = 403; Type = [System.UnauthorizedAccessException] }
        @{ Status = 404; Type = [System.Management.Automation.ItemNotFoundException] }
    ) {
        Mock Invoke-RestMethod { throw (New-HttpError $Status) }

        { Invoke-ManagedBaselinesRequest -Path 'PartnerAccount' } | Should -Throw -ExceptionType $Type
    }

    It 'says the service could not be reached for any other failure' {
        Mock Invoke-RestMethod { throw (New-HttpError 500) }

        { Invoke-ManagedBaselinesRequest -Path 'PartnerAccount' } | Should -Throw -ExpectedMessage '*could not be reached*'
    }
}
