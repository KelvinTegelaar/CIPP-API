# Pester tests for Invoke-AddAPDevice.
#
# Pins the Partner Center batch contract: an existing batch is appended to using Partner
# Center's own id spelling (escaped in the URL) with the same device shape the create path
# sends, an unknown name creates a batch, a slow import is a warning rather than a failure,
# and per-device upload errors surface as error rows.

BeforeAll {
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-AddAPDevice.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-AddAPDevice.ps1 under Modules/' }

    # Azure Functions binding types do not exist outside the Functions host - fake them.
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    # Stub every CIPP helper the function calls so Pester's Mock has a command to replace.
    # Declare the splatted keys so they bind as real parameters for ParameterFilter.
    function Get-Tenants { param($TenantFilter) }
    function New-GraphGetRequest { param($uri, $scope) }
    function New-GraphPOSTRequest { param($uri, $body, $scope, $returnHeaders) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }

    . $FunctionPath

    function New-APRequest {
        param($GroupName, $Devices)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddAPDevice' }
            Headers = @{ Authorization = 'token' }
            Body    = [pscustomobject]@{
                TenantFilter  = @{ value = 'contoso.onmicrosoft.com' }
                Groupname     = $GroupName
                autopilotData = $Devices
            }
        }
    }
}

Describe 'Invoke-AddAPDevice' {
    BeforeEach {
        $script:FinishedStatus = [pscustomobject]@{
            status        = 'finished'
            devicesStatus = @([pscustomobject]@{ serialNumber = 'SN-1'; status = 'finished' })
        }
        Mock -CommandName Start-Sleep -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { [pscustomobject]@{ NormalizedError = "$Exception" } }
        Mock -CommandName Get-Tenants -MockWith { [pscustomobject]@{ customerId = 'customer-guid' } }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/DeviceBatches' } -MockWith {
            [pscustomobject]@{ items = @([pscustomobject]@{ id = 'Sales Laptops' }) }
        }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/batchJobStatus/*' } -MockWith { $script:FinishedStatus }
        Mock -CommandName New-GraphPOSTRequest -MockWith { @{ Location = 'customers/customer-guid/batchJobStatus/job-1' } }

        $script:Devices = @(
            [pscustomobject]@{ SerialNumber = 'SN-1'; oemManufacturerName = ''; modelName = ''; productKey = ''; hardwareHash = 'HASH1'; groupTag = '' }
        )
    }

    It 'appends to an existing batch using Partner Center spelling, escaped, with the shared device shape' {
        $response = Invoke-AddAPDevice -Request (New-APRequest -GroupName 'sales laptops' -Devices $script:Devices) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter {
            $uri -like '*/deviceBatches/Sales%20Laptops/devices' -and
            $body -like '[[]*' -and
            $body -notmatch 'batchId' -and
            $body -notmatch '""' -and
            $body -match 'HASH1'
        }
        @($response.Body.Results)[0].state | Should -Be 'success'
    }

    It 'creates a new batch when the name is unknown' {
        $response = Invoke-AddAPDevice -Request (New-APRequest -GroupName 'Fresh Batch' -Devices $script:Devices) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter {
            $uri -like '*/customers/customer-guid/DeviceBatches' -and
            ($body | ConvertFrom-Json).batchId -eq 'Fresh Batch' -and
            @(($body | ConvertFrom-Json).devices).Count -eq 1
        }
    }

    It 'reports a still-running import as a warning instead of a failure' {
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/batchJobStatus/*' } -MockWith {
            [pscustomobject]@{ status = 'processing' }
        }

        $response = Invoke-AddAPDevice -Request (New-APRequest -GroupName 'sales laptops' -Devices $script:Devices) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $results = @($response.Body.Results)
        $results.Count | Should -Be 1
        $results[0].state | Should -Be 'warning'
        $results[0].resultText | Should -Match 'Sales Laptops'
        Should -Invoke New-GraphGetRequest -Times 15 -Exactly -ParameterFilter { $uri -like '*/batchJobStatus/*' }
    }

    It 'surfaces per-device upload errors with the Partner Center description' {
        $script:FinishedStatus = [pscustomobject]@{
            status        = 'finished_with_errors'
            devicesStatus = @([pscustomobject]@{ serialNumber = 'SN-1'; status = 'finished_with_errors'; errorCode = '806'; errorDescription = 'ZtdDeviceAlreadyAssigned' })
        }

        $response = Invoke-AddAPDevice -Request (New-APRequest -GroupName 'Fresh Batch' -Devices $script:Devices) -TriggerMetadata $null

        $result = @($response.Body.Results)[0]
        $result.state | Should -Be 'error'
        $result.resultText | Should -Match 'ZtdDeviceAlreadyAssigned'
        $result.copyField | Should -Be 'SN-1'
    }
}
