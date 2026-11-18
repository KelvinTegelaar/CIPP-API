# Pester tests for Invoke-ExecUploadAppPackage: one raw block of a .intunewin payload per request,
# capped at 512 blocks of 8 MB, written as an uncommitted block of the package blob.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function New-CIPPAzStorageRequest { param($Service, $Resource, $Component, $Method, $QueryParams, $ContentType, $Body) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/Applications/Invoke-ExecUploadAppPackage.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    $script:PackageId = '6f1c2a3b-1111-2222-3333-444455556666'
    function New-BlockRequest {
        param($Index = 0, $Bytes = [byte[]](1..16), $PackageId = $script:PackageId)
        [pscustomobject]@{ Query = @{ packageId = $PackageId; index = "$Index" }; RawBody = $Bytes; Body = $null; Headers = @{}; Params = @{ CIPPEndpoint = 'ExecUploadAppPackage' } }
    }
}

Describe 'Invoke-ExecUploadAppPackage' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        Mock New-CIPPAzStorageRequest { $script:Calls.Add([pscustomobject]@{ Resource = $Resource; Component = $Component; QueryParams = $QueryParams; Body = $Body }); if ($Component -eq 'list') { @([pscustomobject]@{ Name = 'app-packages' }) } }
    }

    It 'writes a block under the package blob with a fixed-width block id' {
        $Response = Invoke-ExecUploadAppPackage -Request (New-BlockRequest -Index 7) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        $Put = $script:Calls.Where({ $_.QueryParams.comp -eq 'block' })[0]
        $Put.Resource | Should -Be "app-packages/$($script:PackageId)/IntunePackage.intunewin"
        [Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($Put.QueryParams.blockid)) | Should -Be '007'
        $Put.Body.Length | Should -Be 16
    }

    It 'creates the container on the first block only' {
        Mock New-CIPPAzStorageRequest { $script:Calls.Add([pscustomobject]@{ Resource = $Resource; Component = $Component; QueryParams = $QueryParams }); if ($Component -eq 'list') { @() } }

        $null = Invoke-ExecUploadAppPackage -Request (New-BlockRequest -Index 0) -TriggerMetadata $null
        $null = Invoke-ExecUploadAppPackage -Request (New-BlockRequest -Index 1) -TriggerMetadata $null

        $script:Calls.Where({ $_.QueryParams.restype -eq 'container' }).Count | Should -Be 1
    }

    It 'refuses <Case>' -ForEach @(
        @{ Case = 'a package id that is not a GUID'; Request = { New-BlockRequest -PackageId '../other' } }
        @{ Case = 'a body that is not raw bytes'; Request = { $r = New-BlockRequest; $r.RawBody = 'AQID'; $r } }
        @{ Case = 'an empty block'; Request = { New-BlockRequest -Bytes ([byte[]]::new(0)) } }
        @{ Case = 'a block over 8 MB'; Request = { New-BlockRequest -Bytes ([byte[]]::new(8MB + 1)) } }
        @{ Case = 'a block past the 4 GB cap'; Request = { New-BlockRequest -Index 512 } }
    ) {
        $Response = Invoke-ExecUploadAppPackage -Request (& $Request) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
        $script:Calls.Count | Should -Be 0
    }

    It 'reports raw-body support for <Runtime>' -ForEach @(
        # New-CippCoreRequest hands every endpoint [pscustomobject]$Request, so these are the shapes it sees.
        @{ Runtime = 'Craft with raw bodies'; Request = [pscustomobject]@{ Query = @{ capabilities = 'true' }; Body = $null; RawBody = $null; Headers = @{}; Params = @{} }; Expected = $true }
        @{ Runtime = 'Craft without raw bodies'; Request = [pscustomobject]@{ Query = @{ capabilities = 'true' }; Body = $null; Headers = @{}; Params = @{} }; Expected = $false }
        @{ Runtime = 'Azure Functions (RawBody is the body text)'; Request = [pscustomobject]@{ Query = @{}; Body = [pscustomobject]@{ capabilities = $true }; RawBody = '{"capabilities":true}'; Headers = @{}; Params = @{} }; Expected = $false }
    ) {
        (Invoke-ExecUploadAppPackage -Request $Request -TriggerMetadata $null).Body.Results.binaryBlocks | Should -Be $Expected
        $script:Calls.Count | Should -Be 0
    }

    It 'stores a base64 JSON block when the host cannot pass raw bodies' {
        $Request = [pscustomobject]@{ Query = @{}; RawBody = $null; Headers = @{}; Params = @{ CIPPEndpoint = 'ExecUploadAppPackage' }
            Body = [pscustomobject]@{ packageId = $script:PackageId; index = 2; data = [Convert]::ToBase64String([byte[]](1, 2, 3)) } }

        $Response = Invoke-ExecUploadAppPackage -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        $Put = $script:Calls.Where({ $_.QueryParams.comp -eq 'block' })[0]
        [Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($Put.QueryParams.blockid)) | Should -Be '002'
        $Put.Body | Should -Be ([byte[]](1, 2, 3))
    }

    It 'reports a storage failure as an error instead of success' {
        Mock New-CIPPAzStorageRequest { if ($QueryParams.comp -eq 'block') { throw 'Status 503' } }

        $Response = Invoke-ExecUploadAppPackage -Request (New-BlockRequest -Index 3) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([HttpStatusCode]::InternalServerError)
    }
}
