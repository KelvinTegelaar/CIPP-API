function Invoke-ListAvailableTests {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Dashboard.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        # Get all test folders
        $TestsRoot = Join-Path $env:CIPPRootPath 'Modules\CIPPTests\Public\Tests'
        $TestFolders = [System.IO.Directory]::EnumerateDirectories($TestsRoot)
        $CustomTestsTable = Get-CippTable -tablename 'CustomPowershellScripts'
        $Filter = "PartitionKey eq 'CustomScript'"
        $AllScripts = Get-CIPPAzDataTableEntity @CustomTestsTable -Filter $Filter
        # Group by ScriptGuid and get latest version of each
        $LatestCustomScripts = $AllScripts |
            Group-Object -Property ScriptGuid |
            ForEach-Object {
                $_.Group | Sort-Object -Property Version -Descending | Select-Object -First 1
            }


        # Build identity tests array
        $IdentityTests = foreach ($TestFolder in $TestFolders) {
            $IdentityPath = Join-Path $TestFolder 'Identity'
            if (-not [System.IO.Directory]::Exists($IdentityPath)) {
                continue
            }
            $IdentityTestFiles = [System.IO.Directory]::EnumerateFiles($IdentityPath, '*.ps1', [System.IO.SearchOption]::TopDirectoryOnly)
            foreach ($TestFile in $IdentityTestFiles) {
                # Extract test ID from filename (e.g., Invoke-CippTestZTNA21772.ps1 -> ZTNA21772)
                $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($TestFile)
                if ($BaseName -match 'Invoke-CippTest(.+)$') {
                    $TestId = $Matches[1]

                    # Try to get test metadata from the file
                    $TestContent = [System.IO.File]::ReadAllText($TestFile)
                    $TestName = $TestId

                    # Try to extract Synopsis from comment-based help
                    if ($TestContent -match '\.SYNOPSIS\s+(.+?)(?=\s+\.|\s+#>|\s+\[)') {
                        $TestName = $Matches[1].Trim()
                    }

                    [PSCustomObject]@{
                        id         = $TestId
                        name       = $TestName
                        category   = 'Identity'
                        testFolder = [System.IO.Path]::GetFileName($TestFolder)
                    }
                }
            }
        }

        # Build device tests array
        $DevicesTests = foreach ($TestFolder in $TestFolders) {
            $DevicesPath = Join-Path $TestFolder 'Devices'
            if (-not [System.IO.Directory]::Exists($DevicesPath)) {
                continue
            }
            $DeviceTestFiles = [System.IO.Directory]::EnumerateFiles($DevicesPath, '*.ps1', [System.IO.SearchOption]::TopDirectoryOnly)
            foreach ($TestFile in $DeviceTestFiles) {
                $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($TestFile)
                if ($BaseName -match 'Invoke-CippTest(.+)$') {
                    $TestId = $Matches[1]

                    $TestContent = [System.IO.File]::ReadAllText($TestFile)
                    $TestName = $TestId

                    if ($TestContent -match '\.SYNOPSIS\s+(.+?)(?=\s+\.|\s+#>|\s+\[)') {
                        $TestName = $Matches[1].Trim()
                    }

                    [PSCustomObject]@{
                        id         = $TestId
                        name       = $TestName
                        category   = 'Devices'
                        testFolder = [System.IO.Path]::GetFileName($TestFolder)
                    }
                }
            }
        }

        # Build custom tests array from latest custom scripts
        $CustomTestsList = foreach ($CustomTest in @($LatestCustomScripts)) {
            $ScriptGuid = $CustomTest.ScriptGuid
            if ([string]::IsNullOrWhiteSpace($ScriptGuid)) {
                continue
            }

            $TestId = "CustomScript-$ScriptGuid"
            $TestName = if ([string]::IsNullOrWhiteSpace($CustomTest.ScriptName)) { $TestId } else { $CustomTest.ScriptName }

            [PSCustomObject]@{
                id             = $TestId
                name           = $TestName
                category       = 'Custom'
                testFolder     = 'Custom'
                scriptGuid     = $ScriptGuid
                description    = $CustomTest.Description ?? ''
                risk           = $CustomTest.Risk ?? 'Medium'
                enabled        = [bool]$CustomTest.Enabled
                alertOnFailure = [bool]$CustomTest.AlertOnFailure
                version        = $CustomTest.Version
            }
        }

        $Body = [PSCustomObject]@{
            IdentityTests = $IdentityTests
            DevicesTests  = $DevicesTests
            CustomTests   = @($CustomTestsList)
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = [PSCustomObject]@{
            Results = "Failed to list available tests: $($ErrorMessage.NormalizedError)"
        }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -InputObject $Body -Depth 10
        })
}
